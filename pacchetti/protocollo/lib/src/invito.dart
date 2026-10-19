import 'base32.dart';
import 'chiavi.dart';
import 'onion.dart';

/// Contenuto del QR o del link d'invito (§5.2).
class UriInvito {
  const UriInvito({
    required this.indirizzo,
    required this.id,
    required this.segreto,
    required this.chiave,
  });

  static const versione = 1;

  /// Indirizzo onion del coach, senza ".onion".
  final String indirizzo;

  /// Id dell'invito: 16 byte in base32.
  final String id;

  /// Segreto d'invito: 32 byte in base32.
  final String segreto;

  /// Chiave privata X25519 d'invito: 32 byte in base32.
  final String chiave;

  @override
  String toString() =>
      'opencoach://invito?v=$versione&o=$indirizzo&i=$id&s=$segreto&k=$chiave';

  /// Legge un invito dal testo del QR o del link.
  ///
  /// Lancia [VersioneInvitoSconosciuta] se l'invito richiede un'app più
  /// recente, [InvitoNonValido] in tutti gli altri casi.
  static UriInvito analizza(String testo) {
    final uri = Uri.tryParse(testo.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'opencoach' ||
        uri.host.toLowerCase() != 'invito') {
      throw const InvitoNonValido();
    }
    final parametri = uri.queryParameters;
    final versioneInvito = int.tryParse(parametri['v'] ?? '');
    if (versioneInvito == null) throw const InvitoNonValido();
    if (versioneInvito != versione) throw const VersioneInvitoSconosciuta();

    final indirizzo = parametri['o']?.toLowerCase();
    final id = parametri['i']?.toLowerCase();
    final segreto = parametri['s']?.toLowerCase();
    final chiave = parametri['k']?.toLowerCase();
    if (indirizzo == null ||
        indirizzo.length != 56 ||
        !indirizzoOnionValido(indirizzo) ||
        id == null ||
        !idInvitoValido(id) ||
        segreto == null ||
        decodificaChiave32(segreto) == null ||
        chiave == null ||
        decodificaChiave32(chiave) == null) {
      throw const InvitoNonValido();
    }
    return UriInvito(
      indirizzo: indirizzo,
      id: id,
      segreto: segreto,
      chiave: chiave,
    );
  }
}

/// Vero se [id] è un id d'invito: 16 byte in base32 (26 caratteri).
bool idInvitoValido(String id) =>
    id.length == 26 && decodificaBase32(id)?.length == 16;

sealed class ErroreInvito implements Exception {
  const ErroreInvito();
}

/// Il testo non è un invito di Open Coach.
class InvitoNonValido extends ErroreInvito {
  const InvitoNonValido();

  @override
  String toString() => 'InvitoNonValido';
}

/// L'invito usa una versione del formato che questa app non conosce.
class VersioneInvitoSconosciuta extends ErroreInvito {
  const VersioneInvitoSconosciuta();

  @override
  String toString() => 'VersioneInvitoSconosciuta';
}
