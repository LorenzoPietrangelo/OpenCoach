import 'package:atleta_app/app.dart';
import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';

import 'supporto.dart';

void main() {
  late TelefonoDiProva telefono;

  setUp(() => telefono = TelefonoDiProva());
  tearDown(() => telefono.chiudi());

  Future<void> apri(WidgetTester tester) async {
    await tester.pumpWidget(AppAtleta(nucleo: telefono.nucleo));
    await tester.pumpAndSettle();
  }

  void dalCoach(int coach, String testo) => telefono.archivio.db.execute(
    'INSERT INTO messaggi (coach_id, id, dal_coach, testo, inviato_il, ordine, stato, letto) '
    "VALUES (?, ?, 1, ?, '2026-10-21T18:00:00+02:00', '2026-10-21T16:00:00.000Z', 'inviato', 0)",
    [coach, nuovoUuid(), testo],
  );

  Map<String, Object?> questionario(String titolo) => {
    'id': nuovoUuid(),
    'titolo': titolo,
    'descrizione': '',
    'domande': const <Object?>[],
  };

  testWidgets('con il coach ci sono subito Allenamento, Chat, Cibo e Peso', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    telefono.aggiungiScheda(coach, schedaForza());
    await apri(tester);

    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('Marco Bianchi'), findsOneWidget);
    expect(find.text('Forza – blocco 2'), findsOneWidget);
    expect(find.text('Allenamento libero'), findsOneWidget);

    await tester.tap(find.text('Peso'));
    await tester.pumpAndSettle();
    expect(find.text('Peso di oggi'), findsOneWidget);
    expect(find.text('Allenamento libero'), findsNothing);

    await tester.tap(find.text('Cibo'));
    await tester.pumpAndSettle();
    expect(find.text('Colazione'), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Chat con Marco Bianchi'), findsOneWidget);
  });

  testWidgets('i messaggi restano da leggere finché non si apre la chat', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    dalCoach(coach, 'Domani carichi pesanti');
    await apri(tester);
    expect(telefono.nucleo.chat.nonLetti(coach), 1);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Domani carichi pesanti'), findsOneWidget);
    expect(telefono.nucleo.chat.nonLetti(coach), 0);

    // Da un'altra sezione, quello che arriva resta da leggere.
    await tester.tap(find.text('Peso'));
    await tester.pumpAndSettle();
    dalCoach(coach, 'E dormi bene');
    telefono.nucleo.contesto.segnala(coach);
    await tester.pumpAndSettle();
    expect(telefono.nucleo.chat.nonLetti(coach), 1);
  });

  testWidgets('il questionario arriva nella chat e resta in vista finché è da compilare', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    dalCoach(coach, 'Ti ho mandato il check');
    telefono.aggiungiQuestionario(coach, questionario('Check mensile'));
    await apri(tester);
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    // In cima e in mezzo ai messaggi.
    expect(find.text('Check mensile'), findsNWidgets(2));
    expect(find.text('Ti ho mandato il check'), findsOneWidget);

    await tester.tap(find.text('Check mensile').first);
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('Check mensile'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Risposto, resta solo in mezzo ai messaggi.
    telefono.archivio.db.execute("UPDATE questionari SET stato = 'inviato'");
    telefono.nucleo.contesto.segnala(coach);
    await tester.pumpAndSettle();
    expect(find.text('Check mensile'), findsOneWidget);
    expect(find.text('Arrivato al coach'), findsOneWidget);
  });

  testWidgets('storico e archivio restano chiusi finché non si aprono', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    telefono.aggiungiScheda(coach, schedaForza(titolo: 'Attiva'), vista: true);
    telefono.aggiungiScheda(coach, schedaForza(titolo: 'Vecchia', archiviata: true), vista: true);
    telefono.nucleo.diario.salva(coach, logLibero('Corsa', eseguitoIl: DateTime(2026, 10, 1)));
    await apri(tester);
    expect(find.text('Attiva'), findsOneWidget);
    expect(find.text('Storico (1)'), findsOneWidget);
    expect(find.text('Archivio (1)'), findsOneWidget);
    expect(find.textContaining('Corsa'), findsNothing);
    expect(find.text('Vecchia'), findsNothing);

    await tester.tap(find.text('Storico (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Corsa'), findsOneWidget);
    expect(find.text('Vecchia'), findsNothing);

    await tester.tap(find.text('Archivio (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Vecchia'), findsOneWidget);

    // Da un'altra sezione e ritorno restano aperti.
    await tester.tap(find.text('Peso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allenamento'));
    await tester.pumpAndSettle();
    expect(find.text('Vecchia'), findsOneWidget);
  });

  testWidgets('chi aveva due coach sceglie quale tenere; degli altri restano i dati', (tester) async {
    final marco = telefono.aggiungiCoach('Marco Bianchi');
    final anna = telefono.aggiungiCoach('Anna Neri');
    await apri(tester);
    expect(find.text('Scegli il tuo coach'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.text('Anna Neri'));
    await tester.pumpAndSettle();
    // Finché non conferma, non succede niente.
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(telefono.nucleo.collegamenti.attivi(), hasLength(2));

    await tester.tap(find.text('Anna Neri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Anna Neri'), findsOneWidget);
    expect(telefono.nucleo.collegamenti.cerca(marco)!.stato, StatoCollegamento.scollegato);
    expect(telefono.nucleo.collegamenti.cerca(anna)!.stato, StatoCollegamento.attivo);

    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pumpAndSettle();
    expect(find.text('Coach precedenti'), findsOneWidget);
    expect(find.text('Cambia coach'), findsOneWidget);
    await tester.tap(find.text('Vedi'));
    await tester.pumpAndSettle();
    expect(find.text('Marco Bianchi'), findsOneWidget);
    expect(find.text('Allenamento libero'), findsNothing);
  });

  testWidgets('scollegato dal coach, si riparte dal collegamento', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    await apri(tester);
    await telefono.nucleo.collegamenti.scollega(coach);
    await tester.pumpAndSettle();
    expect(find.text('Collegati al tuo coach'), findsOneWidget);
    expect(find.byTooltip('Impostazioni'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
