import 'package:coach_app/servizi.dart';
import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'supporto.dart';

void main() {
  late CoachDiProva coach;
  late DesktopFinto desktop;

  setUp(() {
    coach = CoachDiProva();
    desktop = DesktopFinto();
  });

  testWidgets('al primo avvio chiede il nome e attiva l\'avvio automatico', (tester) async {
    coach = CoachDiProva(nome: '');
    await avviaApp(tester, coach, desktop);
    expect(find.text('Benvenuto in Open Coach'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Marco Bianchi');
    await tester.tap(find.text('Inizia'));
    await tester.pumpAndSettle();

    expect(coach.nucleo.nomeCoach, 'Marco Bianchi');
    expect(desktop.avvio, isTrue);
    expect(find.text('Nessun atleta. Crea il primo con «Nuovo».'), findsOneWidget);
  });

  testWidgets('crea un atleta e mostra il QR del suo invito', (tester) async {
    await avviaApp(tester, coach, desktop);
    await tester.tap(find.text('Nuovo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Giulia Rossi');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(find.text('Giulia Rossi'), findsWidgets);
    expect(find.text('Nessun telefono collegato. Crea un invito e fallo scansionare dall\'app dell\'atleta.'), findsOneWidget);

    await tester.tap(find.text('Nuovo invito'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    final link = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    final invito = UriInvito.analizza(link);
    expect(invito.indirizzo, coach.indirizzo);

    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();
    expect(find.text('Invito aperto'), findsOneWidget);
    expect(find.text('Invito in corso'), findsOneWidget);
  });

  testWidgets('con un telefono collegato avvisa prima di un nuovo invito', (tester) async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    await coach.riceviLog(atleta.id, const []);
    await avviaApp(tester, coach, desktop);
    await tester.tap(find.text('Giulia'));
    await tester.pumpAndSettle();
    expect(find.text('Pixel 8'), findsOneWidget);

    await tester.tap(find.text('Nuovo invito'));
    await tester.pumpAndSettle();
    expect(find.text('Sostituire il telefono?'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(coach.nucleo.inviti.inCorso(atleta.id), isNull);
  });

  testWidgets('l\'editor scrive e pubblica una scheda', (tester) async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    await avviaApp(tester, coach, desktop);
    await tester.tap(find.text('Giulia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schede'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuova scheda'));
    await tester.pumpAndSettle();

    // Senza sedute non si pubblica: il programma dice perché.
    await tester.tap(find.text('Pubblica'));
    await tester.pumpAndSettle();
    expect(find.text('• Serve almeno una seduta'), findsOneWidget);
    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Titolo'), 'Forza');
    await tester.tap(find.text('Aggiungi una seduta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi un esercizio'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Esercizio'), 'Squat');
    await tester.enterText(find.widgetWithText(TextFormField, 'Serie'), '4');
    await tester.enterText(find.widgetWithText(TextFormField, 'Ripetizioni'), '6-8');
    await tester.tap(find.text('Pubblica'));
    await tester.pumpAndSettle();

    final scheda = coach.nucleo.schede.elenco(atleta.id).single;
    expect(scheda.revisione, 1);
    expect(scheda.titolo, 'Forza');
    final contenuto = coach.nucleo.schede.contenutoRevisione(scheda.id, 1)!;
    expect(validaContenutoScheda(contenuto), isEmpty);
    final esercizio = ((contenuto['sedute'] as List).single as Map)['esercizi'] as List;
    expect((esercizio.single as Map)['prescrizione'], [
      {'serie': 4, 'ripetizioni': '6-8'},
    ]);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Forza'), findsOneWidget);
    expect(find.textContaining('Revisione 1 · in attesa di consegna'), findsOneWidget);
  });

  testWidgets('uscire dall\'editor con modifiche chiede conferma', (tester) async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    coach.nucleo.schede.crea(atleta.id, contenuto: contenutoScheda('Forza'));
    await avviaApp(tester, coach, desktop);
    await tester.tap(find.text('Giulia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schede'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forza'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Titolo'), 'Forza 2');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Uscire senza salvare?'), findsOneWidget);
    await tester.tap(find.text('Esci senza salvare'));
    await tester.pumpAndSettle();
    expect(coach.nucleo.schede.elenco(atleta.id).single.titolo, 'Forza');
  });

  testWidgets('l\'editor mostra lo storico delle revisioni', (tester) async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    final id = coach.nucleo.schede.crea(atleta.id, contenuto: contenutoScheda('Forza'));
    coach.nucleo.schede.pubblica(id);
    coach.nucleo.schede.pubblica(id);
    await avviaApp(tester, coach, desktop);
    await tester.tap(find.text('Giulia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schede'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forza'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revisione 2'));
    await tester.pumpAndSettle();
    expect(find.text('Revisioni pubblicate'), findsOneWidget);
    expect(find.textContaining('in attesa di consegna'), findsOneWidget);
    expect(find.textContaining('sostituita prima di arrivare all\'atleta'), findsOneWidget);
  });

  testWidgets('mostra gli allenamenti ricevuti con la prescrizione', (tester) async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    final sedutaId = nuovoUuid();
    final schedaId = coach.nucleo.schede.crea(atleta.id, contenuto: contenutoScheda('Forza', sedutaId: sedutaId));
    coach.nucleo.schede.pubblica(schedaId);
    final esercizioId =
        (((coach.nucleo.schede.contenutoRevisione(schedaId, 1)!['sedute'] as List).single as Map)['esercizi'] as List)
                .single
            as Map;
    await coach.riceviLog(atleta.id, [
      {
        'id': nuovoUuid(),
        'rev': 1,
        'eliminato': false,
        'scheda_id': schedaId,
        'scheda_revisione': 1,
        'seduta_id': sedutaId,
        'eseguito_il': '2026-10-21T18:30:00+02:00',
        'durata_min': 60,
        'esercizi': [
          {
            'esercizio_id': esercizioId['id'],
            'nome': 'Squat',
            'serie': [
              {'ripetizioni': 8, 'carico_kg': 80, 'completata': true},
            ],
          },
        ],
      },
    ]);

    await avviaApp(tester, coach, desktop);
    await tester.tap(find.text('Giulia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allenamenti'));
    await tester.pumpAndSettle();
    expect(find.text('Giorno A'), findsOneWidget);
    expect(find.textContaining('60 minuti'), findsOneWidget);

    await tester.tap(find.text('Giorno A'));
    await tester.pumpAndSettle();
    expect(find.text('Serie 1: 8 ripetizioni, 80 kg'), findsOneWidget);
    expect(find.text('Prescritto: 4 × 6-8, 75% 1RM, 150 s'), findsOneWidget);
  });

  testWidgets('notifica sul desktop gli allenamenti in arrivo', (tester) async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    await avviaApp(tester, coach, desktop);
    await coach.riceviLog(atleta.id, [
      {
        'id': nuovoUuid(),
        'rev': 1,
        'eliminato': false,
        'eseguito_il': '2026-10-21T18:30:00+02:00',
        'esercizi': <Object?>[],
      },
    ]);
    await tester.pumpAndSettle();
    expect(desktop.notifiche, [
      'Open Coach: Giulia ha collegato Pixel 8',
      'Open Coach: Giulia ha registrato un allenamento',
    ]);
  });

  testWidgets('la schermata di stato mostra servizio e indirizzo', (tester) async {
    coach.statoTor = const StatoTor(FaseTor.avvio, avanzamento: 45);
    await avviaApp(tester, coach, desktop);
    await tester.tap(find.text('Stato'));
    await tester.pumpAndSettle();
    expect(find.text('Avvio di Tor (45%)'), findsOneWidget);
    expect(find.text('${coach.indirizzo}.onion'), findsOneWidget);
    expect(desktop.chiamate, contains('stato: Open Coach: Avvio di Tor (45%)'));

    coach.statoTor = const StatoTor(FaseTor.raggiungibile, avanzamento: 100);
    coach.stati.add(coach.statoTor);
    await tester.pumpAndSettle();
    expect(find.text('Raggiungibile'), findsOneWidget);
  });

  testWidgets('dalle impostazioni si cambia la sospensione e si reimposta l\'identità', (tester) async {
    await avviaApp(tester, coach, desktop);
    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Impedisci la sospensione del PC'));
    await tester.pumpAndSettle();
    expect(desktop.sospensioneImpedita, isTrue);
    expect(Preferenze(coach.archivio).impedisciSospensione, isTrue);

    await tester.scrollUntilVisible(find.text('Reimposta l\'identità'), 200);
    await tester.tap(find.text('Reimposta l\'identità'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();
    expect(find.text('Ne sei sicuro?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reimposta l\'identità'));
    await tester.pumpAndSettle();
    expect(coach.identitaReimpostate, 1);
  });
}
