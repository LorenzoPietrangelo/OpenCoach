import 'dart:convert';

import 'package:atleta_app/schermate/impostazioni.dart';
import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'supporto.dart';

void main() {
  late TelefonoDiProva telefono;

  setUp(() => telefono = TelefonoDiProva());
  tearDown(() => telefono.chiudi());

  testWidgets('i coach collegati con indirizzo e ultima sync', (tester) async {
    final marco = telefono.aggiungiCoach(
      'Marco Bianchi',
      ultimaSync: DateTime(2026, 10, 21, 7),
    );
    telefono.aggiungiCoach(
      'Anna Neri',
      stato: StatoCollegamento.revocato,
      problema: ProblemaSync.revocato,
    );

    await tester.pumpWidget(conTesti(Impostazioni(nucleo: telefono.nucleo)));
    await tester.pumpAndSettle();
    final indirizzo = telefono.nucleo.collegamenti.cerca(marco)!.indirizzo;
    expect(find.text('Marco Bianchi'), findsOneWidget);
    expect(find.text('$indirizzo.onion'), findsOneWidget);
    expect(find.textContaining('Ultima sync: '), findsOneWidget);
    expect(find.text('Anna Neri'), findsOneWidget);
    expect(find.text('Non ancora sincronizzato'), findsOneWidget);
    expect(find.text('Il coach ha chiuso il collegamento.'), findsOneWidget);
    expect(find.text('Scollegati'), findsOneWidget);
    expect(find.text('Cancella'), findsOneWidget);
  });

  testWidgets('scollegarsi da un coach e poi cancellarne i dati', (
    tester,
  ) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    telefono.aggiungiScheda(coach, schedaForza(), vista: true);
    telefono.nucleo.diario.salva(
      coach,
      logLibero('Corsa', eseguitoIl: DateTime(2026, 10, 20)),
    );

    await tester.pumpWidget(conTesti(Impostazioni(nucleo: telefono.nucleo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scollegati'));
    await tester.pumpAndSettle();
    expect(find.text('Scollegarti da Marco Bianchi?'), findsOneWidget);
    expect(
      find.textContaining(
        '1 allenamento in attesa di invio non arriverà al coach.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Scollegati'));
    await tester.pumpAndSettle();

    // Senza Tor il coach non si raggiunge: il dispositivo resta attivo sul
    // suo PC finché non lo revoca lui. I dati si cancellano solo dopo
    // un'altra conferma.
    expect(
      telefono.nucleo.collegamenti.cerca(coach)!.stato,
      StatoCollegamento.scollegato,
    );
    expect(find.text('Cancellare i dati di Marco Bianchi?'), findsOneWidget);
    expect(find.textContaining('non era raggiungibile'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Cancella'));
    await tester.pumpAndSettle();
    expect(telefono.nucleo.collegamenti.cerca(coach), isNull);
    expect(telefono.nucleo.schede.elenco(coach), isEmpty);
    expect(telefono.nucleo.diario.elenco(coach), isEmpty);
    expect(find.text('Marco Bianchi'), findsNothing);
    expect(find.text('Non hai ancora collegato nessun coach.'), findsOneWidget);
  });

  testWidgets('dopo lo scollegamento i dati si possono conservare', (
    tester,
  ) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');

    await tester.pumpWidget(conTesti(Impostazioni(nucleo: telefono.nucleo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scollegati'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Scollegati'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conserva'));
    await tester.pumpAndSettle();
    expect(
      telefono.nucleo.collegamenti.cerca(coach)!.stato,
      StatoCollegamento.scollegato,
    );
    expect(find.text('Non sei più collegato a questo coach.'), findsOneWidget);

    // Più tardi si cancellano dal pulsante del coach.
    await tester.tap(find.text('Cancella'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancella'));
    await tester.pumpAndSettle();
    expect(telefono.nucleo.collegamenti.cerca(coach), isNull);
  });

  testWidgets('esporta i dati in JSON', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    telefono.aggiungiScheda(coach, schedaForza(), vista: true);
    telefono.nucleo.diario.salva(
      coach,
      logLibero('Corsa', eseguitoIl: DateTime(2026, 10, 20)),
    );
    final file = <String, String>{};

    await tester.pumpWidget(
      conTesti(
        Impostazioni(
          nucleo: telefono.nucleo,
          esporta: (nome, contenuto) async => file[nome] = contenuto,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Esporta i tuoi dati'));
    await tester.tap(find.text('Esporta i tuoi dati'));
    await tester.pumpAndSettle();

    expect(file.keys, ['open-coach-2026-10-21.json']);
    final dati = jsonDecode(file.values.single) as Map<String, Object?>;
    expect(dati['formato'], 'open-coach-atleta');
    final coachEsportato =
        (dati['coach']! as List<Object?>).single! as Map<String, Object?>;
    expect(coachEsportato['nome_coach'], 'Marco Bianchi');
    expect(coachEsportato['schede'], hasLength(1));
    expect(coachEsportato['log'], hasLength(1));
    // Né chiavi né token (§11.3).
    expect(file.values.single, isNot(contains('token')));
  });

  testWidgets("se l'esportazione non riesce lo dice", (tester) async {
    await tester.pumpWidget(
      conTesti(
        Impostazioni(
          nucleo: telefono.nucleo,
          esporta: (_, _) async => throw Exception('nessuna app'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Esporta i tuoi dati'));
    await tester.tap(find.text('Esporta i tuoi dati'));
    await tester.pumpAndSettle();
    expect(find.text('Esportazione non riuscita.'), findsOneWidget);
  });
}
