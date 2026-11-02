import 'dart:typed_data';

import 'package:coach_app/comuni.dart';
import 'package:coach_app/schermate/chat.dart';
import 'package:coach_app/schermate/peso.dart';
import 'package:coach_app/servizi.dart';
import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:crypto/crypto.dart';
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
    // Il recupero si scrive anche in minuti e secondi.
    await tester.enterText(find.widgetWithText(TextFormField, 'Recupero'), '1:');
    await tester.pump();
    expect(find.text('es. 90 o 1:30'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Recupero'), '1:30');
    await tester.pump();
    expect(find.text('es. 90 o 1:30'), findsNothing);
    await tester.enterText(find.widgetWithText(TextFormField, 'RIR'), '2');
    // Le note dell'esercizio sono a scomparsa.
    expect(find.widgetWithText(TextFormField, 'Note dell\'esercizio'), findsNothing);
    await tester.tap(find.byTooltip('Note dell\'esercizio'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Note dell\'esercizio'),
      'Pausa in buca',
    );
    await tester.tap(find.text('Pubblica'));
    await tester.pumpAndSettle();

    final scheda = coach.nucleo.schede.elenco(atleta.id).single;
    expect(scheda.revisione, 1);
    expect(scheda.titolo, 'Forza');
    final contenuto = coach.nucleo.schede.contenutoRevisione(scheda.id, 1)!;
    expect(validaContenutoScheda(contenuto), isEmpty);
    final esercizio = ((contenuto['sedute'] as List).single as Map)['esercizi'] as List;
    expect((esercizio.single as Map)['note'], 'Pausa in buca');
    expect((esercizio.single as Map)['prescrizione'], [
      {'serie': 4, 'ripetizioni': '6-8', 'recupero_s': 90, 'rir': '2'},
    ]);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Forza'), findsOneWidget);
    expect(find.textContaining('Revisione 1 · in attesa di consegna'), findsOneWidget);
  });

  testWidgets('la libreria manda il video agli esercizi con lo stesso nome', (tester) async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    final schedaId = coach.nucleo.schede.crea(atleta.id, contenuto: contenutoScheda('Forza'));
    coach.nucleo.schede.pubblica(schedaId);
    await avviaApp(tester, coach, desktop);
    await tester.tap(find.text('Libreria'));
    await tester.pumpAndSettle();
    expect(find.text('La libreria è vuota.'), findsOneWidget);

    await tester.tap(find.text('Nuovo esercizio'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Esercizio'), 'squat');
    await tester.enterText(find.widgetWithText(TextField, 'Link al video'), 'http://esempio.it/v');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Serve un link che inizia con https://'), findsOneWidget);

    // Senza https:// il programma lo aggiunge.
    await tester.enterText(find.widgetWithText(TextField, 'Link al video'), 'youtu.be/abc');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Aggiornare i video nelle schede?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Aggiorna i video'));
    await tester.pumpAndSettle();

    final contenuto = coach.nucleo.schede.contenutoRevisione(schedaId, 2)!;
    final esercizio = ((contenuto['sedute'] as List).single as Map)['esercizi'] as List;
    expect((esercizio.single as Map)['video'], 'https://youtu.be/abc');
    expect(find.text('squat'), findsOneWidget);
  });

  test('il recupero si legge in secondi o in minuti e secondi', () {
    expect(analizzaRecupero('90'), 90);
    expect(analizzaRecupero(' 1:30 '), 90);
    expect(analizzaRecupero('2:05'), 125);
    expect(analizzaRecupero('1:5'), isNull);
    expect(analizzaRecupero('1:60'), isNull);
    expect(analizzaRecupero('1:'), isNull);
    expect(analizzaRecupero(''), isNull);
    expect(formattaRecupero(45), '45');
    expect(formattaRecupero(150), '2:30');
    expect(recuperoLeggibile(45), '45 s');
    expect(recuperoLeggibile(90), '1:30 min');
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
    expect(find.text('Prescritto: 4 × 6-8, 75% 1RM, 2:30 min'), findsOneWidget);
  });

  testWidgets('mostra i pesi che l\'atleta condivide, con la media della settimana', (tester) async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    Map<String, Object?> peso(String giorno, num kg) => {
      'id': nuovoUuid(),
      'rev': 1,
      'eliminato': false,
      'giorno': giorno,
      'kg': kg,
    };
    await avviaApp(tester, coach, desktop);
    await tester.tap(find.text('Giulia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peso'));
    await tester.pumpAndSettle();
    expect(find.textContaining('non ti ha ancora condiviso'), findsOneWidget);

    await coach.riceviLog(atleta.id, const [], pesi: [
      peso('2026-10-14', 74),
      peso('2026-10-20', 73),
      peso('2026-10-21', 72),
      peso('2026-10-27', 71.5),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Ultimo peso, 27/10/2026'), findsOneWidget);
    // Media dal 21 al 27: (72 + 71,5) / 2; dal 14 al 20: (74 + 73) / 2.
    expect(find.text('71,8 kg'), findsOneWidget);
    expect(find.text('−1,8 kg'), findsOneWidget);
    expect(find.byType(GraficoPeso), findsOneWidget);
  });

  testWidgets('la chat mostra il video di una serie e manda la risposta', (tester) async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    final video = Uint8List.fromList(List.generate(5000, (i) => i % 256));
    final videoId = nuovoUuid();
    coach.nucleo.messaggi.salvaParteVideo(atleta.id, videoId, 0, video);
    await avviaApp(tester, coach, desktop);
    await coach.riceviLog(atleta.id, const [], messaggi: [
      {
        'id': nuovoUuid(),
        'autore': 'atleta',
        'testo': 'Ultima serie, mi sembra di cedere',
        'inviato_il': '2026-10-21T19:00:00+02:00',
        'video': {
          'id': videoId,
          'dimensione': video.length,
          'parti': 1,
          'sha256': sha256.convert(video).toString(),
          'durata_s': 12,
        },
        'riferimento': {'esercizio': 'Squat', 'serie': 4},
      },
    ]);
    await tester.pumpAndSettle();
    expect(desktop.notifiche.last, 'Open Coach: Giulia ti ha mandato un video');

    await tester.tap(find.text('Giulia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Squat, serie 4'), findsOneWidget);
    expect(find.text('Video di 12 s'), findsOneWidget);
    expect(coach.nucleo.messaggi.nonLetti(atleta.id), 0);

    // Il video si guarda nel programma. Nei test non c'è il lettore di
    // Windows: resta l'apertura con un altro programma.
    await tester.tap(find.text('Guarda'));
    await tester.pumpAndSettle();
    expect(find.byType(LettoreVideo), findsOneWidget);
    expect(find.textContaining('Non riesco a riprodurre il video qui'), findsOneWidget);
    await tester.tap(find.byTooltip('Apri con un altro programma'));
    await tester.pump();
    expect(desktop.chiamate.last, startsWith('apri: '));
    expect(desktop.chiamate.last, endsWith('$videoId.mp4'));
    await tester.tap(find.byTooltip('Chiudi'));
    await tester.pumpAndSettle();
    expect(find.byType(LettoreVideo), findsNothing);

    await tester.enterText(find.byType(TextField), 'Scendi a 90 kg');
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();
    expect(find.text('Scendi a 90 kg'), findsOneWidget);
    expect(coach.nucleo.messaggi.conversazione(atleta.id).last.dalCoach, isTrue);

    coach.nucleo.messaggi.eliminaVideo(atleta.id, coach.nucleo.messaggi.conversazione(atleta.id).first.id);
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
