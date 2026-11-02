import 'casuale.dart';
import 'date.dart';

/// Limiti della chat e dei video (§8.7).
abstract final class LimitiChat {
  static const testo = 4000;

  /// Un video si manda a parti di questa dimensione, l'ultima più corta.
  static const parteVideo = 1024 * 1024;
  static const videoMassimo = 32 * 1024 * 1024;
  static const durataVideoS = 90;
  static const messaggiPerRichiesta = 100;
}

/// Quante parti servono per un video di [dimensione] byte.
int partiVideo(int dimensione) => (dimensione + LimitiChat.parteVideo - 1) ~/ LimitiChat.parteVideo;

final _sha256 = RegExp(r'^[0-9a-f]{64}$');

/// Problemi di un messaggio della chat (§8.7). Lista vuota se è valido.
List<String> validaMessaggio(Object? messaggio) {
  final errori = <String>[];
  void errore(String percorso, String testo) => errori.add('$percorso: $testo');
  if (messaggio is! Map<String, Object?>) return ['messaggio: deve essere un oggetto'];
  final m = messaggio;
  if (!uuidValido(m['id'])) errore('id', 'deve essere un UUID in minuscolo');
  if (m['autore'] != 'coach' && m['autore'] != 'atleta') errore('autore', 'coach o atleta');
  if (analizzaDataOra(m['inviato_il']) == null) errore('inviato_il', 'data e ora non valida');
  final testo = m['testo'];
  if (testo is! String || testo.length > LimitiChat.testo) {
    errore('testo', 'al massimo ${LimitiChat.testo} caratteri');
  }

  final video = m['video'];
  if (video != null) {
    if (video is! Map<String, Object?>) {
      errore('video', 'deve essere un oggetto');
    } else {
      if (!uuidValido(video['id'])) errore('video.id', 'deve essere un UUID in minuscolo');
      final dimensione = video['dimensione'];
      if (dimensione is! int || dimensione < 1 || dimensione > LimitiChat.videoMassimo) {
        errore('video.dimensione', 'da 1 a ${LimitiChat.videoMassimo} byte');
      } else if (video['parti'] != partiVideo(dimensione)) {
        errore('video.parti', 'deve essere ${partiVideo(dimensione)}');
      }
      final impronta = video['sha256'];
      if (impronta is! String || !_sha256.hasMatch(impronta)) {
        errore('video.sha256', 'servono 64 cifre esadecimali minuscole');
      }
      final durata = video['durata_s'];
      if (durata is! int || durata < 1 || durata > LimitiChat.durataVideoS) {
        errore('video.durata_s', 'da 1 a ${LimitiChat.durataVideoS} secondi');
      }
    }
  } else if (testo is String && testo.trim().isEmpty) {
    errore('testo', 'serve un testo o un video');
  }

  final riferimento = m['riferimento'];
  if (riferimento != null) {
    if (riferimento is! Map<String, Object?>) {
      errore('riferimento', 'deve essere un oggetto');
    } else {
      if (riferimento['log_id'] != null && !uuidValido(riferimento['log_id'])) {
        errore('riferimento.log_id', 'deve essere un UUID in minuscolo');
      }
      final esercizio = riferimento['esercizio'];
      if (esercizio is! String || esercizio.trim().isEmpty || esercizio.length > 200) {
        errore('riferimento.esercizio', 'da 1 a 200 caratteri');
      }
      final serie = riferimento['serie'];
      if (serie is! int || serie < 1 || serie > 100) errore('riferimento.serie', 'da 1 a 100');
    }
  }
  return errori;
}
