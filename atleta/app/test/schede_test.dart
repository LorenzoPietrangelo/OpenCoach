import 'package:atleta_app/app.dart';
import 'package:atleta_app/schermate/allenamento.dart';
import 'package:atleta_app/schermate/pagina_coach.dart';
import 'package:atleta_app/schermate/dettaglio_scheda.dart';
import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'supporto.dart';

void main() {
  late TelefonoDiProva telefono;

  setUp(() => telefono = TelefonoDiProva());
  tearDown(() => telefono.chiudi());

  testWidgets('le schede del coach: da vedere, archivio e dettaglio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    final forza = schedaForza();
    telefono.aggiungiScheda(coach, forza);
    telefono.aggiungiScheda(
      coach,
      schedaForza(titolo: 'Mobilità'),
      vista: true,
    );
    telefono.aggiungiScheda(
      coach,
      schedaForza(titolo: 'Forza – blocco 1', archiviata: true),
      vista: true,
    );

    await tester.pumpWidget(AppAtleta(nucleo: telefono.nucleo));
    await tester.pumpAndSettle();
    expect(find.text('Forza – blocco 2'), findsOneWidget);
    expect(find.text('Mobilità'), findsOneWidget);
    expect(find.text('Da vedere'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Mobilità'),
        matching: find.text('Da vedere'),
      ),
      findsNothing,
    );
    expect(find.text('Forza – blocco 1'), findsNothing);
    await tester.tap(find.text('Archivio (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Forza – blocco 1'), findsOneWidget);
    // Senza Tor la sync non parte, e lo stato lo dice (§7.5).
    expect(find.textContaining('rete Tor'), findsOneWidget);

    // Due sedute: si sceglie quale fare, oppure si guarda tutta la scheda.
    await tester.tap(find.text('Forza – blocco 2'));
    await tester.pumpAndSettle();
    expect(find.text('Quale seduta fai?'), findsOneWidget);
    await tester.tap(find.text('Vedi tutta la scheda'));
    await tester.pumpAndSettle();
    expect(find.text('Revisione nuova'), findsOneWidget);
    expect(find.text('Giorno A'), findsOneWidget);
    expect(find.text('Giorno B'), findsOneWidget);
    expect(find.text('4 × 6-8 · 75% 1RM · recupero 2:30 · RIR 1-2'), findsOneWidget);
    expect(find.text('3 × 30 s'), findsOneWidget);
    expect(find.text('Pausa di 1 s in buca'), findsOneWidget);
    expect(find.text('Inizia'), findsNWidgets(2));
    // Aperta l'ultima revisione, l'avviso sparisce.
    expect(
      telefono.nucleo.schede.cerca(coach, forza['id']! as String)!.daVedere,
      isFalse,
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Da vedere'), findsNothing);
  });

  testWidgets('toccando una scheda parte subito l\'allenamento', (
    tester,
  ) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    final forza = schedaForza();
    telefono.aggiungiScheda(coach, forza);
    final unaSeduta = schedaForza(titolo: 'Mobilità')
      ..['sedute'] = [(forza['sedute']! as List<Object?>).last];
    telefono.aggiungiScheda(coach, unaSeduta, vista: true);

    await tester.pumpWidget(conTesti(SezioneAllenamento(nucleo: telefono.nucleo, coachId: coach)));
    await tester.pumpAndSettle();

    // Con più sedute si sceglie quale; si apre l'allenamento, non il riepilogo.
    await tester.tap(find.text('Forza – blocco 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giorno A'));
    await tester.pumpAndSettle();
    expect(find.byType(SchermataAllenamento), findsOneWidget);
    expect(find.byType(DettaglioScheda), findsNothing);
    expect(find.text('Squat'), findsOneWidget);
    // Le note della scheda si vedono anche qui.
    expect(find.text('Riscaldamento di 10 minuti prima di ogni seduta.'), findsOneWidget);
    expect(
      telefono.nucleo.schede.cerca(coach, forza['id']! as String)!.daVedere,
      isFalse,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Con una seduta sola si entra direttamente.
    await tester.tap(find.text('Mobilità'));
    await tester.pumpAndSettle();
    expect(find.byType(SchermataAllenamento), findsOneWidget);
    expect(find.text('Giorno B'), findsOneWidget);
    expect(find.text('Quale seduta fai?'), findsNothing);
  });

  testWidgets('una scheda archiviata si consulta ma non si esegue', (
    tester,
  ) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    final vecchia = schedaForza(archiviata: true);
    telefono.aggiungiScheda(coach, vecchia, vista: true);

    await tester.pumpWidget(
      conTesti(
        DettaglioScheda(
          nucleo: telefono.nucleo,
          coachId: coach,
          schedaId: vecchia['id']! as String,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Scheda archiviata'), findsOneWidget);
    expect(find.text('Giorno A'), findsOneWidget);
    expect(find.text('Inizia'), findsNothing);
  });

  testWidgets('dopo una revoca schede e storico restano in sola lettura', (
    tester,
  ) async {
    final coach = telefono.aggiungiCoach(
      'Marco Bianchi',
      stato: StatoCollegamento.revocato,
      problema: ProblemaSync.revocato,
    );
    final scheda = schedaForza();
    telefono.aggiungiScheda(coach, scheda, vista: true);

    await tester.pumpWidget(conTesti(PaginaCoach(nucleo: telefono.nucleo, coachId: coach)));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Il coach ha chiuso il collegamento.'),
      findsOneWidget,
    );
    expect(find.text('Sincronizza ora'), findsNothing);
    expect(find.text('Allenamento libero'), findsNothing);

    await tester.tap(find.text('Forza – blocco 2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('in sola lettura'), findsOneWidget);
    expect(find.text('Inizia'), findsNothing);
  });
}
