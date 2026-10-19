import 'package:atleta_app/app.dart';
import 'package:atleta_app/piattaforma/tor_non_integrato.dart';
import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';

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
}
