import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'errori.dart';
import 'eventi.dart';
import 'modelli.dart';
import 'tempo.dart';

/// Chat tra coach e atleta (§8.7), con i video che l'atleta allega alle
/// serie.
///
/// I messaggi stanno nell'archivio; i video, troppo grandi, in file sotto
/// [cartellaVideo], una cartella per atleta. Un video arriva a parti
/// (`PUT /v1/video/<id>/<parte>`) e si ricompone quando arriva il messaggio
/// che lo cita, se le parti corrispondono alla sua impronta. I video non
/// entrano nel backup.
class GestioneMessaggi {
  GestioneMessaggi(this._c, this.cartellaVideo);

  final ContestoCoach _c;
  final String cartellaVideo;

  Database get _db => _c.archivio.db;

  /// La conversazione con l'atleta, dal messaggio più vecchio.
  List<Messaggio> conversazione(String atletaId) => [
    for (final riga in _db.select(
      'SELECT * FROM messaggi WHERE atleta_id = ? ORDER BY ordine, id',
      [atletaId],
    ))
      _daRiga(riga),
  ];

  /// Messaggi dell'atleta che il coach non ha ancora letto.
  int nonLetti(String atletaId) =>
      _db.select(
            "SELECT COUNT(*) AS n FROM messaggi WHERE atleta_id = ? AND autore = 'atleta' AND letto = 0",
            [atletaId],
          ).first['n']
          as int;

  void segnaLetti(String atletaId) =>
      _db.execute("UPDATE messaggi SET letto = 1 WHERE atleta_id = ? AND autore = 'atleta'", [atletaId]);

  /// Manda un messaggio all'atleta: arriva alla sua sync successiva. L'[id] lo
  /// sceglie il telefono del coach, che così può ritentare senza doppioni
  /// (§16.3).
  Messaggio invia(String atletaId, String testo, {String? id}) {
    final pulito = testo.trim();
    if (pulito.isEmpty || pulito.length > LimitiChat.testo) {
      throw const OperazioneNonValida('Il messaggio deve avere da 1 a 4000 caratteri');
    }
    final idMessaggio = id ?? nuovoUuid();
    final ora = _c.adesso();
    _c.archivio.transazione(() {
      if (_db.select('SELECT 1 FROM atleti WHERE id = ?', [atletaId]).isEmpty) {
        throw const OperazioneNonValida('Atleta inesistente');
      }
      _db.execute(
        'INSERT INTO messaggi (id, atleta_id, autore, testo, inviato_il, ordine, sequenza, letto) '
        "VALUES (?, ?, 'coach', ?, ?, ?, ?, 1)",
        [idMessaggio, atletaId, pulito, formattaDataOra(ora), istante(ora), _c.archivio.prossimaSequenza()],
      );
    });
    return _daRiga(_db.select('SELECT * FROM messaggi WHERE id = ?', [idMessaggio]).first);
  }

  /// Il file del video del messaggio, se c'è ancora.
  File? fileVideo(String atletaId, Messaggio messaggio) {
    final video = messaggio.video;
    if (video == null || messaggio.videoEliminato) return null;
    final file = File(_percorsoVideo(atletaId, video['id']! as String));
    return file.existsSync() ? file : null;
  }

  /// Cancella il file del video per fare spazio; il messaggio resta.
  void eliminaVideo(String atletaId, String messaggioId) {
    final riga = _db.select('SELECT video FROM messaggi WHERE id = ? AND atleta_id = ?', [
      messaggioId,
      atletaId,
    ]).firstOrNull;
    final video = riga?['video'];
    if (video is! String) return;
    final file = File(_percorsoVideo(atletaId, (jsonDecode(video) as Map<String, Object?>)['id']! as String));
    if (file.existsSync()) file.deleteSync();
    _db.execute('UPDATE messaggi SET video_eliminato = 1 WHERE id = ?', [messaggioId]);
  }

  /// Cancella i video dell'atleta, quando l'atleta viene eliminato.
  void eliminaVideoAtleta(String atletaId) {
    final cartella = Directory(p.join(cartellaVideo, atletaId));
    if (cartella.existsSync()) cartella.deleteSync(recursive: true);
  }

  /// `PUT /v1/video/<id>/<parte>`: salva una parte; idempotente.
  void salvaParteVideo(String atletaId, String videoId, int parte, Uint8List dati) {
    if (!uuidValido(videoId) || parte < 0 || parte >= partiVideo(LimitiChat.videoMassimo)) {
      throw const ErroreHttp(404, CodiceErrore.nonTrovato);
    }
    if (dati.isEmpty || dati.length > LimitiChat.parteVideo) {
      throw const ErroreHttp(400, CodiceErrore.richiestaNonValida, messaggio: 'Parte vuota o troppo grande');
    }
    if (File(_percorsoVideo(atletaId, videoId)).existsSync()) return;
    final cartella = Directory(p.join(cartellaVideo, atletaId))..createSync(recursive: true);
    final provvisorio = File(p.join(cartella.path, '$videoId.$parte.tmp'));
    provvisorio.writeAsBytesSync(dati, flush: true);
    provvisorio.renameSync(_percorsoParte(atletaId, videoId, parte));
  }

  /// Salva un messaggio arrivato con una sync (§7.2): idempotente, in una
  /// transazione già aperta. Un messaggio con un video si accetta solo se il
  /// video è completo e corrisponde all'impronta.
  void riceviMessaggio(
    Dispositivo dispositivo,
    Object? messaggio,
    List<String> accettati,
    List<LogRifiutato> rifiutati,
    List<EventoCoach> eventi,
  ) {
    final id = messaggio is Map<String, Object?> && messaggio['id'] is String ? messaggio['id'] as String : '';
    if (validaMessaggio(messaggio).isNotEmpty || (messaggio! as Map)['autore'] != 'atleta') {
      rifiutati.add(LogRifiutato(id, RifiutoMessaggio.nonValido));
      return;
    }
    final m = messaggio as Map<String, Object?>;
    final esistente = _db.select('SELECT atleta_id FROM messaggi WHERE id = ?', [id]).firstOrNull;
    if (esistente != null) {
      if (esistente['atleta_id'] == dispositivo.atletaId) {
        accettati.add(id);
      } else {
        rifiutati.add(LogRifiutato(id, RifiutoMessaggio.altroAtleta));
      }
      return;
    }
    final video = m['video'] as Map<String, Object?>?;
    if (video != null && !_ricomponi(dispositivo.atletaId, video)) {
      rifiutati.add(LogRifiutato(id, RifiutoMessaggio.videoMancante));
      return;
    }
    final inviato = analizzaDataOra(m['inviato_il'])!;
    _db.execute(
      'INSERT INTO messaggi (id, atleta_id, autore, testo, inviato_il, ordine, video, riferimento) '
      "VALUES (?, ?, 'atleta', ?, ?, ?, ?, ?)",
      [
        id,
        dispositivo.atletaId,
        m['testo'],
        m['inviato_il'],
        istante(inviato),
        video == null ? null : jsonEncode(video),
        m['riferimento'] == null ? null : jsonEncode(m['riferimento']),
      ],
    );
    accettati.add(id);
    eventi.add(MessaggioRicevuto(dispositivo.atletaId, id, conVideo: video != null));
  }

  /// Unisce le parti del video in un file, se ci sono tutte e l'impronta
  /// corrisponde; altrimenti le cancella, così l'app le rimanda.
  bool _ricomponi(String atletaId, Map<String, Object?> video) {
    final id = video['id']! as String;
    final finale = File(_percorsoVideo(atletaId, id));
    if (finale.existsSync()) return true;
    final parti = [for (var i = 0; i < (video['parti']! as int); i++) File(_percorsoParte(atletaId, id, i))];
    if (!parti.every((f) => f.existsSync())) return false;
    final byte = BytesBuilder(copy: false);
    for (final f in parti) {
      byte.add(f.readAsBytesSync());
    }
    final dati = byte.takeBytes();
    final valido = dati.length == video['dimensione'] && sha256.convert(dati).toString() == video['sha256'];
    if (valido) {
      final provvisorio = File('${finale.path}.tmp')..writeAsBytesSync(dati, flush: true);
      provvisorio.renameSync(finale.path);
    }
    for (final f in parti) {
      f.deleteSync();
    }
    return valido;
  }

  /// Il messaggio come lo riceve l'app.
  Map<String, Object?> perProtocollo(Row r) => {
    'id': r['id'],
    'autore': r['autore'],
    'testo': r['testo'],
    'inviato_il': r['inviato_il'],
    if (r['video'] case final String video) 'video': jsonDecode(video),
    if (r['riferimento'] case final String riferimento) 'riferimento': jsonDecode(riferimento),
  };

  String _percorsoVideo(String atletaId, String videoId) => p.join(cartellaVideo, atletaId, '$videoId.mp4');

  String _percorsoParte(String atletaId, String videoId, int parte) =>
      p.join(cartellaVideo, atletaId, '$videoId.$parte.parte');

  Messaggio _daRiga(Row r) => Messaggio(
    id: r['id'] as String,
    dalCoach: r['autore'] == 'coach',
    testo: r['testo'] as String,
    inviatoIl: analizzaDataOra(r['inviato_il'])!,
    video: switch (r['video']) {
      final String testo => jsonDecode(testo) as Map<String, Object?>,
      _ => null,
    },
    riferimento: switch (r['riferimento']) {
      final String testo => jsonDecode(testo) as Map<String, Object?>,
      _ => null,
    },
    videoEliminato: r['video_eliminato'] == 1,
    letto: r['letto'] == 1,
  );
}
