import 'dart:convert';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'dispositivi.dart';
import 'errori.dart';
import 'eventi.dart';
import 'inviti.dart';
import 'modelli.dart';
import 'tempo.dart';

const _invitoNonValido = ErroreHttp(410, CodiceErrore.invitoNonValido);

/// Il telefono con cui il coach usa l'app del coach (§16): al massimo uno
/// attivo, in tabelle proprie, così il token di un atleta non vale mai qui.
class GestioneTelefonoCoach {
  GestioneTelefonoCoach(this._c, this._inviti);

  final ContestoCoach _c;
  final GestioneInviti _inviti;

  /// Il QR si mostra davanti al telefono: un'ora basta anche se il servizio
  /// deve ripubblicarsi con calma (§16.2).
  static const durataInvito = Duration(hours: 1);

  /// Ogni quanto registrare l'ultimo contatto: una scrittura sul disco a ogni
  /// richiesta non serve.
  static const _intervalloContatto = Duration(minutes: 1);

  Database get _db => _c.archivio.db;

  /// Il telefono collegato, se c'è.
  TelefonoCoach? attivo() {
    final riga = _db.select("SELECT * FROM telefoni_coach WHERE stato = 'attivo'").firstOrNull;
    return riga == null ? null : TelefonoCoach.daRiga(riga);
  }

  /// Crea il QR e annulla quello precedente.
  Future<InvitoTelefonoCoach> creaInvito() async {
    final coppia = await CoppiaX25519.genera();
    final id = codificaBase32(byteCasuali(16));
    final segreto = codificaBase32(byteCasuali(32));
    final creatoIl = _c.adesso().toUtc();
    final scadeIl = creatoIl.add(durataInvito);
    _c.archivio.transazione(() {
      _chiudi("stato IN ('aperto', 'in_abbinamento')", const [], StatoInvito.annullato);
      if (_inviti.contaChiaviAutorizzate() >= Limiti.chiaviAutorizzate) {
        throw const OperazioneNonValida('Raggiunto il numero massimo di telefoni e inviti attivi');
      }
      _db.execute(
        'INSERT INTO inviti_telefono_coach (id, segreto, chiave_privata, chiave_pubblica, '
        "creato_il, scade_il, stato) VALUES (?, ?, ?, ?, ?, ?, 'aperto')",
        [id, segreto, coppia.privataBase32, coppia.pubblicaBase32, istante(creatoIl), istante(scadeIl)],
      );
    });
    _c.segnalaChiaviCambiate();
    return InvitoTelefonoCoach(
      id: id,
      scadeIl: scadeIl,
      uri: UriTelefonoCoach(indirizzo: _c.indirizzo, id: id, segreto: segreto, chiave: coppia.privataBase32),
    );
  }

  /// Il QR ancora valido, se c'è.
  InvitoTelefonoCoach? invitoInCorso() {
    final riga = _db.select(
      'SELECT * FROM inviti_telefono_coach '
      "WHERE stato IN ('aperto', 'in_abbinamento') AND scade_il > ?",
      [istante(_c.adesso())],
    ).firstOrNull;
    if (riga == null) return null;
    final segreto = riga['segreto'] as String?;
    final chiave = riga['chiave_privata'] as String?;
    return InvitoTelefonoCoach(
      id: riga['id'] as String,
      scadeIl: leggiIstante(riga['scade_il'] as String),
      uri: riga['stato'] == 'aperto' && segreto != null && chiave != null
          ? UriTelefonoCoach(indirizzo: _c.indirizzo, id: riga['id'] as String, segreto: segreto, chiave: chiave)
          : null,
    );
  }

  /// Annulla il QR. Un telefono già collegato con esso resta collegato.
  void annullaInvito() {
    if (_chiudi("stato IN ('aperto', 'in_abbinamento')", const [], StatoInvito.annullato) > 0) {
      _c.segnalaChiaviCambiate();
    }
  }

  /// Chiude il QR scaduto; restituisce quanti ne ha chiusi.
  int chiudiScaduti() {
    final chiusi = _chiudi(
      "stato IN ('aperto', 'in_abbinamento') AND scade_il <= ?",
      [istante(_c.adesso())],
      StatoInvito.scaduto,
    );
    if (chiusi > 0) _c.segnalaChiaviCambiate();
    return chiusi;
  }

  /// Revoca il telefono: il token smette subito di valere e il servizio viene
  /// ripubblicato senza la sua chiave (§16.2).
  void revoca() {
    _revocaAttivo(istante(_c.adesso()));
    if (_db.updatedRows > 0) _c.segnalaChiaviCambiate();
  }

  /// Il telefono attivo che corrisponde all'intestazione `Authorization`,
  /// oppure null.
  TelefonoCoach? autentica(String? intestazione) {
    if (intestazione == null || !intestazione.startsWith('Bearer ')) return null;
    final token = decodificaChiave32(intestazione.substring(7).trim());
    if (token == null) return null;
    final riga = _db.select(
      "SELECT * FROM telefoni_coach WHERE hash_token = ? AND stato = 'attivo'",
      [hashToken(token)],
    ).firstOrNull;
    if (riga == null) return null;
    final telefono = TelefonoCoach.daRiga(riga);
    final ora = _c.adesso();
    final ultimo = telefono.ultimoContatto;
    if (ultimo == null || ora.difference(ultimo) >= _intervalloContatto) {
      _db.execute('UPDATE telefoni_coach SET ultimo_contatto = ? WHERE id = ?', [istante(ora), telefono.id]);
    }
    return telefono;
  }

  /// `POST /v1/coach/abbinamento`: crea il telefono, emette il token e revoca
  /// quello precedente.
  RispostaAbbinamentoTelefono abbina(RichiestaAbbinamento richiesta) {
    if (confrontaVersioni(richiesta.dispositivo.versioneApp, _c.versioneAppMinima) < 0) {
      throw const ErroreHttp(426, CodiceErrore.aggiornaApp);
    }
    final (risposta, evento) = _c.archivio.transazione(() => _abbina(richiesta));
    // Il servizio onion si ripubblica dopo l'invio della risposta, grazie
    // all'attesa del raggruppamento (§9.2).
    _c.segnalaChiaviCambiate();
    if (evento != null) _c.emetti(evento);
    return risposta;
  }

  /// `POST /v1/coach/abbinamento/conferma`: il telefono usa ormai la propria
  /// chiave, quindi quella del QR non serve più.
  void conferma(TelefonoCoach telefono) {
    _db.execute(
      "UPDATE inviti_telefono_coach SET stato = 'usato', segreto = NULL, chiave_privata = NULL "
      "WHERE telefono_id = ? AND stato = 'in_abbinamento'",
      [telefono.id],
    );
    if (_db.updatedRows == 0) return;
    _c.segnalaChiaviCambiate();
    _c.emetti(const TelefonoCoachConfermato());
  }

  (RispostaAbbinamentoTelefono, EventoCoach?) _abbina(RichiestaAbbinamento r) {
    final ora = istante(_c.adesso());
    final invito = _db.select('SELECT * FROM inviti_telefono_coach WHERE id = ?', [r.invitoId]).firstOrNull;
    if (invito == null) throw _invitoNonValido;
    final stato = invito['stato'] as String;
    final segreto = invito['segreto'] as String?;
    if ((stato != 'aperto' && stato != 'in_abbinamento') ||
        segreto == null ||
        (invito['scade_il'] as String).compareTo(ora) <= 0 ||
        !ugualiInTempoCostante(utf8.encode(segreto), utf8.encode(r.segreto))) {
      throw _invitoNonValido;
    }

    final token = byteCasuali(32);
    final String telefonoId;
    EventoCoach? evento;
    if (stato == 'in_abbinamento') {
      // La risposta si è persa: stesso telefono, token nuovo. Con un'altra
      // chiave è un secondo telefono.
      final telefono = _db.select('SELECT * FROM telefoni_coach WHERE id = ?', [invito['telefono_id']]).firstOrNull;
      if (telefono == null || telefono['stato'] != 'attivo') throw _invitoNonValido;
      if (telefono['chiave_pubblica'] != r.chiaveDispositivo) {
        _c.emetti(const TelefonoCoachContestato());
        throw const ErroreHttp(409, CodiceErrore.invitoInUso);
      }
      telefonoId = telefono['id'] as String;
      _db.execute(
        'UPDATE telefoni_coach SET hash_token = ?, nome = ?, piattaforma = ?, versione_app = ? WHERE id = ?',
        [hashToken(token), r.dispositivo.nome, r.dispositivo.piattaforma, r.dispositivo.versioneApp, telefonoId],
      );
    } else {
      telefonoId = nuovoUuid();
      _revocaAttivo(ora);
      _db.execute(
        'INSERT INTO telefoni_coach (id, chiave_pubblica, hash_token, nome, piattaforma, versione_app, '
        "abbinato_il, stato) VALUES (?, ?, ?, ?, ?, ?, ?, 'attivo')",
        [
          telefonoId,
          r.chiaveDispositivo,
          hashToken(token),
          r.dispositivo.nome,
          r.dispositivo.piattaforma,
          r.dispositivo.versioneApp,
          ora,
        ],
      );
      _db.execute(
        "UPDATE inviti_telefono_coach SET stato = 'in_abbinamento', telefono_id = ? WHERE id = ?",
        [telefonoId, r.invitoId],
      );
      evento = TelefonoCoachCollegato(r.dispositivo.nome);
    }
    return (
      RispostaAbbinamentoTelefono(telefonoId: telefonoId, token: codificaBase32(token), nomeCoach: _c.nomeCoach),
      evento,
    );
  }

  void _revocaAttivo(String ora) => _db.execute(
    "UPDATE telefoni_coach SET stato = 'revocato', revocato_il = ? WHERE stato = 'attivo'",
    [ora],
  );

  /// Chiude gli inviti che rispettano [condizione] e cancella i loro segreti.
  int _chiudi(String condizione, List<Object?> parametri, StatoInvito stato) {
    _db.execute(
      'UPDATE inviti_telefono_coach SET stato = ?, segreto = NULL, chiave_privata = NULL '
      'WHERE $condizione',
      [stato.nome, ...parametri],
    );
    return _db.updatedRows;
  }
}
