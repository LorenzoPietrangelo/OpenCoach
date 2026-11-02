import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:protocollo/protocollo.dart';

/// Da dove prendere il video di una serie.
enum OrigineVideo { fotocamera, galleria }

/// Il video di una serie pronto da mandare: già compresso, in un file
/// temporaneo dell'app.
class VideoPreparato {
  const VideoPreparato(this.percorso, this.durataS);

  final String percorso;
  final int durataS;
}

/// Il video scelto dura più di [massimoS] secondi.
class VideoTroppoLungo implements Exception {
  const VideoTroppoLungo(this.massimoS);

  final int massimoS;
}

/// Durata massima dei video delle serie: il protocollo ne ammette 90 (§8.7),
/// l'app ne chiede al massimo 60, che bastano per una serie e restano
/// sotto gli 8 MB.
const durataMassimaVideoS = 60;

/// Registra o sceglie un video e lo prepara per il coach; null se l'atleta
/// rinuncia. I test ne passano una versione finta.
typedef PreparaVideo = Future<VideoPreparato?> Function(OrigineVideo origine);

const _canale = MethodChannel('org.opencoach.atleta/video');

/// Il video registrato resta nella cache dell'app, non nella galleria. Lo
/// comprime il codice Android (H.264, 480p, 30 fotogrammi al secondo, senza
/// audio); i metadati, compresa la posizione, li toglie il nucleo quando il
/// video si allega al messaggio.
Future<VideoPreparato?> preparaVideoDalTelefono(OrigineVideo origine) async {
  final scelto = await ImagePicker().pickVideo(
    source: origine == OrigineVideo.fotocamera ? ImageSource.camera : ImageSource.gallery,
    maxDuration: const Duration(seconds: durataMassimaVideoS),
  );
  if (scelto == null) return null;
  final cartella = await getTemporaryDirectory();
  final destinazione = '${cartella.path}/serie-${nuovoUuid()}.mp4';
  try {
    final esito = await _canale.invokeMapMethod<String, Object?>('comprimi', {
      'sorgente': scelto.path,
      'destinazione': destinazione,
      'massimo_s': durataMassimaVideoS,
    });
    final durataMs = (esito?['durata_ms'] as num?)?.toInt() ?? 0;
    return VideoPreparato(destinazione, (durataMs / 1000).ceil().clamp(1, durataMassimaVideoS));
  } on PlatformException catch (e) {
    if (e.code == 'troppo_lungo') throw const VideoTroppoLungo(durataMassimaVideoS);
    rethrow;
  } finally {
    // La copia che image_picker mette nella cache non serve più; i file
    // fuori dalla cartella dell'app non si toccano.
    if (scelto.path.startsWith(cartella.path)) {
      try {
        File(scelto.path).deleteSync();
      } on FileSystemException {
        // Già tolta.
      }
    }
  }
}
