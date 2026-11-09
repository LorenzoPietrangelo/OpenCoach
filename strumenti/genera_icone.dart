// Genera tutte le icone di Open Coach dallo stesso logo: un cerchio verde acqua con un anello
// bianco. Programma del coach (finestra, area di notifica, installer), app dell'atleta (Android e
// iOS) e pagina dei download. L'app del coach per il telefono ha i colori invertiti e un punto al
// centro, per non confonderla con l'app dell'atleta sullo stesso telefono. Senza dipendenze, per
// non portare strumenti grafici nel progetto.
//
// Dalla cartella principale della repo:
//
//   dart run strumenti/genera_icone.dart
//
// Le icone vettoriali di Android (icona adattiva e icona delle notifiche) e il logo nelle pagine
// HTML disegnano lo stesso anello con le stesse proporzioni: se cambiano qui, vanno cambiate anche
// lì.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Verde acqua del logo, #00897B.
const _fondo = [0x00, 0x89, 0x7b];

/// Proporzioni rispetto al lato dell'icona: il cerchio verde, e il bordo esterno e interno
/// dell'anello bianco.
const _cerchio = 0.47;
const _anelloFuori = 0.30;
const _anelloDentro = 0.19;

/// Raggio del punto al centro dell'icona dell'app del coach.
const _punto = 0.08;

void main() {
  final repo = File.fromUri(Platform.script).parent.parent.path;
  String percorso(String relativo) => '$repo/$relativo';

  // Programma del coach.
  _scrivi(percorso('coach/app/assets/icona.png'), _png(32));
  _scrivi(percorso('coach/app/assets/icona.ico'), _ico([16, 32, 48]));
  _scrivi(percorso('coach/app/windows/runner/resources/app_icon.ico'), _ico([16, 32, 48, 256]));

  // App dell'atleta su Android: l'icona classica per ogni densità. Da Android 8 vale l'icona
  // adattiva in mipmap-anydpi-v26, disegnata come vettore.
  const densita = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
  densita.forEach((nome, lato) {
    _scrivi(
      percorso('atleta/app/android/app/src/main/res/mipmap-$nome/ic_launcher.png'),
      _png(lato),
    );
  });

  // App del coach su Android: bianca, con anello e punto verde acqua.
  densita.forEach((nome, lato) {
    _scrivi(
      percorso('coach/mobile/android/app/src/main/res/mipmap-$nome/ic_launcher.png'),
      _png(lato, coach: true),
    );
  });

  // App dell'atleta su iOS: piena, senza trasparenza, perché la forma la ritaglia il sistema.
  final cartellaIos = percorso('atleta/app/ios/Runner/Assets.xcassets/AppIcon.appiconset');
  final elenco = jsonDecode(File('$cartellaIos/Contents.json').readAsStringSync()) as Map;
  final fatte = <String>{};
  for (final voce in (elenco['images'] as List).cast<Map>()) {
    final nome = voce['filename'] as String?;
    if (nome == null || !fatte.add(nome)) continue;
    final punti = double.parse((voce['size'] as String).split('x').first);
    final scala = int.parse((voce['scale'] as String).replaceAll('x', ''));
    _scrivi('$cartellaIos/$nome', _png((punti * scala).round(), pieno: true));
  }

  // Pagina dei download.
  _scrivi(percorso('strumenti/download/favicon.png'), _png(64));
  _scrivi(percorso('strumenti/download/apple-touch-icon.png'), _png(180, pieno: true));

  stdout.writeln('Icone scritte.');
}

void _scrivi(String percorso, List<int> byte) => File(percorso).writeAsBytesSync(byte);

/// Pixel RGBA di un'icona di lato [lato], con antialiasing 4×4. Con [pieno] il verde riempie tutto
/// il quadrato e l'anello si allarga in proporzione, come se il cerchio fosse grande quanto il lato.
/// Con [coach] il cerchio è bianco e anello e punto al centro verde acqua.
Uint8List _disegna(int lato, {bool pieno = false, bool coach = false}) {
  final pixel = Uint8List(lato * lato * 4);
  final centro = lato / 2;
  final esterno = lato * _cerchio;
  final ingrandimento = pieno ? 0.5 / _cerchio : 1.0;
  final anelloFuori = lato * _anelloFuori * ingrandimento;
  final anelloDentro = lato * _anelloDentro * ingrandimento;
  final punto = coach ? lato * _punto * ingrandimento : 0.0;
  const bianco = [0xff, 0xff, 0xff];
  final fondo = coach ? bianco : _fondo;
  final segno = coach ? _fondo : bianco;
  for (var y = 0; y < lato; y++) {
    for (var x = 0; x < lato; x++) {
      var coperto = 0;
      var segnati = 0;
      for (var sy = 0; sy < 4; sy++) {
        for (var sx = 0; sx < 4; sx++) {
          final dx = x + (sx + 0.5) / 4 - centro;
          final dy = y + (sy + 0.5) / 4 - centro;
          final d2 = dx * dx + dy * dy;
          if (pieno || d2 <= esterno * esterno) {
            coperto++;
            if ((d2 <= anelloFuori * anelloFuori && d2 >= anelloDentro * anelloDentro) ||
                d2 <= punto * punto) {
              segnati++;
            }
          }
        }
      }
      final i = (y * lato + x) * 4;
      if (coperto == 0) continue;
      final quota = segnati / coperto;
      for (var c = 0; c < 3; c++) {
        pixel[i + c] = (fondo[c] + (segno[c] - fondo[c]) * quota).round();
      }
      pixel[i + 3] = (255 * coperto / 16).round();
    }
  }
  return pixel;
}

Uint8List _png(int lato, {bool pieno = false, bool coach = false}) {
  final rgba = _disegna(lato, pieno: pieno, coach: coach);
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
