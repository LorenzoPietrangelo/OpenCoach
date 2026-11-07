import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:protocollo/protocollo.dart';

import 'annunci.dart';
import 'cassaforte.dart';
import 'coda_messaggi.dart';
import 'collegamento.dart';
import 'fonte_dati.dart';
import 'modelli.dart';

/// L'app senza interfaccia: il telefono collegato, l'elenco degli atleti e il
/// ciclo che tiene i dati aggiornati in primo piano (§16.4). Le schermate
/// ascoltano questo oggetto; i dati di un atleta li chiedono a [fonte] e li
/// rileggono quando [generazione] cambia. Nomi e messaggi stanno solo in memoria.
class StatoCoach extends ChangeNotifier {
  StatoCoach({
    required Cassaforte cassaforte,
    required this.collegamento,
    this.creaFonte,
    this.attese = const [Duration(seconds: 30), Duration(minutes: 2), Duration(minutes: 5)],
    this.atteseConferma = const [
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 30),
      Duration(minutes: 1),
    ],
    this.atteseBackground = const [Duration(seconds: 5), Duration(seconds: 10), Duration(seconds: 20)],
    void Function(String)? registra,
  }) : coda = CodaMessaggi(cassaforte),
       _annunci = RegistroAnnunci(cassaforte),
       _registra = registra ?? ((_) {});

  final ServizioCollegamento collegamento;
  final CodaMessaggi coda;
  final RegistroAnnunci _annunci;
  final void Function(String) _registra;

  /// Sostituisce [ServizioCollegamento.fonte], nei test.
  final FonteDatiCoach Function(Credenziali)? creaFonte;

  /// Pause dopo un errore: il PC può essere spento per ore (§16.4).
  final List<Duration> attese;

  /// Pause mentre il telefono finisce di collegarsi: il PC ripubblica il
  /// servizio in pochi minuti (§5.3, punto 6).
  final List<Duration> atteseConferma;

  /// Pause tra i tentativi di un controllo in background.
  final List<Duration> atteseBackground;

  Credenziali? _credenziali;
  FonteDatiCoach? _fonte;
  var _atleti = const <RiepilogoAtleta>[];
  String? _impronta;
  ProblemaCoach? _problema;
  var _caricato = false;
  var _generazione = 0;
  var _primoPiano = false;

  /// Identifica il ciclo in corso: cambia per fermarlo.
  var _ciclo = 0;
  Completer<void>? _pausa;

  Credenziali? get credenziali => _credenziali;
  bool get collegato => _credenziali != null;

  /// Il telefono aspetta ancora che il PC accetti la sua chiave.
  bool get inCollegamento => _credenziali != null && !_credenziali!.confermato;

  FonteDatiCoach get fonte => _fonte!;
  List<RiepilogoAtleta> get atleti => _atleti;

  /// L'elenco è arrivato almeno una volta dal PC.
  bool get caricato => _caricato;

  /// Perché il PC non risponde; null se va tutto bene.
  ProblemaCoach? get problema => _problema;

  /// Cresce ogni volta che i dati sul PC cambiano.
  int get generazione => _generazione;

  RiepilogoAtleta? atleta(String id) => _atleti.where((a) => a.id == id).firstOrNull;

  Future<void> carica() async {
    await coda.carica();
    final credenziali = await collegamento.caricaCredenziali();
    if (credenziali != null) _usa(credenziali);
  }

  void _usa(Credenziali credenziali) {
    _credenziali = credenziali;
    _fonte = creaFonte?.call(credenziali) ?? collegamento.fonte(credenziali, registra: _registra);
  }

  /// Il QR è stato letto e confermato: da qui il telefono è collegato.
  Future<void> usaCredenziali(Credenziali credenziali) async {
    _usa(credenziali);
    _problema = null;
    notifyListeners();
    if (_primoPiano) _avviaCiclo();
  }

  /// L'app è visibile: i dati si tengono aggiornati.
  void entraInPrimoPiano() {
    _primoPiano = true;
    if (collegato) _avviaCiclo();
  }

  /// L'app non è più visibile: niente rete, se non per i controlli in
  /// background.
  Future<void> vaiInBackground() async {
    _primoPiano = false;
    _ferma();
    await _fonte?.fermaRete();
  }

  /// Il coach vuole riprovare subito.
  void riprova() {
    // Senza impronta il ciclo rilegge subito invece di aspettare novità.
    _impronta = null;
    if (_pausa case final pausa? when !pausa.isCompleted) {
      pausa.complete();
    } else if (_primoPiano && collegato) {
      _avviaCiclo();
    }
  }

  void _ferma() {
    _ciclo++;
    _svegliaPausa();
  }

  void _svegliaPausa() {
    if (_pausa case final pausa? when !pausa.isCompleted) pausa.complete();
  }

  void _avviaCiclo() {
    _ciclo++;
    _svegliaPausa();
    unawaited(_gira(_ciclo));
  }

  Future<void> _gira(int ciclo) async {
    var errori = 0;
    while (ciclo == _ciclo && collegato) {
      try {
        await _conferma();
        if (ciclo != _ciclo) return;
        await coda.svuota(fonte);
        final impronta = _impronta;
        if (impronta == null || !_caricato) {
          await _rileggi();
        } else {
          final novita = await fonte.attendi(impronta);
          if (ciclo != _ciclo) return;
          if (novita) await _rileggi();
        }
        if (ciclo != _ciclo) return;
        errori = 0;
        if (_problema != null) {
          _problema = null;
          notifyListeners();
        }
      } on ErroreCoach catch (e) {
        if (ciclo != _ciclo) return;
        if (e.problema == ProblemaCoach.revocato) {
          await _dimentica();
          return;
        }
        if (_problema != e.problema) {
          _problema = e.problema;
          notifyListeners();
        }
        final lista = inCollegamento ? atteseConferma : attese;
        await _aspetta(lista[min(errori, lista.length - 1)]);
        errori++;
      }
    }
  }

  Future<void> _aspetta(Duration durata) async {
    final pausa = _pausa = Completer<void>();
    final timer = Timer(durata, () {
      if (!pausa.isCompleted) pausa.complete();
    });
    await pausa.future;
    timer.cancel();
  }

  /// Dice al PC che il telefono usa la propria chiave. Se il PC era già
  /// d'accordo non cambia niente.
  Future<void> _conferma() async {
    final credenziali = _credenziali;
    if (credenziali == null || credenziali.confermato) return;
    await fonte.confermaCollegamento();
    final confermate = credenziali.confermate();
    await collegamento.salvaCredenziali(confermate);
    if (identical(_credenziali, credenziali)) _credenziali = confermate;
    notifyListeners();
  }

  Future<void> _rileggi() async {
    final elenco = await fonte.atleti();
    _atleti = elenco.atleti;
    _impronta = elenco.impronta;
    _caricato = true;
    _generazione++;
    // Il coach li sta guardando: non vanno annunciati dopo.
    await _annunci.ricorda(elenco.atleti);
    notifyListeners();
  }

  /// Scrive un messaggio: entra in coda e parte subito, se si può.
  Future<void> scrivi(String atletaId, String testo) async {
    final pulito = testo.trim();
    if (pulito.isEmpty) return;
    await coda.aggiungi(
      MessaggioInCoda(id: nuovoUuid(), atletaId: atletaId, testo: pulito, scrittoIl: DateTime.now()),
    );
    notifyListeners();
    unawaited(_mandaCoda());
  }

  Future<void> _mandaCoda() async {
    try {
      await coda.svuota(fonte);
      _problema = null;
    } on ErroreCoach catch (e) {
      // Il coach lo sa subito, senza aspettare la fine dell'attesa in corso. Il
      // messaggio resta in coda: ci pensa il ciclo.
      _registra('Messaggi in coda: ${e.problema.name}');
      if (e.problema == ProblemaCoach.revocato) {
        await _dimentica();
        return;
      }
      _problema = e.problema;
    }
    _generazione++;
    notifyListeners();
  }

  /// Il coach rinuncia a un messaggio che il PC ha rifiutato.
  Future<void> togliDallaCoda(String id) async {
    await coda.togli(id);
    notifyListeners();
  }

  /// Segna letta la chat: il contatore cambia subito anche nell'elenco.
  Future<void> segnaLetti(String atletaId) async {
    if ((atleta(atletaId)?.nonLetti ?? 0) == 0) return;
    await fonte.segnaLetti(atletaId);
    riprova();
  }

  /// Il controllo in background (§16.4): manda la coda e dice cosa annunciare.
  /// Con l'app in primo piano il coach vede già tutto, e non si annuncia niente.
  Future<List<Annuncio>> controllaInBackground() async {
    if (!collegato) return const [];
    if (_primoPiano) return const [];
    try {
      for (var tentativo = 0; ; tentativo++) {
        try {
          await _conferma();
          await coda.svuota(fonte);
          final elenco = await fonte.atleti();
          return await _annunci.confronta(elenco.atleti);
        } on ErroreCoach catch (e) {
          _registra('Controllo in background: ${e.problema.name}');
          if (e.problema == ProblemaCoach.revocato) {
            await _dimentica();
            return const [];
          }
          // Tor appena riacceso può non avere ancora i circuiti: qualche
          // tentativo ravvicinato, poi tocca al prossimo controllo.
          final ritentabile = e.problema == ProblemaCoach.irraggiungibile ||
              e.problema == ProblemaCoach.chiaveRifiutata ||
              e.problema == ProblemaCoach.occupato;
          if (!ritentabile || tentativo >= atteseBackground.length || _primoPiano || !collegato) return const [];
          await Future<void>.delayed(atteseBackground[tentativo]);
        }
      }
    } finally {
      if (!_primoPiano) await _fonte?.fermaRete();
    }
  }

  /// Il coach scollega il telefono dall'app. Se il PC non risponde il telefono
  /// dimentica lo stesso: il coach lo revoca poi dal PC.
  Future<void> scollega() async {
    try {
      await _fonte?.scollega();
    } on ErroreCoach catch (e) {
      _registra('Scollegamento non arrivato al PC: ${e.problema.name}');
    }
    await _dimentica();
  }

  Future<void> _dimentica() async {
    _ferma();
    await coda.cancellaTutto();
    await _annunci.cancella();
    await collegamento.cancellaCredenziali();
    _credenziali = null;
    _fonte = null;
    _atleti = const [];
    _impronta = null;
    _caricato = false;
    _problema = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _ferma();
    super.dispose();
  }
}
