import 'package:atleta_app/app.dart';
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
    expect(find.textContaining('1 scheda da vedere'), findsOneWidget);

    await tester.tap(find.text('Marco Bianchi'));
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
    expect(find.text('Archivio'), findsOneWidget);
    expect(find.text('Forza – blocco 1'), findsOneWidget);
    // Senza Tor la sync non parte, e lo stato lo dice (§7.5).
    expect(find.textContaining('rete Tor'), findsOneWidget);

    await tester.tap(find.text('Forza – blocco 2'));
    await tester.pumpAndSettle();
    expect(find.text('Revisione nuova'), findsOneWidget);
    expect(find.text('Giorno A'), findsOneWidget);
    expect(find.text('Giorno B'), findsOneWidget);
    expect(find.text('4 × 6-8 · 75% 1RM · recupero 2:30'), findsOneWidget);
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

    await tester.pumpWidget(AppAtleta(nucleo: telefono.nucleo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marco Bianchi'));
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
