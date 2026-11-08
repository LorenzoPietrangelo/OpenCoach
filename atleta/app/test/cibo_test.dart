import 'dart:convert';

import 'package:atleta_app/app.dart';
import 'package:atleta_app/schermate/cibo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';

import 'supporto.dart';

void main() {
  late TelefonoDiProva telefono;

  setUp(() => telefono = TelefonoDiProva());
  tearDown(() => telefono.chiudi());

  Future<void> apriCibo(WidgetTester tester) async {
    await tester.pumpWidget(AppAtleta(nucleo: telefono.nucleo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cibo'));
    await tester.pumpAndSettle();
  }

  testWidgets('un alimento scritto dall\'atleta entra nel pranzo con i totali', (tester) async {
    telefono.aggiungiCoach('Marco Bianchi');
    await apriCibo(tester);
    expect(find.text('oggi'), findsOneWidget);
    expect(find.text('0 kcal'), findsOneWidget);
    expect(find.text('Il coach non ha fissato un obiettivo.'), findsOneWidget);

    await tester.tap(find.text('Aggiungi').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Aggiungi a pranzo'), findsOneWidget);

    // Senza Tor la ricerca lo dice, e si può scrivere l'alimento.
    await tester.enterText(find.byType(TextField), 'pollo');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.textContaining('Ricerca non disponibile'), findsOneWidget);

    await tester.tap(find.text('Scrivi un alimento tuo'));
    await tester.pumpAndSettle();
    final campi = find.byType(TextField);
    expect(tester.widget<TextField>(campi.at(0)).controller!.text, 'pollo');
    await tester.enterText(campi.at(0), 'Petto di pollo');
    await tester.enterText(campi.at(2), '1200');
    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Scrivi un nome, le calorie'), findsOneWidget);
    await tester.enterText(campi.at(2), '110');
    await tester.enterText(campi.at(3), '23');
    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();

    // La porzione: 100 g proposti, valori ricalcolati.
    expect(find.text('Quanto ne hai mangiato?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '150');
    await tester.pumpAndSettle();
    expect(find.text('165'), findsOneWidget);
    expect(find.text('34,5'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Aggiungi a pranzo'));
    await tester.pumpAndSettle();

    expect(find.text('Petto di pollo'), findsOneWidget);
    expect(find.text('165 kcal'), findsWidgets);
    final voce = telefono.nucleo.cibo.giornata(DateTime(2026, 10, 21)).voci.single;
    expect(voce.fonte, FonteCibo.atleta);
    expect(voce.grammi, 150);

    // Toccandola si correggono i grammi.
    await tester.tap(find.text('Petto di pollo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '200');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('220 kcal'), findsWidgets);

    // La prossima volta è tra i recenti.
    await tester.tap(find.text('Aggiungi').first);
    await tester.pumpAndSettle();
    expect(find.text('Recenti'), findsOneWidget);
    expect(find.text('Petto di pollo'), findsOneWidget);

    // Scrivendo si trova tra i cibi già usati, senza chiedere al coach.
    await tester.enterText(find.byType(TextField), 'PET');
    await tester.pumpAndSettle();
    expect(find.text('Già usati'), findsOneWidget);
    expect(find.text('Petto di pollo'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'riso');
    await tester.pumpAndSettle();
    expect(find.textContaining('Nessun cibo già usato'), findsOneWidget);
  });

  testWidgets("l'obiettivo del coach e la condivisione", (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    telefono.archivio.db.execute('UPDATE coach SET obiettivo_cibo = ? WHERE id = ?', [
      jsonEncode(const ObiettivoCibo(kcal: 2200, proteineG: 140).toJson()),
      coach,
    ]);
    await apriCibo(tester);
    expect(find.text('/ 2.200'), findsOneWidget);
    expect(find.textContaining('P 0/140 g'), findsOneWidget);

    await tester.scrollUntilVisible(find.byType(Switch), 300);
    expect(find.text('Vede quello che mangi'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(telefono.nucleo.collegamenti.cerca(coach)!.condivideCibo, isFalse);
  });

  test('i numeri si leggono come in italiano', () {
    expect(intero(1850.4), '1.850');
    expect(intero(95), '95');
    expect(leggiGrammi('12,5'), 12.5);
    expect(leggiGrammi('0'), isNull);
    expect(leggiGrammi('6000'), isNull);
  });
}
