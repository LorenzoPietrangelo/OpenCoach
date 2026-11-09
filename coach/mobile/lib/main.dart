import 'package:flutter/material.dart';
import 'package:protocollo/protocollo.dart';
import 'package:trasporto_tor/trasporto_tor.dart';

import 'app.dart';
import 'dati/collegamento.dart';
import 'dati/stato_coach.dart';
import 'l10n/testi.dart';
import 'piattaforma/avviatore_android.dart';
import 'piattaforma/background.dart';
import 'piattaforma/blocco.dart';
import 'piattaforma/cassaforte_sicura.dart';
import 'piattaforma/qr_di_prova.dart';

/// Versione inviata al programma del coach: la stessa del pubspec.
const versioneApp = '1.6.1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Prima di ogni await: il link che apre l'app arriva subito.
  final qr = QrDiProva();
  final stato = await _creaStato();
  final background = ControlliInBackground(stato, testi: lookupTesti(const Locale('it')));
  await background.collega();
  runApp(AppCoachMobile(stato: stato, blocco: BloccoDiSistema(), background: background, qrDiProva: qr));
}

/// Avvio senza interfaccia, per un controllo in background con l'app chiusa: lo
/// chiede il lavoro di WorkManager (MotoreFlutter). Se poi il coach apre l'app,
/// l'interfaccia usa questo stesso stato.
@pragma('vm:entry-point')
Future<void> avvioInBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  final qr = QrDiProva();
  final stato = await _creaStato();
  var mostrata = false;
  late final ControlliInBackground background;
  void mostra() {
    if (mostrata) return;
    mostrata = true;
    runApp(AppCoachMobile(stato: stato, blocco: BloccoDiSistema(), background: background, qrDiProva: qr));
  }

  background = ControlliInBackground(stato, testi: lookupTesti(const Locale('it')), mostraInterfaccia: mostra);
  if (await background.collega()) mostra();
}

Future<StatoCoach> _creaStato() async {
  const cassaforte = CassaforteSicura();
  final tor = TrasportoTorControllato(const AvviatoreTorAndroid(), registra: debugPrint);
  final stato = StatoCoach(
    cassaforte: cassaforte,
    collegamento: ServizioCollegamento(
      cassaforte: cassaforte,
      tor: tor,
      dispositivo: const DatiDispositivo(nome: 'Telefono Android', piattaforma: 'android', versioneApp: versioneApp),
    ),
    registra: debugPrint,
  );
  await stato.carica();
  return stato;
}
