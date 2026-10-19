import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha3.dart';

import 'base32.dart';

const _versioneOnion = 3;

/// Indirizzo onion v3 (56 caratteri, senza ".onion") della chiave pubblica
/// Ed25519 [chiavePubblica], secondo rend-spec-v3.
String indirizzoOnionDaChiave(List<int> chiavePubblica) {
  if (chiavePubblica.length != 32) {
    throw ArgumentError.value(
      chiavePubblica.length,
      'chiavePubblica',
      'servono 32 byte',
    );
  }
  final checksum = _checksum(chiavePubblica);
  return codificaBase32([
    ...chiavePubblica,
    checksum[0],
    checksum[1],
    _versioneOnion,
  ]);
}

/// Chiave pubblica Ed25519 contenuta nell'indirizzo onion v3 [indirizzo],
/// con o senza ".onion". Null se l'indirizzo non è valido.
Uint8List? chiaveDaIndirizzoOnion(String indirizzo) {
  var testo = indirizzo.toLowerCase();
  if (testo.endsWith('.onion')) testo = testo.substring(0, testo.length - 6);
  if (testo.length != 56) return null;
  final dati = decodificaBase32(testo);
  if (dati == null || dati.length != 35 || dati[34] != _versioneOnion) {
    return null;
  }
  final chiave = Uint8List.fromList(dati.sublist(0, 32));
  final checksum = _checksum(chiave);
  if (dati[32] != checksum[0] || dati[33] != checksum[1]) return null;
  return chiave;
}

/// Vero se [indirizzo] è un indirizzo onion v3 valido.
bool indirizzoOnionValido(String indirizzo) =>
    chiaveDaIndirizzoOnion(indirizzo) != null;

Uint8List _checksum(List<int> chiavePubblica) =>
    SHA3Digest(256).process(
      Uint8List.fromList([
        ...ascii.encode('.onion checksum'),
        ...chiavePubblica,
        _versioneOnion,
      ]),
    );
