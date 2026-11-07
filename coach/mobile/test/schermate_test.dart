import 'dart:io';
import 'dart:typed_data';

import 'package:coach_mobile/app.dart';
import 'package:coach_mobile/dati/cassaforte.dart';
import 'package:coach_mobile/dati/collegamento.dart';
import 'package:coach_mobile/dati/fonte_dati.dart';
import 'package:coach_mobile/dati/modelli.dart';
import 'package:coach_mobile/dati/stato_coach.dart';
import 'package:coach_mobile/l10n/testi.dart';
import 'package:coach_mobile/piattaforma/blocco.dart';
import 'package:coach_mobile/schermate/blocco.dart';
import 'package:coach_mobile/schermate/peso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';
import 'package:trasporto_tor/trasporto_tor.dart';

RiepilogoAtleta _atleta(String id, String nome, {int nonLetti = 0, int risposte = 0, String? ultimo}) => RiepilogoAtleta(
  id: id,
  nome: nome,
  telefonoCollegato: true,
  ultimoContatto: null,
  nonLetti: nonLetti,
  risposteNuove: risposte,
  ultimoMessaggio: ultimo == null
      ? null
      : Anteprima(dalCoach: false, testo: ultimo, conVideo: false, inviatoIl: DateTime(2026, 11, 6, 10)),
  ultimoAllenamento: null,
);

/// Dati pronti, senza rete.
class FonteFinta implements FonteDatiCoach {
  var elenco = [_atleta('a', 'Anna'), _atleta('g', 'Giulia', nonLetti: 2, ultimo: 'Ciao coach')];
  ProblemaCoach? guasto;
  final inviati = <String>[];
  final letti = <String>[];
  var questionariLetti = <String>[];
  var scollegato = false;

  @override
  Future<ElencoAtleti> atleti() async {
    if (guasto case final g?) throw ErroreCoach(g);
    return ElencoAtleti(elenco, 'impronta');
  }

  @override
  Future<DettaglioAtleta> atleta(String id) async => DettaglioAtleta(
    riepilogo: elenco.firstWhere((a) => a.id == id),
    note: 'Ginocchio delicato',
    allenamentiTotali: 3,
    schede: const [
      SchedaAtleta(titolo: 'Forza', stato: 'pubblicata', revisione: 2, ricevutaIl: null),
    ],
  );

  @override
  Future<Pagina<MessaggioChat>> messaggi(String atletaId, {String? prima}) async => Pagina([
    MessaggioChat(id: 'm1', dalCoach: false, testo: 'Ciao coach', inviatoIl: DateTime(2026, 11, 6, 10)),
    MessaggioChat(
      id: 'm2',
      dalCoach: false,
      testo: '',
      inviatoIl: DateTime(2026, 11, 6, 11),
      conVideo: true,
      durataVideoS: 42,
      esercizio: 'Squat',
      serie: 4,
    ),
    for (final (i, testo) in inviati.indexed)
      MessaggioChat(id: 'mio$i', dalCoach: true, testo: testo, inviatoIl: DateTime(2026, 11, 6, 12)),
  ], altri: false);

  @override
  Future<void> inviaMessaggio(String atletaId, String id, String testo) async {
    if (guasto case final g?) throw ErroreCoach(g);
    inviati.add(testo);
  }

  @override
  Future<void> segnaLetti(String atletaId) async => letti.add(atletaId);

  @override
  Future<Pagina<AllenamentoAtleta>> allenamenti(String atletaId, {String? prima}) async => Pagina([
    AllenamentoAtleta(
      id: 'l1',
      eseguitoIl: DateTime(2026, 11, 5, 18, 30),
      note: 'Bene',
      durataMin: null,
      rpe: null,
      esercizi: const [
        EsercizioEseguito(
          nome: 'Panca',
          note: '',
          serie: [
            SerieEseguita(completata: true, ripetizioni: 8, caricoKg: 62.5, durataS: null, rpe: null),
            SerieEseguita(completata: false, ripetizioni: null, caricoKg: null, durataS: null, rpe: null),
          ],
        ),
      ],
    ),
  ], altri: false);

  @override
  Future<List<PesoGiorno>> pesi(String atletaId) async => [
    PesoGiorno(DateTime.utc(2026, 10, 25), 72),
    PesoGiorno(DateTime.utc(2026, 11, 5), 70.5),
  ];

  @override
  Future<List<QuestionarioAtleta>> questionari(String atletaId) async => [
    QuestionarioAtleta.daJson({
      'id': 'q1',
      'titolo': 'Check mensile',
      'stato': 'risposto',
      'letto': false,
      'risposto_il': '2026-11-05T18:00:00+01:00',
      'contenuto': {
        'domande': [
          {'id': '1', 'testo': 'Come va?'},
        ],
      },
      'risposta': {
        'risposte': [
          {'domanda_id': '1', 'valore': 'Molto bene'},
        ],
      },
    }),
  ];

  @override
  Future<void> segnaQuestionarioLetto(String id) async => questionariLetti.add(id);

  @override
  Future<Uint8List> foto(String id) async => Uint8List(0);

  /// Non torna mai da sola: l'attesa finisce quando il test chiude lo stato.
  @override
  Future<bool> attendi(String impronta) async {
    if (guasto case final g?) throw ErroreCoach(g);
    await Future<void>.delayed(const Duration(hours: 1));
    return false;
  }

  @override
  Future<void> confermaCollegamento() async {}

  @override
  Future<void> scollega() async => scollegato = true;

  @override
  Future<void> fermaRete() async {}
}

class BloccoFinto implements BloccoApp {
  BloccoFinto({this.esiste = true, this.esito = true});

  bool esiste;
  bool esito;
  var chieste = 0;

  @override
  Future<bool> disponibile() async => esiste;

  @override
  Future<bool> chiedi(String motivo) async {
    chieste++;
    return esito;
  }
}

class _TorMuto implements TrasportoTor {
  @override
  Future<void> avvia({void Function(int percento)? avanzamento}) async {}

  @override
  HttpClient creaHttpClient() => throw UnimplementedError();

  @override
  Future<void> ferma() async {}

  @override
  Future<void> impostaChiave(String indirizzo, Uint8List chiavePrivata) async {}

  @override
  Future<void> rimuoviChiave(String indirizzo) async {}
}

void main() {
  late FonteFinta fonte;
  late CassaforteInMemoria cassaforte;
  late StatoCoach stato;

  setUp(() {
    fonte = FonteFinta();
    cassaforte = CassaforteInMemoria();
  });

  Future<void> avvia(WidgetTester tester, {bool collegato = true, BloccoApp? blocco}) async {
    final servizio = ServizioCollegamento(
      cassaforte: cassaforte,
      tor: _TorMuto(),
      dispositivo: const DatiDispositivo(nome: 'Prova', piattaforma: 'android', versioneApp: '1.5.0'),
    );
    if (collegato) {
      await servizio.salvaCredenziali(
        Credenziali(
          indirizzo: indirizzoOnionDaChiave(List.filled(32, 7)),
          token: codificaBase32(List.filled(32, 1)),
          chiavePrivata: codificaBase32(List.filled(32, 2)),
          nomeCoach: 'Marco Bianchi',
          confermato: true,
        ),
      );
    }
    stato = StatoCoach(
      cassaforte: cassaforte,
      collegamento: servizio,
      creaFonte: (_) => fonte,
      attese: const [Duration(hours: 1)],
    );
    await stato.carica();
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppCoachMobile(stato: stato, blocco: blocco ?? BloccoFinto()));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> chiudi(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    stato.dispose();
    await tester.pump(const Duration(hours: 2));
  }

  testWidgets('senza collegamento chiede di inquadrare il QR', (tester) async {
    await avvia(tester, collegato: false);
    expect(find.text('Collega il telefono al PC'), findsOneWidget);
    expect(find.text('Inquadra il QR'), findsOneWidget);
    await chiudi(tester);
  });

  testWidgets('l\'elenco mette in cima chi ha novità, con il contatore', (tester) async {
    await avvia(tester);
    expect(find.text('I tuoi atleti'), findsOneWidget);
    final giulia = tester.getTopLeft(find.text('Giulia'));
    final anna = tester.getTopLeft(find.text('Anna'));
    expect(giulia.dy, lessThan(anna.dy));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Ciao coach'), findsOneWidget);
    await chiudi(tester);
  });

  testWidgets('con il PC spento lo dice e si può riprovare', (tester) async {
    fonte.guasto = ProblemaCoach.irraggiungibile;
    await avvia(tester);
    expect(find.textContaining('Il PC non risponde'), findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);

    fonte.guasto = null;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Il PC non risponde'), findsNothing);
    expect(find.text('Giulia'), findsOneWidget);
    await chiudi(tester);
  });

  testWidgets('la chat segna letto, manda i messaggi e dice dove si guarda il video', (tester) async {
    await avvia(tester);
    await tester.tap(find.text('Giulia'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(find.text('Ciao coach'), findsOneWidget);
    expect(find.text('Video di 42 s: si guarda dal programma sul PC'), findsOneWidget);
    expect(find.text('Squat, serie 4'), findsOneWidget);
    expect(fonte.letti, ['g']);

    await tester.enterText(find.byType(TextField), 'Bravissima');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(fonte.inviati, ['Bravissima']);
    await tester.pump();
    expect(find.text('Bravissima'), findsOneWidget);
    await chiudi(tester);
  });

  testWidgets('con il PC spento il messaggio si vede in attesa', (tester) async {
    await avvia(tester);
    await tester.tap(find.text('Anna'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    fonte.guasto = ProblemaCoach.irraggiungibile;
    await tester.enterText(find.byType(TextField), 'Quando torni');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('Quando torni'), findsOneWidget);
    expect(find.text('In attesa del PC'), findsOneWidget);
    await chiudi(tester);
  });

  testWidgets('le altre sezioni mostrano i dati dell\'atleta', (tester) async {
    await avvia(tester);
    await tester.tap(find.text('Anna'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));

    await tester.tap(find.text('Allenamenti'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(find.text('05/11/2026 18:30'), findsOneWidget);
    expect(find.text('1 di 2 serie'), findsOneWidget);
    await tester.tap(find.text('05/11/2026 18:30'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(find.text('Serie 1: 62,5 kg × 8'), findsOneWidget);
    expect(find.text('Serie 2: non fatta'), findsOneWidget);

    await tester.tap(find.text('Peso'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(find.text('Ultimo peso'), findsOneWidget);
    expect(find.text('70,5 kg'), findsWidgets);

    await tester.tap(find.text('Questionari'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    await tester.tap(find.text('Check mensile'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(find.text('Molto bene'), findsOneWidget);
    expect(fonte.questionariLetti, ['q1']);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));

    await tester.ensureVisible(find.text('Scheda'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    await tester.tap(find.text('Scheda'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(find.text('Ginocchio delicato'), findsOneWidget);
    expect(find.text('Revisione 2, non ancora ricevuta'), findsOneWidget);
    await chiudi(tester);
  });

  testWidgets('scollegando il telefono torna alla schermata di collegamento', (tester) async {
    await avvia(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    await tester.tap(find.text('Scollega questo telefono'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    await tester.tap(find.widgetWithText(FilledButton, 'Scollega questo telefono'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(fonte.scollegato, isTrue);
    expect(find.text('Collega il telefono al PC'), findsOneWidget);
    expect(cassaforte.voci, isEmpty);
    await chiudi(tester);
  });

  group('blocco', () {
    testWidgets('finché non si sblocca non si vede niente', (tester) async {
      final blocco = BloccoFinto(esito: false);
      await avvia(tester, blocco: blocco);
      expect(find.text('App bloccata'), findsOneWidget);
      expect(find.text('Giulia'), findsNothing);
      expect(blocco.chieste, 1);

      blocco.esito = true;
      await tester.tap(find.text('Sblocca'));
      await tester.pump();
      await tester.pump();
      expect(find.text('App bloccata'), findsNothing);
      expect(find.text('Giulia'), findsOneWidget);
      await chiudi(tester);
    });

    testWidgets('senza blocco schermo resta usabile e lo dice', (tester) async {
      await avvia(tester, blocco: BloccoFinto(esiste: false));
      expect(find.text('Giulia'), findsOneWidget);
      expect(find.textContaining('non ha un blocco schermo'), findsOneWidget);
      await chiudi(tester);
    });

    testWidgets('dopo 5 minuti in background si richiude, prima no', (tester) async {
      var ora = DateTime(2026, 11, 7, 10);
      final blocco = BloccoFinto();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: Testi.localizationsDelegates,
          supportedLocales: Testi.supportedLocales,
          builder: (context, navigatore) => CancelloBlocco(
            blocco: blocco,
            adesso: () => ora,
            child: navigatore!,
          ),
          home: const Text('Contenuto'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Contenuto'), findsOneWidget);
      expect(blocco.chieste, 1);

      Future<void> vaiEdEntra(Duration fuori) async {
        for (final s in const [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
          tester.binding.handleAppLifecycleStateChanged(s);
        }
        ora = ora.add(fuori);
        for (final s in const [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
          tester.binding.handleAppLifecycleStateChanged(s);
        }
        await tester.pump();
        await tester.pump();
      }

      await vaiEdEntra(const Duration(minutes: 4));
      expect(blocco.chieste, 1);

      blocco.esito = false;
      await vaiEdEntra(const Duration(minutes: 5));
      expect(blocco.chieste, 2);
      expect(find.text('App bloccata'), findsOneWidget);
      // Il contenuto resta montato ma nascosto.
      expect(find.text('Contenuto'), findsNothing);
    });
  });

  test('la media di 7 giorni guarda solo quei giorni', () {
    final pesi = [
      PesoGiorno(DateTime.utc(2026, 11, 1), 80),
      PesoGiorno(DateTime.utc(2026, 11, 8), 70),
      PesoGiorno(DateTime.utc(2026, 11, 10), 72),
    ];
    expect(mediaSetteGiorni(pesi, DateTime.utc(2026, 11, 10)), 71);
    expect(mediaSetteGiorni(pesi, DateTime.utc(2026, 10, 1)), isNull);
  });
}
