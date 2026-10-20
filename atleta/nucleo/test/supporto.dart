import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

/// Rete simulata: un orologio comune, i programmi dei coach in memoria con
/// il server HTTP vero e i telefoni degli atleti, ciascuno con il proprio
/// Tor finto.
class Ambiente {
  final orologio = OrologioFinto();
  final _pc = <String, PcCoach>{};
  final _telefoni = <Telefono>[];

  Future<PcCoach> avviaCoach({
    String nome = 'Marco Bianchi',
    int? budgetPagina,
  }) async {
    final pc = await PcCoach._avvia(
      orologio,
      nome: nome,
      budgetPagina: budgetPagina,
    );
    _pc[pc.indirizzo] = pc;
    return pc;
  }

  Telefono telefono({
    String nome = 'Pixel 8',
    String versioneApp = '1.0.0',
    int logPerRichiesta = Limiti.logPerRichiesta,
  }) {
    final telefono = Telefono._(
      this,
      nome: nome,
      versioneApp: versioneApp,
      logPerRichiesta: logPerRichiesta,
    );
    _telefoni.add(telefono);
    return telefono;
  }

  /// Abbina [telefono] all'atleta con un invito nuovo, fino alla prima sync.
  Future<CoachCollegato> abbina(
    Telefono telefono,
    PcCoach pc,
    String atletaId,
  ) async {
    final invito = await telefono.nucleo.leggiInvito(await pc.invito(atletaId));
    return invito.collega();
  }

  Future<void> chiudi() async {
    for (final telefono in _telefoni) {
      await telefono.chiudi();
    }
    for (final pc in _pc.values) {
      await pc.chiudi();
    }
  }
}

/// Orologio controllato dal test, condiviso da app e programmi del coach:
/// le attese dell'app fanno passare il tempo anche per i coach.
class OrologioFinto implements Orologio {
  var ora = DateTime.utc(2026, 10, 18, 12);
  final _timer = <TimerFinto>[];

  /// Attese chieste dall'app, in ordine.
  final attese = <Duration>[];

  @override
  DateTime adesso() => ora;

  @override
  Future<void> attendi(Duration durata) async {
    attese.add(durata);
    avanza(durata);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Timer timer(Duration durata, void Function() azione) {
    final timer = TimerFinto._(this, ora.add(durata), azione);
    _timer.add(timer);
    return timer;
  }

  /// Timer non ancora scattati né annullati.
  List<TimerFinto> get inAttesa => List.of(_timer);

  /// Fa passare [durata], eseguendo in ordine i timer che scadono.
  void avanza(Duration durata) {
    final fine = ora.add(durata);
    while (true) {
      final scaduti = _timer.where((t) => !t.scadenza.isAfter(fine)).toList()
        ..sort((a, b) => a.scadenza.compareTo(b.scadenza));
      if (scaduti.isEmpty) break;
      final timer = scaduti.first;
      if (timer.scadenza.isAfter(ora)) ora = timer.scadenza;
      timer._scatta();
    }
    ora = fine;
  }
}

class TimerFinto implements Timer {
  TimerFinto._(this._orologio, this.scadenza, this._azione);

  final OrologioFinto _orologio;
  final DateTime scadenza;
  final void Function() _azione;
  var _attivo = true;

  @override
  bool get isActive => _attivo;

  @override
  int get tick => _attivo ? 0 : 1;

  @override
  void cancel() {
    _attivo = false;
    _orologio._timer.remove(this);
  }

  void _scatta() {
    cancel();
    _azione();
  }
}

/// Programma del coach in memoria, con il server HTTP vero. Il servizio
/// onion lo simula [TorFinto]: raggiunge il server solo chi ha una chiave
/// tra quelle pubblicate nel descrittore.
class PcCoach {
  PcCoach._(
    this._orologio,
    this.archivio,
    this.nucleo,
    this.server,
    this.registro,
  );

  static Future<PcCoach> _avvia(
    OrologioFinto orologio, {
    required String nome,
    int? budgetPagina,
  }) async {
    final archivio = Archivio.inMemoria();
    final identita = await caricaOCreaIdentita(archivio, PortachiaviMemoria());
    final nucleo = NucleoCoach(
      archivio: archivio,
      indirizzo: identita.indirizzo,
      adesso: orologio.adesso,
      budgetPagina: budgetPagina,
    )..nomeCoach = nome;
    final registro = <String>[];
    final server = ServerCoach(
      nucleo,
      adesso: orologio.adesso,
      registra: registro.add,
    );
    await server.avvia();
    final pc = PcCoach._(orologio, archivio, nucleo, server, registro);
    nucleo.eventi.listen(pc._evento);
    return pc;
  }

  final OrologioFinto _orologio;
  final Archivio archivio;
  final NucleoCoach nucleo;
  final ServerCoach server;

  /// Errori registrati dal server HTTP.
  final List<String> registro;
  final eventi = <EventoCoach>[];

  /// Spento: Tor non trova il descrittore (F0) e le connessioni aperte
  /// cadono prima della risposta.
  var acceso = true;

  /// La prossima risposta si perde: il coach ha trattato la richiesta, ma la
  /// connessione cade prima che la risposta arrivi al telefono.
  var perdiProssimaRisposta = false;

  List<String>? _pubblicate;
  DateTime? _ripubblicaAlle;
  final _attese = <(int, void Function())>[];

  String get indirizzo => nucleo.indirizzo;

  /// Richieste `POST /v1/sync` trattate.
  int get richiesteSync => eventi.whereType<DispositivoSincronizzato>().length;

  /// Chiavi pubbliche nel descrittore pubblicato: di norma quelle autorizzate
  /// in questo momento.
  List<String> chiaviPubblicate() {
    final scadenza = _ripubblicaAlle;
    if (scadenza != null && !_orologio.ora.isBefore(scadenza)) ripubblica();
    return _pubblicate ?? nucleo.chiaviAutorizzate();
  }

  /// Il descrittore resta quello attuale, come se il servizio non fosse
  /// ancora stato ripubblicato; con [per] si ripubblica dopo quel tempo.
  void congelaServizio({Duration? per}) {
    _pubblicate = nucleo.chiaviAutorizzate();
    _ripubblicaAlle = per == null ? null : _orologio.ora.add(per);
  }

  void ripubblica() {
    _pubblicate = null;
    _ripubblicaAlle = null;
  }

  /// Esegue [azione] appena il coach ha trattato la [n]-esima richiesta di
  /// sync da adesso, prima che la risposta arrivi al telefono.
  void dopoRichiesteSync(int n, void Function() azione) =>
      _attese.add((richiesteSync + n, azione));

  void _evento(EventoCoach evento) {
    eventi.add(evento);
    if (evento is! DispositivoSincronizzato) return;
    for (final attesa in _attese.where((a) => a.$1 == richiesteSync).toList()) {
      _attese.remove(attesa);
      attesa.$2();
    }
  }

  void spegni() => acceso = false;

  void accendi() => acceso = true;

  /// Crea un invito per l'atleta e restituisce il testo del QR.
  Future<String> invito(String atletaId) async =>
      (await nucleo.inviti.crea(atletaId)).uri!.toString();

  /// Crea e pubblica una scheda; restituisce l'id.
  String pubblicaScheda(String atletaId, String titolo, {String note = ''}) {
    final id = nucleo.schede.crea(
      atletaId,
      contenuto: contenutoScheda(titolo, note: note),
    );
    nucleo.schede.pubblica(id);
    return id;
  }

  /// Il log come l'ha salvato il coach, oppure null.
  ({int rev, bool eliminato, Map<String, Object?>? contenuto})? log(String id) {
    final riga = archivio.db.select(
      'SELECT rev, eliminato, contenuto FROM log WHERE id = ?',
      [id],
    ).firstOrNull;
    if (riga == null) return null;
    final contenuto = riga['contenuto'];
    return (
      rev: riga['rev'] as int,
      eliminato: riga['eliminato'] == 1,
      contenuto: contenuto is String
          ? jsonDecode(contenuto) as Map<String, Object?>
          : null,
    );
  }

  Future<void> chiudi() async {
    await server.chiudi();
    await nucleo.chiudi();
    archivio.chiudi();
  }
}

/// Tor del telefono, simulato. Raggiunge il server del coach se il PC è
/// acceso e se la chiave impostata per l'indirizzo è tra quelle pubblicate:
/// altrimenti dà gli errori SOCKS estesi che darebbe Tor (F0, F4, F5).
class TorFinto implements TrasportoTor {
  TorFinto._(this._ambiente);

  final Ambiente _ambiente;
  final chiavi = <String, Uint8List>{};
  var attivo = false;

  /// Il bootstrap non si completa: [avvia] lancia [TorNonParte].
  var nonParte = false;
  var avvii = 0;
  var arresti = 0;

  /// Tentativi di connessione, riusciti o no.
  var connessioni = 0;

  /// Errori da dare alle prossime connessioni, uno per connessione.
  final guasti = <Object>[];

  /// Chiavi pubbliche con cui le connessioni hanno raggiunto un coach.
  final chiaviUsate = <String>[];

  /// Eseguita una volta, all'inizio della prossima connessione.
  Future<void> Function()? primaDellaConnessione;

  @override
  Future<void> avvia() async {
    if (nonParte) throw const TorNonParte();
    if (attivo) return;
    attivo = true;
    avvii++;
  }

  @override
  Future<void> ferma() async {
    attivo = false;
    arresti++;
  }

  @override
  Future<void> impostaChiave(String indirizzo, Uint8List chiavePrivata) async =>
      chiavi[indirizzo] = Uint8List.fromList(chiavePrivata);

  @override
  Future<void> rimuoviChiave(String indirizzo) async =>
      chiavi.remove(indirizzo);

  @override
  HttpClient creaHttpClient() => HttpClient()
    ..connectionFactory = (uri, proxyHost, proxyPort) async {
      final prima = primaDellaConnessione;
      primaDellaConnessione = null;
      await prima?.call();
      connessioni++;
      if (!attivo) throw const SocketException('Tor non è attivo');
      if (guasti.isNotEmpty) throw guasti.removeAt(0);
      final indirizzo = uri.host.replaceAll('.onion', '');
      final pc = _ambiente._pc[indirizzo];
      if (pc == null || !pc.acceso) {
        throw const ErroreSocks(ErroreSocks.descrittoreNonTrovato);
      }
      final chiave = chiavi[indirizzo];
      if (chiave == null) {
        throw const ErroreSocks(ErroreSocks.autorizzazioneMancante);
      }
      final pubblica = (await CoppiaX25519.daPrivata(chiave)).pubblicaBase32;
      if (!pc.chiaviPubblicate().contains(pubblica)) {
        throw const ErroreSocks(ErroreSocks.autorizzazioneErrata);
      }
      chiaviUsate.add(pubblica);
      return ConnectionTask.fromSocket(_inoltra(pc), () {});
    };

  /// Collega il telefono al server del coach attraverso un inoltro locale,
  /// che fa cadere la connessione quando il PC si spegne o deve perdere una
  /// risposta.
  Future<Socket> _inoltra(PcCoach pc) async {
    final ascolto = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final telefono = Socket.connect(InternetAddress.loopbackIPv4, ascolto.port);
    final lato = await ascolto.first;
    await ascolto.close();
    final coach = await Socket.connect(
      InternetAddress.loopbackIPv4,
      pc.server.porta,
    );
    var interrotta = false;
    void interrompi() {
      if (interrotta) return;
      interrotta = true;
      lato.destroy();
      coach.destroy();
    }

    lato.listen(
      (dati) {
        if (!interrotta) coach.add(dati);
      },
      onDone: () {
        if (!interrotta) coach.close().ignore();
      },
      onError: (Object _) => interrompi(),
    );
    coach.listen(
      (dati) {
        if (interrotta) return;
        if (!pc.acceso || pc.perdiProssimaRisposta) {
          pc.perdiProssimaRisposta = false;
          interrompi();
        } else {
          lato.add(dati);
        }
      },
      onDone: () {
        if (!interrotta) lato.close().ignore();
      },
      onError: (Object _) => interrompi(),
    );
    return telefono;
  }
}

class ReteFinta implements Connettivita {
  var connessa = true;

  @override
  Future<bool> disponibile() async => connessa;
}

/// Telefono dell'atleta: l'app vera, con archivio in memoria, cassaforte
/// in memoria e Tor finto.
class Telefono {
  Telefono._(
    this._ambiente, {
    required String nome,
    required String versioneApp,
    required int logPerRichiesta,
  }) : tor = TorFinto._(_ambiente),
       _dispositivo = DatiDispositivo(
         nome: nome,
         piattaforma: 'android',
         versioneApp: versioneApp,
       ),
       _logPerRichiesta = logPerRichiesta {
    nucleo = _avvia();
  }

  final Ambiente _ambiente;
  final DatiDispositivo _dispositivo;
  final int _logPerRichiesta;
  final archivio = ArchivioAtleta.inMemoria();
  final cassaforte = CassaforteMemoria();
  final TorFinto tor;
  final rete = ReteFinta();
  final registro = <String>[];
  late NucleoAtleta nucleo;

  NucleoAtleta _avvia() => NucleoAtleta(
    archivio: archivio,
    cassaforte: cassaforte,
    tor: tor,
    dispositivo: _dispositivo,
    rete: rete,
    orologio: _ambiente.orologio,
    registra: registro.add,
    logPerRichiesta: _logPerRichiesta,
  );

  /// L'app si chiude e si riapre: restano archivio e cassaforte, non le
  /// chiavi impostate in Tor.
  Future<void> riapri() async {
    await nucleo.chiudi();
    tor.chiavi.clear();
    tor.attivo = false;
    nucleo = _avvia();
  }

  Future<void> chiudi() async {
    await nucleo.chiudi();
    archivio.chiudi();
  }
}

TypeMatcher<ErroreAbbinamento> erroreAbbinamento(
  ProblemaAbbinamento problema,
) => isA<ErroreAbbinamento>().having((e) => e.problema, 'problema', problema);

Map<String, Object?> contenutoScheda(String titolo, {String note = ''}) => {
  'titolo': titolo,
  'note': note,
  'valida_dal': '2026-10-20',
  'sedute': [
    {
      'id': nuovoUuid(),
      'nome': 'Giorno A',
      'esercizi': [
        {
          'id': nuovoUuid(),
          'nome': 'Squat',
          'prescrizione': [
            {
              'serie': 4,
              'ripetizioni': '6-8',
              'carico': '75% 1RM',
              'recupero_s': 150,
            },
          ],
        },
      ],
    },
  ],
};

/// Allenamento come lo compila l'interfaccia (§8.2), senza id né rev.
Map<String, Object?> allenamento({
  String note = '',
  String eseguitoIl = '2026-10-21T18:30:00+02:00',
  String? schedaId,
  int? revisione,
}) => {
  'scheda_id': schedaId,
  'scheda_revisione': revisione,
  'seduta_id': null,
  'eseguito_il': eseguitoIl,
  'durata_min': 65,
  'rpe': 8,
  'note': note,
  'esercizi': [
    {
      'esercizio_id': null,
      'nome': 'Squat',
      'note': '',
      'serie': [
        {
          'ripetizioni': 8,
          'carico_kg': 80,
          'durata_s': null,
          'rpe': 7.5,
          'completata': true,
        },
      ],
    },
  ],
};
