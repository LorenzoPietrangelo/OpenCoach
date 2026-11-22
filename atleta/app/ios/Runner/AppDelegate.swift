import AVFoundation
import AudioToolbox
import Flutter
import Tor
import UIKit

/// L'app su iOS. Oltre ai plugin, il codice Dart chiede qui tre cose che
/// Flutter non fa da solo, con gli stessi canali dell'app Android: Tor
/// (`org.opencoach.atleta/tor`), la compressione dei video delle serie
/// (`/video`) e il segnale di fine recupero (`/suono`). I link d'invito li
/// passa Flutter (FlutterDeepLinkingEnabled nell'Info.plist).
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let messaggi = engineBridge.pluginRegistry.registrar(forPlugin: "OpenCoach")?.messenger() else {
      return
    }
    FlutterMethodChannel(name: "org.opencoach.atleta/tor", binaryMessenger: messaggi)
      .setMethodCallHandler { chiamata, risultato in
        switch chiamata.method {
        case "avvia": TorIncorporato.avvia(risultato)
        default: risultato(FlutterMethodNotImplemented)
        }
      }
    FlutterMethodChannel(name: "org.opencoach.atleta/video", binaryMessenger: messaggi)
      .setMethodCallHandler { chiamata, risultato in
        switch chiamata.method {
        case "comprimi":
          CompressioneVideo.comprimi(chiamata.arguments as? [String: Any] ?? [:], risultato)
        default: risultato(FlutterMethodNotImplemented)
        }
      }
    FlutterMethodChannel(name: "org.opencoach.atleta/suono", binaryMessenger: messaggi)
      .setMethodCallHandler { chiamata, risultato in
        switch chiamata.method {
        case "suona":
          // Il suono d'avviso del sistema, che fa anche vibrare. Con il
          // telefono in silenzioso resta la vibrazione.
          AudioServicesPlayAlertSound(SystemSoundID(1005))
          risultato(nil)
        default: risultato(FlutterMethodNotImplemented)
        }
      }
  }
}

/// Tor dentro l'app con Tor.framework (§10.1). Parte una volta per processo,
/// senza rete: il trasporto del nucleo gliela dà e gliela toglie
/// (`DisableNetwork`) e apre il proxy SOCKS dopo il bootstrap.
///
/// La porta di controllo è sul loopback con l'autenticazione a cookie: Dart
/// su iOS non garantisce i socket Unix che usa l'app Android. Il cookie è
/// nella cartella privata dell'app, quindi solo l'app può comandare tor.
enum TorIncorporato {
  private static let coda = DispatchQueue(label: "org.opencoach.atleta.tor")
  private static var thread: TorThread?
  private static var configurazione: TorConfiguration?

  static func avvia(_ risultato: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let accesso = try avviaEAttendi()
        DispatchQueue.main.async { risultato(accesso) }
      } catch {
        DispatchQueue.main.async {
          risultato(FlutterError(code: "tor", message: "\(error)", details: nil))
        }
      }
    }
  }

  private enum Errore: Error {
    case portaDiControlloMancante
  }

  private static func avviaEAttendi() throws -> [String: Any] {
    let configurazione = try coda.sync { () throws -> TorConfiguration in
      if let esistente = self.configurazione { return esistente }
      let nuova = try configura()
      // Il file della sessione precedente: tor lo riscrive quando è pronto.
      if let file = nuova.controlPortFile { try? FileManager.default.removeItem(at: file) }
      let avviato = TorThread(configuration: nuova)
      avviato.start()
      thread = avviato
      self.configurazione = nuova
      return nuova
    }
    // Tor scrive la porta e il cookie qualche istante dopo l'avvio.
    let scadenza = Date().addingTimeInterval(30)
    while Date() < scadenza {
      if let file = configurazione.controlPortFile,
        let testo = try? String(contentsOf: file, encoding: .utf8),
        let porta = portaDa(testo),
        let cookie = configurazione.cookie, cookie.count == 32
      {
        return ["porta": porta, "cookie": FlutterStandardTypedData(bytes: cookie)]
      }
      Thread.sleep(forTimeInterval: 0.1)
    }
    throw Errore.portaDiControlloMancante
  }

  private static func configura() throws -> TorConfiguration {
    let gestore = FileManager.default
    var cartella = try gestore.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    ).appendingPathComponent("tor", isDirectory: true)
    try gestore.createDirectory(
      at: cartella, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    // Come su Android, i dati di Tor restano fuori dai backup.
    var valori = URLResourceValues()
    valori.isExcludedFromBackup = true
    try cartella.setResourceValues(valori)

    let configurazione = TorConfiguration()
    configurazione.ignoreMissingTorrc = true
    configurazione.cookieAuthentication = true
    configurazione.autoControlPort = true
    configurazione.avoidDiskWrites = true
    configurazione.clientOnly = true
    configurazione.dataDirectory = cartella
    configurazione.options = NSMutableDictionary(dictionary: [
      // Il proxy SOCKS lo apre il trasporto dopo il bootstrap.
      "SocksPort": "0",
      "DisableNetwork": "1",
      "Log": "notice stdout",
    ])
    return configurazione
  }

  /// La riga di ControlPortWriteToFile, come «PORT=127.0.0.1:9151».
  private static func portaDa(_ testo: String) -> Int? {
    for riga in testo.split(whereSeparator: \.isNewline) where riga.hasPrefix("PORT=") {
      if let duePunti = riga.lastIndex(of: ":"),
        let porta = Int(riga[riga.index(after: duePunti)...])
      {
        return porta
      }
    }
    return nil
  }
}

/// Il video di una serie pronto per il coach (§8.7), come `CompressioneVideo`
/// su Android: solo la traccia video, al massimo 640×480, in MP4, senza
/// audio e senza i metadati di posizione.
enum CompressioneVideo {
  private enum Errore: Error {
    case troppoLungo
    case fallita(String)
  }

  static func comprimi(_ argomenti: [String: Any], _ risultato: @escaping FlutterResult) {
    guard let sorgente = argomenti["sorgente"] as? String,
      let destinazione = argomenti["destinazione"] as? String,
      let massimoS = argomenti["massimo_s"] as? Int
    else {
      risultato(FlutterError(code: "argomenti", message: "Argomenti mancanti", details: nil))
      return
    }
    Task {
      let esito: Any
      do {
        let durataMs = try await esporta(
          da: URL(fileURLWithPath: sorgente), a: URL(fileURLWithPath: destinazione),
          massimoS: massimoS)
        esito = ["durata_ms": durataMs]
      } catch Errore.troppoLungo {
        // Lo stesso codice dell'app Android: Dart lo mostra all'atleta.
        esito = FlutterError(code: "troppo_lungo", message: nil, details: nil)
      } catch {
        esito = FlutterError(code: "compressione", message: "\(error)", details: nil)
      }
      await MainActor.run { risultato(esito) }
    }
  }

  private static func esporta(da sorgente: URL, a destinazione: URL, massimoS: Int) async throws
    -> Int
  {
    let asset = AVURLAsset(url: sorgente)
    let durata = try await asset.load(.duration)
    // Mezzo secondo di tolleranza sul massimo.
    if durata.seconds > Double(massimoS) + 0.5 { throw Errore.troppoLungo }
    guard let traccia = try await asset.loadTracks(withMediaType: .video).first else {
      throw Errore.fallita("Il file non ha video")
    }
    let composizione = AVMutableComposition()
    guard
      let video = composizione.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw Errore.fallita("Traccia non creata") }
    try video.insertTimeRange(CMTimeRange(start: .zero, duration: durata), of: traccia, at: .zero)
    video.preferredTransform = try await traccia.load(.preferredTransform)

    guard
      let esportazione = AVAssetExportSession(
        asset: composizione, presetName: AVAssetExportPreset640x480)
    else { throw Errore.fallita("Esportazione non disponibile") }
    try? FileManager.default.removeItem(at: destinazione)
    esportazione.outputURL = destinazione
    esportazione.outputFileType = .mp4
    esportazione.shouldOptimizeForNetworkUse = true
    esportazione.metadataItemFilter = .forSharing()
    await esportazione.export()
    guard esportazione.status == .completed else {
      throw Errore.fallita(esportazione.error?.localizedDescription ?? "Esportazione non riuscita")
    }
    return Int((durata.seconds * 1000).rounded())
  }
}
