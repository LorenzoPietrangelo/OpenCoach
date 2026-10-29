import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:protocollo/protocollo.dart';

/// Da dove prendere una foto per un questionario.
enum OrigineFoto { fotocamera, galleria }

/// Scatta o sceglie una foto e la prepara per il coach; null se l'atleta
/// rinuncia. I test ne passano una finta.
typedef ScegliFoto = Future<Uint8List?> Function(OrigineFoto origine);

/// La foto scattata con la fotocamera resta nella cache dell'app, non nella
/// galleria. Prima di allegarla l'app la ricomprime in JPEG: il lato corto
/// al massimo di 1600 pixel, senza i dati EXIF, quindi senza la posizione
/// GPS né il modello del telefono, e ruotata come l'ha vista l'atleta
/// (§8.6).
Future<Uint8List?> scegliFotoDalTelefono(OrigineFoto origine) async {
  final file = await ImagePicker().pickImage(
    source: origine == OrigineFoto.fotocamera ? ImageSource.camera : ImageSource.gallery,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  for (final (lato, qualita) in [(1600, 80), (1280, 70), (1024, 60)]) {
    final jpeg = await FlutterImageCompress.compressWithFile(
      file.path,
      minWidth: lato,
      minHeight: lato,
      quality: qualita,
      format: CompressFormat.jpeg,
      keepExif: false,
      autoCorrectionAngle: true,
    );
    if (jpeg != null && jpeg.length <= Limiti.fotoMassima) return jpeg;
  }
  throw const FormatException('Foto troppo grande anche dopo la compressione');
}
