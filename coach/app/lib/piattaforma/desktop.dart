import 'dart:io';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

/// Testi che l'integrazione mostra fuori dall'interfaccia: menu dell'area di
/// notifica e titolo della finestra.
class TestiDesktop {
  const TestiDesktop({
    required this.titolo,
    required this.apri,
    required this.esci,
  });

  final String titolo;
  final String apri;
  final String esci;
}

/// Integrazione con il sistema operativo (§9.1): area di notifica, finestra
/// che si riduce invece di chiudersi, avvio con la sessione, notifiche,
/// sospensione, scelta di file. [DesktopReale] usa i plugin; i test una
/// versione finta.
abstract interface class Desktop {
  /// Prepara finestra e area di notifica. Con [nascosto] la finestra resta
  /// chiusa, come all'avvio automatico. [richiestaUscita] parte da «Esci»
  /// nel menu dell'area di notifica.
  Future<void> prepara({
    required TestiDesktop testi,
    required bool nascosto,
    required VoidCallback richiestaUscita,
  });

  Future<void> mostraFinestra();

  /// Testo dell'icona nell'area di notifica, con lo stato del servizio.
  Future<void> aggiornaStato(String descrizione);

  Future<bool> avvioAutomatico();

  Future<void> impostaAvvioAutomatico(bool attivo);

  Future<void> impedisciSospensione(bool attivo);

  Future<void> notifica(String titolo, String testo);

  Future<String?> scegliCartella();

  /// Percorso del file da creare, scelto dal coach; null se annulla.
  Future<String?> scegliDoveSalvare(String nomeSuggerito, String estensione);

  /// File da aprire, scelto dal coach; null se annulla.
  Future<String?> scegliFile(String estensione);

  /// Apre il file con il programma predefinito, per esempio un video della
  /// chat con il lettore del sistema.
  Future<void> apriFile(String percorso);

  /// Chiude finestra e icona e termina il processo.
  Future<void> esci();
}

class DesktopReale with TrayListener, WindowListener implements Desktop {
  VoidCallback? _richiestaUscita;

  @override
  Future<void> prepara({
    required TestiDesktop testi,
    required bool nascosto,
    required VoidCallback richiestaUscita,
  }) async {
    _richiestaUscita = richiestaUscita;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    // Chiudere la finestra la riduce nell'area di notifica (§9.1).
    await windowManager.setPreventClose(true);
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        title: testi.titolo,
        size: const Size(1200, 800),
        minimumSize: const Size(900, 600),
        center: true,
      ),
      () async {
        if (nascosto) return;
        await windowManager.show();
        await windowManager.focus();
      },
    );

    trayManager.addListener(this);
    // Il percorso è relativo agli asset dell'eseguibile.
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/icona.ico' : 'assets/icona.png',
    );
    await trayManager.setToolTip(testi.titolo);
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'apri', label: testi.apri),
          MenuItem.separator(),
          MenuItem(key: 'esci', label: testi.esci),
        ],
      ),
    );

    await localNotifier.setup(appName: testi.titolo);
    launchAtStartup.setup(
      appName: testi.titolo,
      appPath: Platform.resolvedExecutable,
      args: const ['--nascosto'],
    );
  }

  @override
  void onWindowClose() => windowManager.hide();

  @override
  void onTrayIconMouseDown() => mostraFinestra();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'apri':
        mostraFinestra();
      case 'esci':
        _richiestaUscita?.call();
    }
  }

  @override
  Future<void> mostraFinestra() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> aggiornaStato(String descrizione) =>
      trayManager.setToolTip(descrizione);

  @override
  Future<bool> avvioAutomatico() => launchAtStartup.isEnabled();

  @override
  Future<void> impostaAvvioAutomatico(bool attivo) async {
    if (attivo) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }

  @override
  Future<void> impedisciSospensione(bool attivo) => WakelockPlus.toggle(enable: attivo);

  @override
  Future<void> notifica(String titolo, String testo) =>
      localNotifier.notify(LocalNotification(title: titolo, body: testo));

  @override
  Future<String?> scegliCartella() => getDirectoryPath();

  @override
  Future<String?> scegliDoveSalvare(String nomeSuggerito, String estensione) async {
    final posizione = await getSaveLocation(
      suggestedName: nomeSuggerito,
      acceptedTypeGroups: [
        XTypeGroup(label: estensione, extensions: [estensione]),
      ],
    );
    return posizione?.path;
  }

  @override
  Future<String?> scegliFile(String estensione) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: estensione, extensions: [estensione]),
      ],
    );
    return file?.path;
  }

  @override
  Future<void> apriFile(String percorso) async {
    final (comando, argomenti) = Platform.isWindows
        ? ('explorer.exe', [percorso])
        : Platform.isMacOS
        ? ('open', [percorso])
        : ('xdg-open', [percorso]);
    // explorer.exe esce con 1 anche quando apre il file: conta solo se parte.
    await Process.start(comando, argomenti, mode: ProcessStartMode.detached);
  }

  @override
  Future<void> esci() async {
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }
}
