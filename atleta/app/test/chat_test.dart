import 'dart:io';

import 'package:atleta_app/schermate/chat.dart';
import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';

import 'supporto.dart';

void main() {
  late TelefonoDiProva telefono;

  setUp(() => telefono = TelefonoDiProva());
  tearDown(() => telefono.chiudi());

  /// Un messaggio del coach arrivato con una sync.
  void dalCoach(int coach, String testo) => telefono.archivio.db.execute(
    'INSERT INTO messaggi (coach_id, id, dal_coach, testo, inviato_il, ordine, stato, letto) '
    "VALUES (?, ?, 1, ?, '2026-10-21T18:00:00+02:00', '2026-10-21T16:00:00.000Z', 'inviato', 0)",
    [coach, nuovoUuid(), testo],
  );

  testWidgets('la chat mostra i messaggi, li segna letti e ne manda di nuovi', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    dalCoach(coach, 'Domani carichi pesanti');
    final file = File('${telefono.cartellaVideo.path}/serie.mp4')..writeAsBytesSync(List.filled(500, 1));
    telefono.nucleo.chat.allegaVideo(coach, file: file.path, durataS: 11, esercizio: 'Panca', serie: 3);
    expect(telefono.nucleo.chat.nonLetti(coach), 1);

    await tester.pumpWidget(conTesti(SchermataChat(nucleo: telefono.nucleo, coachId: coach)));
    await tester.pumpAndSettle();
    expect(find.text('Chat con Marco Bianchi'), findsOneWidget);
    expect(find.text('Domani carichi pesanti'), findsOneWidget);
    expect(find.text('Panca, serie 3 · video di 11 s'), findsOneWidget);
    expect(telefono.nucleo.chat.nonLetti(coach), 0);

    await tester.enterText(find.byType(TextField), 'Ok, a domani');
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();
    expect(find.text('Ok, a domani'), findsOneWidget);
    expect(find.byType(TextField).evaluate().single.widget, isA<TextField>().having((t) => t.controller!.text, 'testo', ''));
    final scritto = telefono.nucleo.chat.elenco(coach).last;
    expect(scritto.testo, 'Ok, a domani');
    expect(scritto.stato, StatoMessaggio.inInvio);

    // Non ancora partito: con una pressione lunga si ritira.
    await tester.longPress(find.text('Ok, a domani'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Non inviarlo'));
    await tester.pumpAndSettle();
    expect(find.text('Ok, a domani'), findsNothing);
  });

  testWidgets('con un coach che non conosce la chat avvisa di aggiornare', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    telefono.archivio.db.execute('UPDATE coach SET chat_supportata = 0 WHERE id = ?', [coach]);
    await tester.pumpWidget(conTesti(SchermataChat(nucleo: telefono.nucleo, coachId: coach)));
    await tester.pumpAndSettle();
    expect(find.textContaining('alla versione 1.3.0'), findsOneWidget);
  });
}
