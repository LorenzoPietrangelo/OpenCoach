import 'dart:math';
import 'dart:typed_data';

final _generatore = Random.secure();

/// [quanti] byte da un generatore crittograficamente sicuro.
Uint8List byteCasuali(int quanti) {
  final byte = Uint8List(quanti);
  for (var i = 0; i < quanti; i++) {
    byte[i] = _generatore.nextInt(256);
  }
  return byte;
}

/// Nuovo UUID v4 in minuscolo (§6.2).
String nuovoUuid() {
  final byte = byteCasuali(16);
  byte[6] = (byte[6] & 0x0f) | 0x40;
  byte[8] = (byte[8] & 0x3f) | 0x80;
  final esadecimale = byte
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${esadecimale.substring(0, 8)}-${esadecimale.substring(8, 12)}-'
      '${esadecimale.substring(12, 16)}-${esadecimale.substring(16, 20)}-'
      '${esadecimale.substring(20)}';
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Vero se [valore] è un UUID in minuscolo.
bool uuidValido(Object? valore) => valore is String && _uuid.hasMatch(valore);

/// Confronta due sequenze di byte in un tempo che non dipende dal contenuto.
bool ugualiInTempoCostante(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var differenza = 0;
  for (var i = 0; i < a.length; i++) {
    differenza |= a[i] ^ b[i];
  }
  return differenza == 0;
}
