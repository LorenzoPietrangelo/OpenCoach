import 'dart:async';
import 'dart:io';

import 'package:protocollo/protocollo.dart';
import 'package:trasporto_tor/trasporto_tor.dart';

import 'contesto.dart';
import 'errori.dart';
import 'modelli.dart';
import 'problemi.dart';
import 'sincronizzazione.dart';
import 'tempo.dart';

/// Coach a cui il telefono è o è stato abbinato (§10.2). L'app può essere
/// abbinata a più coach insieme; schede e log restano separati per coach.
class Collegamenti {
  Collegamenti(this._c, this._motore, {void Function(int coachId)? datiCancellati})
    : _datiCancellati = datiCancellati;

  final ContestoAtleta _c;
  final MotoreSync _motore;

  /// Cancella i file del coach fuori dall'archivio, come i video.
  final void Function(int coachId)? _datiCancellati;

  /// Quanto [scollega] aspetta il coach, avvio di Tor compreso, prima di
  /// scollegare il telefono senza avvisarlo. Con il PC spento la
  /// connessione arriverebbe al timeout di 90 s (§6.2), troppo per un
  /// atleta che aspetta davanti a uno spinner.
  var attesaAvviso = const Duration(seconds: 20);

  /// Tutti i collegamenti, compresi quelli chiusi, per nome del coach.
  List<CoachCollegato> elenco() => [
    for (final riga in _c.db.select(
      '$selezioneCoach ORDER BY coach.nome_coach COLLATE NOCASE, coach.id',
    ))
      CoachCollegato.daRiga(riga),
  ];

  List<CoachCollegato> attivi() => _c.coachAttivi();

  CoachCollegato? cerca(int coachId) => _c.coach(coachId);

  /// Scollega il telefono dal coach (§10.2): chiama `DELETE /v1/dispositivo`
  /// se il coach è raggiungibile, poi smette di sincronizzare e cancella
  /// chiave e token. Schede e log restano finché l'atleta, dopo conferma, non
  /// li cancella con [cancellaDati].
  ///
  /// Restituisce vero se il coach ha ricevuto lo scollegamento; altrimenti il
  /// dispositivo resta attivo sul suo PC finché non lo revoca lui. I log
  /// ancora in coda non arrivano più al coach.
  ///
  /// Una sync in corso con il coach si ferma subito invece di essere
  /// aspettata: dopo l'abbinamento la conferma si ritenta per minuti.
  Future<bool> scollega(int coachId) {
    _motore.interrompi(coachId);
    return _motore.inEsclusiva(coachId, () => _scollega(coachId));
  }

  Future<bool> _scollega(int coachId) async {
    // Le operazioni in coda prima di questa sono già finite.
    _motore.riprendi(coachId);
    final coach = _c.coach(coachId);
    if (coach == null) throw const OperazioneNonAmmessa('Coach inesistente');
    final avvisato =
        coach.stato == StatoCollegamento.attivo && await _avvisaCoach(coach);
    _c.db.execute(
      "UPDATE coach SET stato = 'scollegato', problema = ?, problema_il = ? "
      "WHERE id = ? AND stato = 'attivo'",
      [ProblemaSync.scollegato.name, istante(_c.orologio.adesso()), coachId],
    );
    await _c.eliminaCredenziali(coachId);
    await _c.rimuoviChiaveSeInutile(coach.indirizzo);
    _c.segnala(coachId);
    return avvisato;
  }

  /// Cancella dal telefono schede e log di un coach con cui il collegamento
  /// è chiuso (§10.2, §11.3).
  Future<void> cancellaDati(int coachId) =>
      _motore.inEsclusiva(coachId, () async {
        final coach = _c.coach(coachId);
        if (coach == null) return;
        if (coach.stato == StatoCollegamento.attivo) {
          throw const OperazioneNonAmmessa(
            'Prima di cancellare i dati bisogna scollegarsi dal coach',
          );
        }
        _c.db.execute('DELETE FROM coach WHERE id = ?', [coachId]);
        _datiCancellati?.call(coachId);
        await _c.eliminaCredenziali(coachId);
        _c.segnala(coachId);
      });

  /// `DELETE /v1/dispositivo`; vero se il coach l'ha ricevuto.
  Future<bool> _avvisaCoach(CoachCollegato coach) async {
    final credenziali = await _c.credenziali(coach.id);
    if (credenziali == null || !await _c.rete.disponibile()) return false;
    HttpClient? http;
    var scaduto = false;
    Future<void> avvisa() async {
      await _c.tor.avvia();
      // Scaduta l'attesa, scollega toglie la chiave del coach da Tor: non va
      // rimessa.
      if (scaduto) return;
      await _c.assicuraChiave(coach.indirizzo, credenziali.chiave);
      if (scaduto) {
        // Rimessa mentre scollega la toglieva.
        await _c.rimuoviChiaveSeInutile(coach.indirizzo);
        return;
      }
      http = _c.tor.creaHttpClient();
      await ClienteApi(
        indirizzo: coach.indirizzo,
        http: http!,
        token: credenziali.token,
      ).scollega();
    }

    final avviso = avvisa();
    // Scaduta l'attesa, l'avviso si interrompe quando il finally chiude il
    // client: il suo errore non interessa più a nessuno.
    avviso.ignore();
    try {
      await avviso.timeout(attesaAvviso);
      return true;
    } on TimeoutException {
      scaduto = true;
      _c.registra(
        'Scollegamento non comunicato al coach: nessuna risposta in '
        '${attesaAvviso.inSeconds} s',
      );
      return false;
    } on TorNonParte {
      return false;
    } catch (e) {
      final guasto = classifica(e);
      if (guasto == null) rethrow;
      // Con 401 il coach aveva già revocato il dispositivo.
      if (guasto.errore?.stato == 401) return true;
      _c.registra('Scollegamento non comunicato al coach: $e');
      return false;
    } finally {
      http?.close(force: true);
    }
  }
}
