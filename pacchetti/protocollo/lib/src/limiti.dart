/// Versioni maggiori del protocollo supportate (§6.2).
const versioniProtocollo = [1];

/// Limiti del protocollo (§6.2).
abstract final class Limiti {
  static const corpoMassimo = 2 * 1024 * 1024;
  static const logMassimo = 64 * 1024;
  static const schedaMassima = 256 * 1024;
  static const logPerRichiesta = 100;
  static const pesiPerRichiesta = 500;
  static const rispostePerRichiesta = 20;

  /// Una foto di un questionario, già compressa dall'app (§8.6).
  static const fotoMassima = 1536 * 1024;
  static const richiesteAlMinutoPerDispositivo = 30;

  /// Il telefono del coach apre più pagine e scarica le foto una per una
  /// (§16.3).
  static const richiesteAlMinutoPerTelefonoCoach = 120;
  static const abbinamentiAlMinuto = 10;
  static const syncContemporanee = 10;

  /// Attesa massima di `POST /v1/attendi`, in secondi (§6.3).
  static const attesaNovitaS = 25;

  /// Chiavi autorizzate contemporaneamente: dispositivi attivi più inviti
  /// aperti (§9.2, §12).
  static const chiaviAutorizzate = 200;
}
