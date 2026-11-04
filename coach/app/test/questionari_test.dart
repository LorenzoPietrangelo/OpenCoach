import 'dart:typed_data';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';

import 'supporto.dart';

/// Un JPEG minimo valido (1×1), per mostrare la foto nella pagina.
final jpeg = Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
  0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
  0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
  0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20, 0x24, 0x2E, 0x27, 0x20,
  0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29, 0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27,
  0x39, 0x3D, 0x38, 0x32, 0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
  0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x09, 0xFF, 0xC4,
  0x00, 0x14, 0x10, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x2A, 0x9F,
  0xFF, 0xD9,
]);

void main() {
  late CoachDiProva coach;
  late DesktopFinto desktop;

  setUp(() {
    coach = CoachDiProva();
    desktop = DesktopFinto();
  });

  testWidgets('scrive un questionario, lo manda e legge le risposte con le foto', (tester) async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    await coach.riceviLog(atleta.id, const []);
    await avviaApp(tester, coach, desktop);

    // Nessuna sezione a parte: i questionari stanno nella chat.
    expect(find.text('Questionari'), findsNothing);
    await tester.tap(find.text('Giulia'));
    await tester.pumpAndSettle();
    expect(find.text('Questionari'), findsNothing);
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Manda un questionario'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuovo questionario'));
    await tester.pumpAndSettle();

    // Senza titolo né testo non si salva: il programma dice cosa manca.
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Il questionario non è completo'), findsOneWidget);
    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Titolo'), 'Check mensile');
    await tester.enterText(find.widgetWithText(TextFormField, 'Domanda 1'), 'Quanti giorni a settimana?');
    await tester.tap(find.text('Testo breve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scelta singola').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Opzioni'), '3 giorni\n4 giorni\n');
    await tester.tap(find.text('Consenti «Altro:» con una risposta scritta'));
    await tester.tap(find.text('Obbligatoria'));
    await tester.ensureVisible(find.text('Chiedi delle foto'));
    await tester.tap(find.text('Chiedi delle foto'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Quante foto'), '1');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Questionario salvato'), findsOneWidget);

    final modello = coach.nucleo.questionari.modelli().single;
    expect(validaContenutoQuestionario(modello.contenuto), isEmpty);
    final domanda = (modello.contenuto['domande']! as List<Object?>).single! as Map<String, Object?>;
    expect(domanda['opzioni'], ['3 giorni', '4 giorni']);
    expect(domanda['altro'], isTrue);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('1 domanda · 1 foto'), findsOneWidget);

    await tester.tap(find.text('Manda'));
    await tester.pumpAndSettle();
    final inviato = coach.nucleo.questionari.inviati(atleta.id).single;
    expect(find.textContaining('in attesa di risposta'), findsOneWidget);

    // L'atleta risponde, con la foto.
    final foto = nuovoUuid();
    coach.nucleo.questionari.salvaFoto(atleta.id, foto, jpeg);
    await coach.riceviLog(atleta.id, const [], risposte: [
      {
        'questionario_id': inviato.id,
        'inviata_il': '2026-10-27T18:00:00+01:00',
        'risposte': [
          {
            'domanda_id': domanda['id'],
            'valore': {'altro': 'Giorni alterni'},
          },
        ],
        'foto': [foto],
      },
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Risposte arrivate il'), findsOneWidget);
    // Il pallino sulla chat conta le risposte da leggere.
    expect(coach.nucleo.questionari.nonLette(atleta.id), 1);
    expect(desktop.notifiche, contains('Open Coach: Giulia ha risposto a «Check mensile»'));

    await tester.tap(find.text('Check mensile'));
    await tester.pumpAndSettle();
    expect(find.text('Quanti giorni a settimana?'), findsOneWidget);
    expect(find.text('Altro: Giorni alterni'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(coach.nucleo.questionari.nonLette(atleta.id), 0);
  });

  testWidgets('dalla chat si annulla un questionario senza risposta', (tester) async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    await coach.riceviLog(atleta.id, const []);
    final modello = coach.nucleo.questionari.creaModello({
      'titolo': 'Anamnesi',
      'domande': [
        {'id': nuovoUuid(), 'tipo': 'testo_breve', 'testo': 'Come stai?', 'obbligatoria': false},
      ],
    });
    coach.nucleo.messaggi.invia(atleta.id, 'Ti mando una cosa');
    coach.nucleo.questionari.invia(modello, atleta.id);
    await avviaApp(tester, coach, desktop);
    await tester.tap(find.text('Giulia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Ti mando una cosa'), findsOneWidget);
    expect(find.text('Anamnesi'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Annulla').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Annulla'));
    await tester.pumpAndSettle();
    expect(coach.nucleo.questionari.inviati(atleta.id).single.stato, StatoQuestionario.annullato);
    expect(find.text('Annullato'), findsOneWidget);
  });

  testWidgets('le risposte si vedono accanto all\'editor della scheda', (tester) async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    await coach.riceviLog(atleta.id, const []);
    final domanda = nuovoUuid();
    final modello = coach.nucleo.questionari.creaModello({
      'titolo': 'Anamnesi',
      'domande': [
        {'id': domanda, 'tipo': 'numero', 'testo': 'Quanto sei alto?', 'obbligatoria': true, 'unita': 'cm'},
      ],
    });
    final inviato = coach.nucleo.questionari.invia(modello, atleta.id);
    await coach.riceviLog(atleta.id, const [], risposte: [
      {
        'questionario_id': inviato,
        'inviata_il': '2026-10-27T18:00:00+01:00',
        'risposte': [
          {'domanda_id': domanda, 'valore': 168.5},
        ],
        'foto': <Object?>[],
      },
    ]);
    await avviaApp(tester, coach, desktop);
    await tester.tap(find.text('Giulia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schede'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuova scheda'));
    await tester.pumpAndSettle();
    expect(find.text('Risposte ai questionari'), findsOneWidget);
    expect(find.text('168,5 cm'), findsOneWidget);
  });
}
