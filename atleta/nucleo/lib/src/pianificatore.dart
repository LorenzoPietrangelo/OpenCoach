import 'dart:async';

import 'contesto.dart';
import 'modelli.dart';
import 'sincronizzazione.dart';

/// Quando parte la sync con l'app in primo piano (§7.4): all'apertura e al
/// ritorno in primo piano, subito dopo ogni modifica dei log, con «Sincronizza
/// ora» e ogni 10 minuti. Se il coach non risponde ritenta dopo 30 s, 2 e 5
/// minuti, poi aspetta l'occasione successiva.
///
/// In background la sync la chiede il sistema operativo (WorkManager,
/// BGAppRefreshTask) con `NucleoAtleta.sincronizzaInBackground`.
class PianificatoreSync {
  PianificatoreSync(this._c, this._motore);

  static const periodo = Duration(minutes: 10);

  static const ritentativi = [
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

  final ContestoAtleta _c;
  final MotoreSync _motore;
  var _primoPiano = false;
  Timer? _periodico;
  final _timerRitentativi = <int, Timer>{};

  /// Indice in [ritentativi] della prossima attesa, per ogni coach.
  final _prossimo = <int, int>{};

  /// Cresce a ogni occasione nuova: gli esiti delle sync partite prima non
  /// decidono più i ritentativi.
  final _generazione = <int, int>{};
  final _inVolo = <Future<void>>{};

  bool get inPrimoPiano => _primoPiano;

  /// All'apertura dell'app e al ritorno in primo piano.
  void entraInPrimoPiano() {
    _primoPiano = true;
    _armaPeriodico();
    _tutti();
  }

  /// L'app va in background: niente più sync automatiche; Tor si ferma appena
  /// finiscono quelle in corso, salvo che l'app torni in primo piano.
  Future<void> vaiInBackground() async {
    ferma();
    await _motore.attendiTutte();
    if (!_primoPiano) await _c.tor.ferma();
  }

  /// Un log è stato salvato, modificato o eliminato.
  void logCambiato(int coachId) {
    if (_primoPiano) _occasione(coachId);
  }

  /// Il sistema operativo segnala che la rete è tornata.
  void reteTornata() {
    if (_primoPiano) _tutti();
  }

  /// Tasto «Sincronizza ora» o trascinamento per aggiornare.
  Future<EsitoSync> sincronizzaOra(int coachId) => _occasione(coachId);

  Future<List<EsitoSync>> sincronizzaTuttiOra() =>
      Future.wait([for (final coach in _c.coachAttivi()) _occasione(coach.id)]);

  /// Aspetta che finiscano le sync avviate dal pianificatore.
  Future<void> attendi() async {
    while (_inVolo.isNotEmpty) {
      await Future.wait(_inVolo.toList());
    }
    await _motore.attendiTutte();
  }

  /// Ferma la sync periodica e i ritentativi.
  void ferma() {
    _primoPiano = false;
    _periodico?.cancel();
    _periodico = null;
    for (final timer in _timerRitentativi.values) {
      timer.cancel();
    }
    _timerRitentativi.clear();
    _prossimo.clear();
  }

  void _armaPeriodico() {
    _periodico?.cancel();
    _periodico = _c.orologio.timer(periodo, () {
      if (!_primoPiano) return;
      _armaPeriodico();
      _tutti();
    });
  }

  void _tutti() {
    for (final coach in _c.coachAttivi()) {
      _occasione(coach.id);
    }
  }

  Future<EsitoSync> _occasione(int coachId) {
    _timerRitentativi.remove(coachId)?.cancel();
    _prossimo[coachId] = 0;
    final generazione = _generazione[coachId] =
        (_generazione[coachId] ?? 0) + 1;
    return _avvia(coachId, generazione);
  }

  Future<EsitoSync> _avvia(int coachId, int generazione) {
    final sync = _motore.sincronizza(coachId).then((esito) {
      _dopo(esito, generazione);
      return esito;
    });
    final traccia = sync.then<void>((_) {});
    _inVolo.add(traccia);
    traccia.whenComplete(() => _inVolo.remove(traccia)).ignore();
    return sync;
  }

  void _dopo(EsitoSync esito, int generazione) {
    final id = esito.coachId;
    if (_generazione[id] != generazione) return;
    final indice = _prossimo[id];
    if (esito.riuscita ||
        !esito.problema!.temporaneo ||
        !_primoPiano ||
        indice == null ||
        indice >= ritentativi.length) {
      _prossimo.remove(id);
      return;
    }
    _prossimo[id] = indice + 1;
    _timerRitentativi[id]?.cancel();
    _timerRitentativi[id] = _c.orologio.timer(ritentativi[indice], () {
      _timerRitentativi.remove(id);
      if (_primoPiano && _generazione[id] == generazione) {
        _avvia(id, generazione);
      }
    });
  }
}
