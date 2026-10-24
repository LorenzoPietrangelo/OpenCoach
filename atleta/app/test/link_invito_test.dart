import 'dart:async';
import 'dart:io';

import 'package:atleta_app/app.dart';
import 'package:atleta_app/piattaforma/inviti_in_arrivo.dart';
import 'package:atleta_app/schermate/aggiungi_coach.dart';
import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'supporto.dart';

/// Il sistema apre [link] nell'app, come fanno MainActivity e iOS (§5.3).
/// Restituisce la risposta dell'app: vero se il link l'ha preso lei.
Future<bool> apriLink(WidgetTester tester, String link) async {
  final risposta = await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage(
        SystemChannels.navigation.name,
        SystemChannels.navigation.codec.encodeMethodCall(
          MethodCall('pushRouteInformation', {'location': link}),
        ),
        null,
      );
  return SystemChannels.navigation.codec.decodeEnvelope(risposta!) as bool;
}

/// Tor che non risponde finché il test non lo fa fallire: intanto
/// l'abbinamento resta in corso.
class _TorLento implements TrasportoTor {
  final _avvio = Completer<void>();
  var avvii = 0;

  void nonParte() => _avvio.completeError(const TorNonParte());

  @override
  Future<void> avvia({void Function(int percento)? avanzamento}) {
    avvii++;
    avanzamento?.call(30);
    return _avvio.future;
  }

  @override
  Future<void> ferma() async {}

  @override
  Future<void> impostaChiave(String indirizzo, Uint8List chiavePrivata) async {}

  @override
  Future<void> rimuoviChiave(String indirizzo) async {}

  @override
  HttpClient creaHttpClient() => throw UnsupportedError('Tor non è partito');
}

void main() {
  late TelefonoDiProva telefono;
  late InvitiInArrivo inviti;

  tearDown(() async {
    inviti.dispose();
    await telefono.chiudi();
  });

  String testoDelCampo(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets("un link aperto da un'altra app porta all'abbinamento", (
    tester,
  ) async {
    telefono = TelefonoDiProva();
    inviti = InvitiInArrivo();
    final link = linkInvito();
    await tester.pumpWidget(AppAtleta(nucleo: telefono.nucleo, inviti: inviti));
    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pumpAndSettle();

    expect(await apriLink(tester, link), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Collegati al tuo coach'), findsOneWidget);
    // Il link resta nel campo, per riprovare con «Continua».
    expect(testoDelCampo(tester), link);
    // L'invito è valido: senza Tor l'abbinamento si ferma lì (§7.5).
    expect(find.textContaining('rete Tor'), findsOneWidget);
    expect(telefono.nucleo.collegamenti.elenco(), isEmpty);

    // Sotto c'è ancora la schermata in cui era l'atleta.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Impostazioni'), findsOneWidget);
  });

  testWidgets("il link che apre l'app aspetta la schermata dei coach", (
    tester,
  ) async {
    telefono = TelefonoDiProva();
    inviti = InvitiInArrivo();
    // Il link arriva appena parte il codice Dart, prima dell'interfaccia.
    expect(await apriLink(tester, linkInvito()), isTrue);
    await tester.pumpWidget(AppAtleta(nucleo: telefono.nucleo, inviti: inviti));
    await tester.pumpAndSettle();
    expect(find.text('Collegati al tuo coach'), findsOneWidget);
    expect(find.textContaining('rete Tor'), findsOneWidget);
    expect(inviti.inAttesa, isNull);
  });

  testWidgets('il link chiude la fotocamera e prende il suo posto', (
    tester,
  ) async {
    telefono = TelefonoDiProva();
    inviti = InvitiInArrivo();
    final link = linkInvito();
    String? letto = 'nessuna risposta';
    await tester.pumpWidget(
      conTesti(
        AggiungiCoach(
          nucleo: telefono.nucleo,
          inviti: inviti,
          scansiona: (context) async => letto = await Navigator.of(context)
              .push(
                MaterialPageRoute<String>(
                  builder: (_) => const Scaffold(body: Text('Fotocamera')),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Scansiona il QR'));
    await tester.pumpAndSettle();
    expect(find.text('Fotocamera'), findsOneWidget);

    await apriLink(tester, link);
    await tester.pumpAndSettle();
    expect(find.text('Fotocamera'), findsNothing);
    expect(letto, isNull);
    expect(testoDelCampo(tester), link);
    expect(find.textContaining('rete Tor'), findsOneWidget);
  });

  testWidgets('lo stesso link toccato due volte si apre una volta', (
    tester,
  ) async {
    final tor = _TorLento();
    telefono = TelefonoDiProva(tor: tor);
    inviti = InvitiInArrivo();
    final link = linkInvito();
    await tester.pumpWidget(AppAtleta(nucleo: telefono.nucleo, inviti: inviti));
    // Durante il collegamento la barra si muove sempre: si va avanti a tempo,
    // non finché la schermata è ferma.
    Future<void> attendi() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await apriLink(tester, link);
    await attendi();
    expect(find.text('Avvio della rete Tor… 30%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tor.avvii, 1);

    await apriLink(tester, link);
    await attendi();
    expect(find.byType(AggiungiCoach), findsOneWidget);
    expect(inviti.inAttesa, isNull);

    tor.nonParte();
    await tester.pumpAndSettle();
    expect(find.textContaining('rete Tor'), findsOneWidget);
    expect(tor.avvii, 1);
  });

  testWidgets('un link di Open Coach che non è un invito lo dice', (
    tester,
  ) async {
    telefono = TelefonoDiProva();
    inviti = InvitiInArrivo();
    await tester.pumpWidget(AppAtleta(nucleo: telefono.nucleo, inviti: inviti));
    await apriLink(tester, 'opencoach://scheda?id=1');
    await tester.pumpAndSettle();
    expect(
      find.text('Questo codice non è un invito di Open Coach.'),
      findsOneWidget,
    );
  });

  testWidgets('gli altri link non si fermano qui', (tester) async {
    telefono = TelefonoDiProva();
    inviti = InvitiInArrivo();
    expect(
      await inviti.didPushRouteInformation(
        RouteInformation(uri: Uri.parse('https://esempio.it/invito')),
      ),
      isFalse,
    );
    expect(inviti.inAttesa, isNull);
    expect(
      await inviti.didPushRouteInformation(
        RouteInformation(uri: Uri.parse('OpenCoach://invito?v=1')),
      ),
      isTrue,
    );
    expect(inviti.inAttesa, 'opencoach://invito?v=1');
  });
}
