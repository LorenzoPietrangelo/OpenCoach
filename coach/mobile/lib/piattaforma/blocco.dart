import 'package:local_auth/local_auth.dart';

/// Il riconoscimento del coach prima di mostrare i dati (§16.4).
abstract interface class BloccoApp {
  /// Vero se il telefono ha un'impronta o un blocco schermo da chiedere.
  Future<bool> disponibile();

  /// Chiede il riconoscimento; vero se è andato bene.
  Future<bool> chiedi(String motivo);
}

/// Con l'impronta o, se il coach preferisce, il blocco schermo del telefono.
class BloccoDiSistema implements BloccoApp {
  BloccoDiSistema([LocalAuthentication? autenticazione]) : _autenticazione = autenticazione ?? LocalAuthentication();

  final LocalAuthentication _autenticazione;

  @override
  Future<bool> disponibile() => _autenticazione.isDeviceSupported();

  @override
  Future<bool> chiedi(String motivo) async {
    try {
      return await _autenticazione.authenticate(localizedReason: motivo, persistAcrossBackgrounding: true);
    } on LocalAuthException {
      // Annullato, troppi tentativi o niente da chiedere: l'app resta chiusa e
      // il pulsante riprova.
      return false;
    }
  }
}
