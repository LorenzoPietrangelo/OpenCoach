import 'package:atleta_app/app.dart';
import 'package:atleta_app/schermate/peso.dart';
import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'supporto.dart';

void main() {
  late TelefonoDiProva telefono;

  setUp(() => telefono = TelefonoDiProva());
  tearDown(() => telefono.chiudi());

  testWidgets('il peso di oggi: si registra, si corregge e si condivide con i coach scelti', (
    tester,
  ) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    await tester.pumpWidget(AppAtleta(nucleo: telefono.nucleo));
    await tester.pumpAndSettle();
    expect(find.text('Registra il peso di oggi'), findsOneWidget);

    await tester.tap(find.text('Peso'));
    await tester.pumpAndSettle();
    expect(find.text('Peso di oggi'), findsOneWidget);
    expect(find.text('Nessun peso registrato.'), findsOneWidget);

    // Fuori dall'intervallo del protocollo non si salva.
    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('Salva'));
    await tester.pump();
    expect(find.text('Scrivi un peso tra 20 e 400 kg'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '72,4');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Peso salvato'), findsOneWidget);
    expect(telefono.nucleo.pesi.elenco().single.kg, 72.4);
    expect(find.text('72,4 kg'), findsWidgets);

    // Il coach lo vede finché l'atleta non spegne la condivisione.
    expect(find.text('Vede il tuo peso'), findsOneWidget);
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Non vede il tuo peso'), findsOneWidget);
    expect(telefono.nucleo.collegamenti.cerca(coach)!.condividePesi, isFalse);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Oggi: 72,4 kg'), findsOneWidget);
  });

  test('la media degli ultimi 7 giorni conta solo i giorni con un peso', () {
    final pesi = [
      PesoDelGiorno(giorno: DateTime(2026, 10, 10), kg: 74),
      PesoDelGiorno(giorno: DateTime(2026, 10, 15), kg: 73),
      PesoDelGiorno(giorno: DateTime(2026, 10, 18), kg: 72),
    ];
    expect(mediaSettimana(pesi, DateTime(2026, 10, 18)), 72.5);
    expect(mediaSettimana(pesi, DateTime(2026, 10, 9)), isNull);
  });
}
