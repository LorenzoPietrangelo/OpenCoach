import 'package:atleta_app/piattaforma/sync_in_background.dart';
import 'package:atleta_app/schermate/principale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'supporto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messaggi =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late TelefonoDiProva telefono;

  /// Come il codice Kotlin vede la batteria dell'app.
  late String stato;

  /// Fino a quando il consiglio è rimandato, in millisecondi; 0 se non lo è.
  late int rimandato;
  late List<MethodCall> chiamate;

  setUp(() {
    telefono = TelefonoDiProva();
    stato = 'ottimizzata';
    rimandato = 0;
    chiamate = [];
    messaggi.setMockMethodCallHandler(SyncInBackground.canalePredefinito, (
      chiamata,
    ) async {
      chiamate.add(chiamata);
      return switch (chiamata.method) {
        'statoBatteria' => stato,
        'avvisoBatteriaRimandato' => rimandato,
        _ => null,
      };
    });
  });

  tearDown(() async {
    messaggi.setMockMethodCallHandler(SyncInBackground.canalePredefinito, null);
    await telefono.chiudi();
  });

  Future<void> apri(WidgetTester tester) async {
    await tester.pumpWidget(
      conTesti(
        // Ogni apertura è una schermata nuova, come all'avvio dell'app.
        SchermataPrincipale(
          key: UniqueKey(),
          nucleo: telefono.nucleo,
          background: SyncInBackground(telefono.nucleo),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> metodi() => [for (final c in chiamate) c.method];

  testWidgets('con la batteria «Ottimizzata» consiglia «Senza restrizioni»', (
    tester,
  ) async {
    telefono.aggiungiCoach('Marco Bianchi');
    await apri(tester);
    expect(find.text('Ricevi le schede prima'), findsOneWidget);
    expect(find.textContaining('«Senza restrizioni»'), findsOneWidget);

    await tester.tap(find.text("Apri le impostazioni dell'app"));
    await tester.pumpAndSettle();
    expect(metodi(), contains('apriImpostazioniApp'));
    expect(metodi(), isNot(contains('rimandaAvvisoBatteria')));
  });

  testWidgets('con la batteria «Limitata» dice che le schede arrivano solo '
      'ad app aperta', (tester) async {
    stato = 'limitata';
    telefono.aggiungiCoach('Marco Bianchi');
    await apri(tester);
    expect(find.text("Le schede arrivano solo ad app aperta"), findsOneWidget);

    // «Non ora» lo nasconde per una settimana.
    await tester.tap(find.text('Non ora'));
    await tester.pumpAndSettle();
    final rinvio = chiamate.singleWhere(
      (c) => c.method == 'rimandaAvvisoBatteria',
    );
    final fino = DateTime.fromMillisecondsSinceEpoch(
      (rinvio.arguments as Map<Object?, Object?>)['fino']! as int,
    );
    expect(
      fino.difference(telefono.orologio.ora),
      const Duration(days: 7),
    );
  });

  testWidgets('niente consiglio con «Senza restrizioni», senza coach o se '
      'rimandato', (tester) async {
    // Senza coach collegati non serve.
    await apri(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(metodi(), isNot(contains('statoBatteria')));

    telefono.aggiungiCoach('Marco Bianchi');
    stato = 'senza_restrizioni';
    chiamate.clear();
    await apri(tester);
    expect(metodi(), contains('statoBatteria'));
    expect(find.byType(AlertDialog), findsNothing);

    stato = 'ottimizzata';
    rimandato = telefono.orologio.ora
        .add(const Duration(days: 2))
        .millisecondsSinceEpoch;
    chiamate.clear();
    await apri(tester);
    expect(metodi(), contains('avvisoBatteriaRimandato'));
    expect(find.byType(AlertDialog), findsNothing);

    // Passata la settimana torna.
    telefono.orologio.avanza(const Duration(days: 3));
    await apri(tester);
    expect(find.text('Ricevi le schede prima'), findsOneWidget);
  });
}
