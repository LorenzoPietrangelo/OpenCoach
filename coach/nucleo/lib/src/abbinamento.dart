import 'dart:convert';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'dispositivi.dart';
import 'errori.dart';
import 'eventi.dart';
import 'modelli.dart';
import 'tempo.dart';

const _invitoNonValido = ErroreHttp(410, CodiceErrore.invitoNonValido);

/// Abbinamento dei telefoni, lato programma (§5.3).
class ServizioAbbinamento {
  ServizioAbbinamento(this._c);

  final ContestoCoach _c;

  Database get _db => _c.archivio.db;

  /// `POST /v1/abbinamento`: crea il dispositivo, emette il token e revoca
  /// l'eventuale telefono precedente dell'atleta.
  RispostaAbbinamento abbina(RichiestaAbbinamento richiesta) {
    final versioneApp = richiesta.dispositivo.versioneApp;
    if (confrontaVersioni(versioneApp, _c.versioneAppMinima) < 0) {
      throw const ErroreHttp(426, CodiceErrore.aggiornaApp);
    }
    final (risposta, evento) = _c.archivio.transazione(() => _abbina(richiesta));
    // Il servizio onion si ripubblica dopo l'invio della risposta, grazie
    // all'attesa del raggruppamento (§9.2).
    _c.segnalaChiaviCambiate();
    if (evento != null) _c.emetti(evento);
    return risposta;
  }

  /// `POST /v1/abbinamento/conferma`: il telefono usa ormai la propria
  /// chiave, quindi quella d'invito non serve più.
  void conferma(Dispositivo dispositivo) {
    _db.execute(
      "UPDATE inviti SET stato = 'usato', segreto = NULL, chiave_privata = NULL "
      "WHERE dispositivo_id = ? AND stato = 'in_abbinamento'",
      [dispositivo.id],
    );
    if (_db.updatedRows == 0) return;
    _c.segnalaChiaviCambiate();
    _c.emetti(AbbinamentoConfermato(dispositivo.atletaId, dispositivo.id));
  }

  (RispostaAbbinamento, EventoCoach?) _abbina(RichiestaAbbinamento r) {
    final ora = istante(_c.adesso());
    final invito = _db.select('SELECT * FROM inviti WHERE id = ?', [
      r.invitoId,
    ]).firstOrNull;
    if (invito == null) throw _invitoNonValido;
    final stato = invito['stato'] as String;
    final segreto = invito['segreto'] as String?;
    if ((stato != 'aperto' && stato != 'in_abbinamento') ||
        segreto == null ||
        (invito['scade_il'] as String).compareTo(ora) <= 0 ||
        !ugualiInTempoCostante(utf8.encode(segreto), utf8.encode(r.segreto))) {
      throw _invitoNonValido;
    }

    final atletaId = invito['atleta_id'] as String;
    final token = byteCasuali(32);
    final String dispositivoId;
    EventoCoach? evento;

    if (stato == 'in_abbinamento') {
      // L'app ripete la richiesta perché non ha ricevuto la risposta: stesso
      // dispositivo, token nuovo. Con un'altra chiave è un secondo telefono.
      final dispositivo = _db.select('SELECT * FROM dispositivi WHERE id = ?', [
        invito['dispositivo_id'],
      ]).firstOrNull;
      if (dispositivo == null || dispositivo['stato'] != 'attivo') {
        throw _invitoNonValido;
      }
      if (dispositivo['chiave_pubblica'] != r.chiaveDispositivo) {
        _c.emetti(InvitoContestato(atletaId, r.invitoId));
        throw const ErroreHttp(409, CodiceErrore.invitoInUso);
      }
      dispositivoId = dispositivo['id'] as String;
      _db.execute(
        'UPDATE dispositivi SET hash_token = ?, nome = ?, piattaforma = ?, '
        'versione_app = ? WHERE id = ?',
        [
          hashToken(token),
          r.dispositivo.nome,
          r.dispositivo.piattaforma,
          r.dispositivo.versioneApp,
          dispositivoId,
        ],
      );
    } else {
      dispositivoId = nuovoUuid();
      _db.execute(
        "UPDATE dispositivi SET stato = 'revocato', revocato_il = ? "
        "WHERE atleta_id = ? AND stato = 'attivo'",
        [ora, atletaId],
      );
      _db.execute(
        'INSERT INTO dispositivi (id, atleta_id, chiave_pubblica, hash_token, '
        'nome, piattaforma, versione_app, abbinato_il, stato) '
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'attivo')",
        [
          dispositivoId,
          atletaId,
          r.chiaveDispositivo,
          hashToken(token),
          r.dispositivo.nome,
          r.dispositivo.piattaforma,
          r.dispositivo.versioneApp,
          ora,
        ],
      );
      _db.execute(
        "UPDATE inviti SET stato = 'in_abbinamento', dispositivo_id = ? "
        'WHERE id = ?',
        [dispositivoId, r.invitoId],
      );
      evento = DispositivoAbbinato(atletaId, dispositivoId, r.dispositivo.nome);
    }

    final nomeAtleta = _db.select('SELECT nome FROM atleti WHERE id = ?', [
      atletaId,
    ]).first['nome'] as String;
    final risposta = RispostaAbbinamento(
      atletaId: atletaId,
      dispositivoId: dispositivoId,
      token: codificaBase32(token),
      nomeAtleta: nomeAtleta,
      nomeCoach: _c.nomeCoach,
    );
    return (risposta, evento);
  }
}
