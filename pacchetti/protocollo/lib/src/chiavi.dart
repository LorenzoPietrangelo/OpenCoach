import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'base32.dart';
import 'casuale.dart';

/// Decodifica una chiave o un segreto di 32 byte scritto in base32
/// (52 caratteri, §4). Null se il testo non è valido.
Uint8List? decodificaChiave32(String testo) {
  if (testo.length != 52) return null;
  final byte = decodificaBase32(testo);
  return byte != null && byte.length == 32 ? byte : null;
}

/// Coppia di chiavi X25519 per la client authorization di Tor (§4).
class CoppiaX25519 {
  CoppiaX25519._(this.privata, this.pubblica);

  final Uint8List privata;
  final Uint8List pubblica;

  String get privataBase32 => codificaBase32(privata);
  String get pubblicaBase32 => codificaBase32(pubblica);

  static Future<CoppiaX25519> genera() => daPrivata(byteCasuali(32));

  static Future<CoppiaX25519> daPrivata(List<int> privata) async {
    if (privata.length != 32) {
      throw ArgumentError.value(privata.length, 'privata', 'servono 32 byte');
    }
    final coppia = await X25519().newKeyPairFromSeed(privata);
    final pubblica = await coppia.extractPublicKey();
    return CoppiaX25519._(
      Uint8List.fromList(privata),
      Uint8List.fromList(pubblica.bytes),
    );
  }
}
