// Genera le icone del programma: un cerchio verde acqua con un anello
// bianco. Senza dipendenze, per non portare strumenti grafici nel progetto.
//
//   dart run tool/genera_icone.dart
import 'dart:io';
import 'dart:typed_data';

void main() {
  File('assets/icona.png').writeAsBytesSync(_png(32));
  File('assets/icona.ico').writeAsBytesSync(_ico([16, 32, 48]));
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(_ico([16, 32, 48, 256]));
  stdout.writeln('Icone scritte.');
}

/// Pixel RGBA di un'icona di lato [lato], con antialiasing 4×4.
Uint8List _disegna(int lato) {
  const fondo = [0x00, 0x89, 0x7b];
  final pixel = Uint8List(lato * lato * 4);
  final centro = lato / 2;
  final esterno = lato * 0.47;
  final anelloFuori = lato * 0.30;
  final anelloDentro = lato * 0.19;
  for (var y = 0; y < lato; y++) {
    for (var x = 0; x < lato; x++) {
      var coperto = 0;
      var bianco = 0;
      for (var sy = 0; sy < 4; sy++) {
        for (var sx = 0; sx < 4; sx++) {
          final dx = x + (sx + 0.5) / 4 - centro;
          final dy = y + (sy + 0.5) / 4 - centro;
          final d2 = dx * dx + dy * dy;
          if (d2 <= esterno * esterno) {
            coperto++;
            if (d2 <= anelloFuori * anelloFuori && d2 >= anelloDentro * anelloDentro) bianco++;
          }
        }
      }
      final i = (y * lato + x) * 4;
      if (coperto == 0) continue;
      final quotaBianca = bianco / coperto;
      for (var c = 0; c < 3; c++) {
        pixel[i + c] = (fondo[c] + (255 - fondo[c]) * quotaBianca).round();
      }
      pixel[i + 3] = (255 * coperto / 16).round();
    }
  }
  return pixel;
}

Uint8List _png(int lato) {
  final rgba = _disegna(lato);
  final righe = BytesBuilder();
  for (var y = 0; y < lato; y++) {
    righe
      ..addByte(0)
      ..add(rgba.sublist(y * lato * 4, (y + 1) * lato * 4));
  }
  final intestazione = ByteData(13)
    ..setUint32(0, lato)
    ..setUint32(4, lato)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  return (BytesBuilder()
        ..add([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        ..add(_blocco('IHDR', intestazione.buffer.asUint8List()))
        ..add(_blocco('IDAT', ZLibCodec().encode(righe.takeBytes())))
        ..add(_blocco('IEND', const [])))
      .takeBytes();
}

Uint8List _blocco(String tipo, List<int> dati) {
  final corpo = [...tipo.codeUnits, ...dati];
  final lunghezza = ByteData(4)..setUint32(0, dati.length);
  final crc = ByteData(4)..setUint32(0, _crc32(corpo));
  return (BytesBuilder()
        ..add(lunghezza.buffer.asUint8List())
        ..add(corpo)
        ..add(crc.buffer.asUint8List()))
      .takeBytes();
}

int _crc32(List<int> dati) {
  var crc = 0xffffffff;
  for (final byte in dati) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}

/// File ICO con un'immagine PNG per ogni lato, come accetta Windows Vista
/// e successivi.
Uint8List _ico(List<int> lati) {
  final immagini = [for (final lato in lati) _png(lato)];
  final testa = ByteData(6 + 16 * lati.length)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, lati.length, Endian.little);
  var posizione = testa.lengthInBytes;
  for (var i = 0; i < lati.length; i++) {
    final voce = 6 + 16 * i;
    testa
      ..setUint8(voce, lati[i] >= 256 ? 0 : lati[i])
      ..setUint8(voce + 1, lati[i] >= 256 ? 0 : lati[i])
      ..setUint16(voce + 4, 1, Endian.little)
      ..setUint16(voce + 6, 32, Endian.little)
      ..setUint32(voce + 8, immagini[i].length, Endian.little)
      ..setUint32(voce + 12, posizione, Endian.little);
    posizione += immagini[i].length;
  }
  final file = BytesBuilder()..add(testa.buffer.asUint8List());
  immagini.forEach(file.add);
  return file.takeBytes();
}
