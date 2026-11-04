import 'dart:typed_data';

import 'package:atleta_app/app.dart';
import 'package:atleta_app/schermate/questionario.dart';
import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';

import 'supporto.dart';

/// Un JPEG minimo valido (1×1), per mostrare la miniatura.
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
  late TelefonoDiProva telefono;

  setUp(() => telefono = TelefonoDiProva());
  tearDown(() => telefono.chiudi());

  final giorni = nuovoUuid();
  final peso = nuovoUuid();
  final energia = nuovoUuid();
  final attrezzi = nuovoUuid();
  Map<String, Object?> questionario() => {
    'id': nuovoUuid(),
    'inviato_il': '2026-10-21T10:00:00+02:00',
    'titolo': 'Check mensile',
    'descrizione': 'Come è andato il mese?',
    'domande': [
      {
        'id': giorni,
        'tipo': 'scelta_singola',
        'testo': 'Quanti giorni ti sei allenato a settimana?',
        'obbligatoria': true,
        'opzioni': ['2', '3', '4'],
        'altro': true,
      },
      {'id': peso, 'tipo': 'numero', 'testo': 'Quanto pesi?', 'obbligatoria': true, 'unita': 'kg', 'peso_corporeo': true},
      {'id': energia, 'tipo': 'scala', 'testo': 'Energia', 'obbligatoria': false},
      {
        'id': attrezzi,
        'tipo': 'scelta_multipla',
        'testo': 'Attrezzi',
        'obbligatoria': false,
        'opzioni': ['Leg press', 'Lat machine'],
      },
    ],
    'foto': {'numero': 1, 'istruzioni': 'Corpo intero, di fronte.'},
  };

  testWidgets('dalla chat si compila, con la foto, e si invia', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    final q = questionario();
    telefono.aggiungiQuestionario(coach, q);
    telefono.nucleo.pesi.salva(DateTime(2026, 10, 20), 72.4);
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(AppAtleta(nucleo: telefono.nucleo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    // In cima alla chat e in mezzo ai messaggi.
    expect(find.text('Da compilare'), findsNWidgets(2));
    await tester.tap(find.text('Check mensile').first);
    await tester.pumpAndSettle();

    // Al posto della fotocamera, una foto finta.
    await tester.pumpWidget(
      conTesti(
        SchermataQuestionario(
          nucleo: telefono.nucleo,
          coachId: coach,
          questionarioId: q['id']! as String,
          scegliFoto: (_) async => jpeg,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Come è andato il mese?'), findsOneWidget);
    // Il peso parte dall'ultimo registrato.
    expect(find.widgetWithText(TextField, '72,4'), findsOneWidget);

    // Senza la risposta obbligatoria e la foto non si invia.
    await tester.tap(find.text('Invia al coach'));
    await tester.pumpAndSettle();
    expect(find.text('Serve una risposta'), findsOneWidget);

    await tester.tap(find.text('Altro'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Giorni alterni');
    await tester.tap(find.widgetWithText(ChoiceChip, '8'));
    await tester.tap(find.text('Leg press'));
    await tester.tap(find.text('Foto 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scegli dalla galleria'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.text('Invia al coach'));
    await tester.pumpAndSettle();
    expect(find.text('Inviare le risposte?'), findsOneWidget);
    await tester.tap(find.text('Invia'));
    await tester.pumpAndSettle();

    final inviato = telefono.nucleo.questionari.cerca(coach, q['id']! as String)!;
    expect(inviato.stato, StatoQuestionario.inInvio);
    expect(inviato.risposta!['risposte'], [
      {
        'domanda_id': giorni,
        'valore': {'altro': 'Giorni alterni'},
      },
      {'domanda_id': peso, 'valore': 72.4},
      {'domanda_id': energia, 'valore': 8},
      {
        'domanda_id': attrezzi,
        'valore': {
          'scelte': ['Leg press'],
        },
      },
    ]);
    expect((inviato.risposta!['foto']! as List<Object?>), hasLength(1));
  });

  testWidgets('inviato si legge soltanto', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    final q = questionario()..remove('foto');
    telefono.aggiungiQuestionario(coach, q);
    final id = q['id']! as String;
    telefono.nucleo.questionari.rispondi(coach, id, giorni, {'scelta': '3'});
    telefono.nucleo.questionari.rispondi(coach, id, peso, 70);
    telefono.nucleo.questionari.invia(coach, id);

    await tester.pumpWidget(
      conTesti(SchermataQuestionario(nucleo: telefono.nucleo, coachId: coach, questionarioId: id)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('partono alla prossima sincronizzazione'), findsOneWidget);
    expect(find.text('Invia al coach'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });
}
