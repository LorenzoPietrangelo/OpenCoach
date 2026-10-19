/// Versioni maggiori del protocollo supportate (§6.2).
const versioniProtocollo = [1];

/// Limiti del protocollo (§6.2).
abstract final class Limiti {
  static const corpoMassimo = 2 * 1024 * 1024;
  static const logMassimo = 64 * 1024;
  static const schedaMassima = 256 * 1024;
  static const logPerRichiesta = 100;
  static const richiesteAlMinutoPerDispositivo = 30;
  static const abbinamentiAlMinuto = 10;
  static const syncContemporanee = 10;

  /// Chiavi autorizzate contemporaneamente: dispositivi attivi più inviti
  /// aperti (§9.2, §12).
  static const chiaviAutorizzate = 200;
}
