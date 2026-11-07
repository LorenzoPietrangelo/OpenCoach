import 'chiavi.dart';
import 'invito.dart';
import 'onion.dart';

// Il telefono del coach (§16): il QR, l'abbinamento e le pagine di dati. I dati
// degli atleti restano JSON con la forma del §16.3: li interpreta l'app.

/// Contenuto del QR per collegare il telefono del coach (§16.2).
class UriTelefonoCoach {
  const UriTelefonoCoach({
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

  /// Segreto dell'invito: 32 byte in base32.
  final String segreto;

  /// Chiave privata X25519 dell'invito: 32 byte in base32.
  final String chiave;

  @override
  String toString() =>
      'opencoach://telefono?v=$versione&o=$indirizzo&i=$id&s=$segreto&k=$chiave';

  /// Legge il testo del QR.
  ///
  /// Lancia [VersioneInvitoSconosciuta] se il QR richiede un'app più recente,
  /// [InvitoNonValido] in tutti gli altri casi, compreso l'invito di un atleta.
  static UriTelefonoCoach analizza(String testo) {
    final uri = Uri.tryParse(testo.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'opencoach' ||
        uri.host.toLowerCase() != 'telefono') {
      throw const InvitoNonValido();
    }
    final parametri = uri.queryParameters;
    final versioneQr = int.tryParse(parametri['v'] ?? '');
    if (versioneQr == null) throw const InvitoNonValido();
    if (versioneQr != versione) throw const VersioneInvitoSconosciuta();

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
    return UriTelefonoCoach(
      indirizzo: indirizzo,
      id: id,
      segreto: segreto,
      chiave: chiave,
    );
  }
}

/// Risposta di `POST /v1/coach/abbinamento`.
class RispostaAbbinamentoTelefono {
  const RispostaAbbinamentoTelefono({
    required this.telefonoId,
    required this.token,
    required this.nomeCoach,
  });

  factory RispostaAbbinamentoTelefono.fromJson(Object? json) {
    if (json case {
      'telefono_id': final String telefonoId,
      'token': final String token,
      'nome_coach': final String nomeCoach,
    } when decodificaChiave32(token) != null) {
      return RispostaAbbinamentoTelefono(
        telefonoId: telefonoId,
        token: token,
        nomeCoach: nomeCoach,
      );
    }
    throw const FormatException('Risposta di abbinamento non valida');
  }

  final String telefonoId;
  final String token;
  final String nomeCoach;

  Map<String, Object?> toJson() => {
    'telefono_id': telefonoId,
    'token': token,
    'nome_coach': nomeCoach,
  };
}

/// Una pagina di messaggi, allenamenti o questionari (§16.3).
class PaginaDatiCoach {
  const PaginaDatiCoach(this.elementi, {required this.altri});

  /// Gli elementi nell'ordine della risposta.
  final List<Map<String, Object?>> elementi;

  /// Ce ne sono altri più vecchi di questi.
  final bool altri;
}
