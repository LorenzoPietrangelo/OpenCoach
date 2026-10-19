import 'dart:io';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:protocollo/protocollo.dart';

import 'app.dart';
import 'piattaforma/cassaforte_sicura.dart';
import 'piattaforma/tor_non_integrato.dart';

/// Versione inviata al coach (§6.3): la stessa del pubspec.
const versioneApp = '1.0.0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Spazio privato dell'app (§8.4). Su iOS la classe di protezione
  // predefinita è già CompleteUntilFirstUserAuthentication.
  final cartella = await getApplicationSupportDirectory();
  final nucleo = NucleoAtleta(
    archivio: ArchivioAtleta.apri(
      '${cartella.path}${Platform.pathSeparator}atleta.db',
    ),
    cassaforte: CassaforteSicura(),
    tor: const TorNonIntegrato(),
    dispositivo: DatiDispositivo(
      nome: Platform.isIOS ? 'iPhone' : 'Telefono Android',
      piattaforma: Platform.isIOS ? 'ios' : 'android',
      versioneApp: versioneApp,
    ),
  );
  runApp(AppAtleta(nucleo: nucleo));
}
