import 'dart:io';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:protocollo/protocollo.dart';

import 'app.dart';
import 'piattaforma/avviatore_android.dart';
import 'piattaforma/cassaforte_sicura.dart';
import 'piattaforma/inviti_in_arrivo.dart';
import 'piattaforma/sync_in_background.dart';
import 'piattaforma/tor_non_integrato.dart';

/// Versione inviata al coach (§6.3): la stessa del pubspec.
const versioneApp = '1.2.0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Prima di ogni await: il link che apre l'app arriva subito.
  final inviti = InvitiInArrivo();
  final nucleo = await creaNucleo();
  // Su iOS la sync in background (BGAppRefreshTask) non è ancora integrata.
  final background = Platform.isAndroid ? SyncInBackground(nucleo) : null;
  await background?.collega();
  runApp(AppAtleta(nucleo: nucleo, background: background, inviti: inviti));
}

/// Avvio senza interfaccia, per una sync in background con l'app chiusa: lo
/// chiede il lavoro di WorkManager (MotoreFlutter nel codice Kotlin). Se poi
/// l'atleta apre l'app, l'interfaccia usa questo stesso nucleo.
@pragma('vm:entry-point')
Future<void> avvioInBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Se l'app si apre con un link, il link arriva a questo motore.
  final inviti = InvitiInArrivo();
  final nucleo = await creaNucleo();
  var mostrata = false;
  late final SyncInBackground background;
  void mostra() {
    if (mostrata) return;
    mostrata = true;
    runApp(AppAtleta(nucleo: nucleo, background: background, inviti: inviti));
  }

  background = SyncInBackground(nucleo, mostraInterfaccia: mostra);
  if (await background.collega()) mostra();
}

/// Il nucleo dell'atleta con l'archivio, la cassaforte e Tor del telefono.
Future<NucleoAtleta> creaNucleo() async {
  // Spazio privato dell'app (§8.4). Su iOS la classe di protezione
  // predefinita è già CompleteUntilFirstUserAuthentication.
  final cartella = await getApplicationSupportDirectory();
  return NucleoAtleta(
    archivio: ArchivioAtleta.apri(
      '${cartella.path}${Platform.pathSeparator}atleta.db',
    ),
    cassaforte: CassaforteSicura(),
    // Su iOS Tor.framework non è ancora integrato.
    tor: Platform.isAndroid
        ? TrasportoTorControllato(
            const AvviatoreTorAndroid(),
            registra: debugPrint,
          )
        : const TorNonIntegrato(),
    registra: debugPrint,
    dispositivo: DatiDispositivo(
      nome: Platform.isIOS ? 'iPhone' : 'Telefono Android',
      piattaforma: Platform.isIOS ? 'ios' : 'android',
      versioneApp: versioneApp,
    ),
  );
}
