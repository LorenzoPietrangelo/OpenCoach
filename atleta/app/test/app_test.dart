import 'package:atleta_app/app.dart';
import 'package:atleta_app/l10n/testi.dart';
import 'package:atleta_app/piattaforma/tor_non_integrato.dart';
import 'package:atleta_app/schermate/aggiungi_coach.dart';
import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';

import 'supporto.dart';

void main() {
  late ArchivioAtleta archivio;
  late NucleoAtleta nucleo;

  setUp(() {
    archivio = ArchivioAtleta.inMemoria();
    nucleo = NucleoAtleta(
      archivio: archivio,
      cassaforte: CassaforteMemoria(),
      tor: const TorNonIntegrato(),
      dispositivo: const DatiDispositivo(
        nome: 'Telefono di prova',
        piattaforma: 'android',
        versioneApp: '1.0.0',
      ),
    );
  });

  tearDown(() async {
    await nucleo.chiudi();
    archivio.chiudi();
  });

  testWidgets('senza coach invita ad aggiungerne uno', (tester) async {
    await tester.pumpWidget(AppAtleta(nucleo: nucleo));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nessun coach collegato'), findsOneWidget);
    expect(find.text('Aggiungi coach'), findsOneWidget);
  });

  testWidgets('un invito incollato male mostra il messaggio del §5.4', (
    tester,
  ) async {
    await tester.pumpWidget(AppAtleta(nucleo: nucleo));
    await tester.tap(find.text('Aggiungi coach'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'https://esempio.it');
    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();
    expect(
      find.text('Questo codice non è un invito di Open Coach.'),
      findsOneWidget,
    );
  });

  testWidgets("il QR inquadrato porta all'abbinamento", (tester) async {
    // Il QR contiene l'URI intero (§5.2).
    final qr = linkInvito();
    final scansioni = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: Testi.localizationsDelegates,
        supportedLocales: Testi.supportedLocales,
        home: AggiungiCoach(
          nucleo: nucleo,
          scansiona: (_) async {
            scansioni.add('fotocamera');
            return qr;
          },
        ),
      ),
    );
    await tester.tap(find.text('Scansiona il QR'));
    await tester.pumpAndSettle();
    expect(scansioni, ['fotocamera']);
    // L'invito è valido: senza Tor l'abbinamento si ferma lì (§7.5).
    expect(find.textContaining('rete Tor'), findsOneWidget);
    expect(nucleo.collegamenti.elenco(), isEmpty);
  });

  testWidgets('chi chiude la fotocamera resta sulla schermata', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: Testi.localizationsDelegates,
        supportedLocales: Testi.supportedLocales,
        home: AggiungiCoach(nucleo: nucleo, scansiona: (_) async => null),
      ),
    );
    await tester.tap(find.text('Scansiona il QR'));
    await tester.pumpAndSettle();
    expect(find.text('Collegati al tuo coach'), findsOneWidget);
    expect(find.textContaining('Questo codice'), findsNothing);
    expect(find.textContaining('rete Tor'), findsNothing);
  });
}
