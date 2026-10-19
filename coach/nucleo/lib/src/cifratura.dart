import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:protocollo/protocollo.dart';

final _aead = Xchacha20.poly1305Aead();
const _lunghezzaNonce = 24;
const _lunghezzaMac = 16;

/// Cifra [chiaro] con XChaCha20-Poly1305. Il risultato è
/// nonce (24 byte) + testo cifrato + MAC (16 byte).
Future<Uint8List> cifra(List<int> chiave, List<int> chiaro) async {
  final nonce = byteCasuali(_lunghezzaNonce);
  final scatola = await _aead.encrypt(
    chiaro,
    secretKey: SecretKey(chiave),
    nonce: nonce,
  );
  return Uint8List.fromList([
    ...nonce,
    ...scatola.cipherText,
    ...scatola.mac.bytes,
  ]);
}

/// Inverso di [cifra]. Lancia [SecretBoxAuthenticationError] se la chiave è
/// sbagliata o i dati sono stati alterati.
Future<Uint8List> decifra(List<int> chiave, List<int> cifrato) async {
  if (cifrato.length < _lunghezzaNonce + _lunghezzaMac) {
    throw SecretBoxAuthenticationError();
  }
  final scatola = SecretBox(
    cifrato.sublist(_lunghezzaNonce, cifrato.length - _lunghezzaMac),
    nonce: cifrato.sublist(0, _lunghezzaNonce),
    mac: Mac(cifrato.sublist(cifrato.length - _lunghezzaMac)),
  );
  return Uint8List.fromList(
    await _aead.decrypt(scatola, secretKey: SecretKey(chiave)),
  );
}
