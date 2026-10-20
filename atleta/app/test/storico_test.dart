import 'package:atleta_app/schermate/pagina_coach.dart';
import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';

import 'supporto.dart';

void main() {
  late TelefonoDiProva telefono;

  setUp(() => telefono = TelefonoDiProva());
  tearDown(() => telefono.chiudi());

  Future<void> apriStorico(WidgetTester tester, int coach) async {
    await tester.pumpWidget(
      conTesti(PaginaCoach(nucleo: telefono.nucleo, coachId: coach)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Storico'));
    await tester.pumpAndSettle();
  }

  testWidgets('lo storico dice quali allenamenti aspettano, quali sono '
      'arrivati e quali il coach ha rifiutato', (tester) async {
    final coach = telefono.aggiungiCoach(
      'Marco Bianchi',
      ultimaSync: DateTime(2026, 10, 21, 7),
    );
    final diario = telefono.nucleo.diario;
    diario.salva(coach, logLibero('Corsa', eseguitoIl: DateTime(2026, 10, 20)));
    final inviato = diario.salva(
      coach,
      logLibero('Nuoto', eseguitoIl: DateTime(2026, 10, 19)),
    );
    telefono.confermaLog(inviato.id);
    final rifiutato = diario.salva(
      coach,
      logLibero('Bici', eseguitoIl: DateTime(2026, 10, 18)),
    );
    telefono.rifiutaLog(rifiutato.id, RifiutoLog.nonValido);

    await apriStorico(tester, coach);
    // Lo stato della sync (§7.5) sopra le schede.
    expect(
      find.textContaining('1 allenamento in attesa di invio'),
      findsOneWidget,
    );
    expect(
      find.textContaining('1 allenamento rifiutato dal coach'),
      findsOneWidget,
    );
    expect(find.textContaining('In attesa di invio'), findsOneWidget);
    expect(find.textContaining('Inviato al coach'), findsOneWidget);
    expect(
      find.textContaining(
        'Rifiutato dal coach: non rispetta il formato di Open Coach',
      ),
      findsOneWidget,
    );
  });

  testWidgets('un allenamento rifiutato si rimette in coda, si modifica e si '
      'elimina', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    final log = telefono.nucleo.diario.salva(
      coach,
      logLibero('Bici', eseguitoIl: DateTime(2026, 10, 18, 7)),
    );
    telefono.rifiutaLog(log.id, RifiutoLog.troppoGrande);

    await apriStorico(tester, coach);
    await tester.tap(find.textContaining('Rifiutato dal coach'));
    await tester.pumpAndSettle();
    expect(find.text('Bici'), findsOneWidget);
    expect(find.text('Durata: 40 min'), findsOneWidget);
    expect(find.text('1. 40 min'), findsOneWidget);

    // Il coach non lo ritenta da sé (§7.3): lo rimette in coda l'atleta.
    await tester.tap(find.text('Invia di nuovo'));
    await tester.pumpAndSettle();
    expect(
      find.text("L'allenamento partirà con la prossima sync."),
      findsOneWidget,
    );
    expect(find.text('In attesa di invio'), findsOneWidget);
    expect(telefono.nucleo.diario.cerca(coach, log.id)!.inAttesa, isTrue);

    // Ogni modifica incrementa rev (§10.2).
    await tester.tap(find.byTooltip('Modifica'));
    await tester.pumpAndSettle();
    expect(find.text('Allenamento libero'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '2700');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Modifiche salvate'), findsOneWidget);
    expect(find.text('1. 45 min'), findsOneWidget);
    final modificato = telefono.nucleo.diario.cerca(coach, log.id)!;
    expect(modificato.rev, 2);
    final esercizio =
        (modificato.contenuto!['esercizi']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(esercizio['serie'], [
      {'durata_s': 2700, 'completata': true},
    ]);
    // Data e durata restano quelle del log.
    expect(
      modificato.contenuto!['eseguito_il'],
      formattaDataOra(DateTime(2026, 10, 18, 7)),
    );
    expect(modificato.contenuto!['durata_min'], 40);

    await tester.tap(find.byTooltip('Elimina'));
    await tester.pumpAndSettle();
    expect(find.text("Eliminare l'allenamento?"), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Elimina'));
    await tester.pumpAndSettle();
    expect(telefono.nucleo.diario.cerca(coach, log.id)!.eliminato, isTrue);
    expect(telefono.nucleo.diario.elenco(coach), isEmpty);
    expect(find.textContaining('Nessun allenamento'), findsOneWidget);
  });

  testWidgets('con il collegamento chiuso lo storico è in sola lettura', (
    tester,
  ) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    final log = telefono.nucleo.diario.salva(
      coach,
      logLibero('Bici', eseguitoIl: DateTime(2026, 10, 18, 7)),
    );
    telefono.rifiutaLog(log.id, RifiutoLog.altroAtleta);
    telefono.archivio.db.execute(
      "UPDATE coach SET stato = 'revocato', problema = 'revocato'",
    );

    await apriStorico(tester, coach);
    await tester.tap(find.textContaining('Rifiutato dal coach'));
    await tester.pumpAndSettle();
    expect(find.textContaining('risulta di un altro atleta'), findsOneWidget);
    expect(find.text('Invia di nuovo'), findsNothing);
    expect(find.byTooltip('Modifica'), findsNothing);
    expect(find.byTooltip('Elimina'), findsNothing);
    expect(
      telefono.nucleo.collegamenti.cerca(coach)!.stato,
      StatoCollegamento.revocato,
    );
  });
}
