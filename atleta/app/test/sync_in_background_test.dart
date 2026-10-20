import 'dart:async';

import 'package:atleta_app/l10n/testi.dart';
import 'package:atleta_app/piattaforma/sync_in_background.dart';
import 'package:atleta_app/piattaforma/tor_non_integrato.dart';
import 'package:atleta_app/schermate/impostazioni.dart';
import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messaggi =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ArchivioAtleta archivio;
  late NucleoAtleta nucleo;

  /// Le chiamate al codice Kotlin, che qui risponde come farebbe l'app.
  late List<MethodCall> chiamate;

  /// La batteria dell'app è «Limitata».
  var limitata = false;

  setUp(() {
    limitata = false;
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
    chiamate = [];
    messaggi.setMockMethodCallHandler(SyncInBackground.canalePredefinito, (
      chiamata,
    ) async {
      chiamate.add(chiamata);
      return switch (chiamata.method) {
        'pronto' => false,
        'frequenza' => 60,
        'limitata' => limitata,
        _ => null,
      };
    });
  });

  tearDown(() async {
    messaggi.setMockMethodCallHandler(SyncInBackground.canalePredefinito, null);
    await nucleo.chiudi();
    archivio.chiudi();
  });

  /// Una chiamata del codice Kotlin al lato Dart, con la sua risposta.
  Future<Object?> chiamaDaKotlin(String metodo) async {
    const codec = StandardMethodCodec();
    final risposta = Completer<ByteData?>();
    await messaggi.handlePlatformMessage(
      SyncInBackground.canalePredefinito.name,
      codec.encodeMethodCall(MethodCall(metodo)),
      risposta.complete,
    );
    return codec.decodeEnvelope((await risposta.future)!);
  }

  test('una notifica per ogni coach con schede nuove, con i titoli', () {
    SchedaRicevuta scheda(int coachId, String titolo, {int revisione = 1}) =>
        SchedaRicevuta(
          coachId: coachId,
          id: titolo,
          revisione: revisione,
          archiviata: false,
          contenuto: {'titolo': titolo},
          ricevutaIl: DateTime(2026, 10, 20),
          daVedere: true,
        );
    final notifiche = notificheSchede(
      [
        EsitoSync(coachId: 1, schedeNuove: [scheda(1, 'Forza')]),
        const EsitoSync(coachId: 2),
        const EsitoSync(
          coachId: 3,
          problema: ProblemaSync.coachIrraggiungibile,
        ),
        EsitoSync(
          coachId: 4,
          schedeNuove: [
            scheda(4, 'Corsa'),
            scheda(4, 'Mobilità', revisione: 3),
          ],
        ),
      ],
      (id) => id == 1 ? 'Marco Bianchi' : 'Anna Neri',
      lookupTesti(const Locale('it')),
    );
    expect(
      [for (final notifica in notifiche) notifica.perAndroid()],
      [
        {
          'coach': 1,
          'titolo': 'Nuova scheda da Marco Bianchi',
          'testo': 'Forza',
        },
        {
          'coach': 4,
          'titolo': '2 schede nuove da Anna Neri',
          'testo': 'Corsa, Mobilità',
        },
      ],
    );
  });

  test('collega pianifica il lavoro, dice che il nucleo è pronto e risponde '
      'alle sync chieste da WorkManager', () async {
    final background = SyncInBackground(nucleo);
    expect(await background.collega(), isFalse);
    expect([for (final c in chiamate) c.method], ['pianifica', 'pronto']);
    expect(chiamate.first.arguments, {'attiva': false});

    // Senza coach collegati la sync non ha notifiche da mostrare.
    expect(await chiamaDaKotlin('sincronizzaInBackground'), isEmpty);

    // Nessuna sync in corso e nessun coach: niente lavoro accelerato né
    // richiesta del permesso per le notifiche.
    chiamate.clear();
    await background.proseguiSeInCorso();
    await background.chiediPermessoNotifiche();
    await background.aggiornaPianificazione();
    expect(chiamate, isEmpty);
    await background.chiudi();
  });

  testWidgets('le impostazioni scelgono la frequenza della sync', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: Testi.localizationsDelegates,
        supportedLocales: Testi.supportedLocales,
        home: Impostazioni(background: SyncInBackground(nucleo)),
      ),
    );
    await tester.pumpAndSettle();
    Finder spunta(String voce) => find.descendant(
      of: find.widgetWithText(ListTile, voce),
      matching: find.byIcon(Icons.check),
    );
    expect(find.text('Disattivata'), findsOneWidget);
    expect(spunta('Ogni ora'), findsOneWidget);

    await tester.tap(find.text('Ogni 3 ore'));
    await tester.pumpAndSettle();
    expect(chiamate.last.method, 'impostaFrequenza');
    expect(chiamate.last.arguments, {'minuti': 180, 'attiva': false});
    expect(spunta('Ogni 3 ore'), findsOneWidget);
    expect(spunta('Ogni ora'), findsNothing);
  });

  testWidgets('con la batteria «Limitata» le impostazioni lo dicono', (
    tester,
  ) async {
    limitata = true;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: Testi.localizationsDelegates,
        supportedLocales: Testi.supportedLocales,
        home: Impostazioni(background: SyncInBackground(nucleo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('non lasciano lavorare Open Coach'),
      findsOneWidget,
    );
    await tester.tap(find.text("Apri le impostazioni dell'app"));
    await tester.pumpAndSettle();
    expect(chiamate.last.method, 'apriImpostazioniApp');
  });

  testWidgets('senza sync in background le impostazioni lo spiegano', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: Testi.localizationsDelegates,
        supportedLocales: Testi.supportedLocales,
        home: const Impostazioni(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining("quando apri l'app"), findsOneWidget);
    expect(find.text('Ogni ora'), findsNothing);
  });
}
