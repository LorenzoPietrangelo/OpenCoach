import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'errori.dart';
import 'tempo.dart';

enum StatoMessaggio {
  /// Scritto dall'atleta, in coda per il coach.
  inInvio,

  /// Il coach l'ha ricevuto; i messaggi del coach sono sempre in questo
  /// stato.
  inviato,

  /// Il coach l'ha scartato: [MessaggioChat.rifiuto] dice perché.
  rifiutato,
}

/// Messaggio della chat con un coach (§8.7).
class MessaggioChat {
  const MessaggioChat({
    required this.coachId,
    required this.id,
    required this.dalCoach,
    required this.testo,
    required this.inviatoIl,
    required this.stato,
    required this.letto,
    this.video,
    this.riferimento,
    this.fileVideo,
    this.rifiuto,
  });

  factory MessaggioChat.daRiga(Row r) => MessaggioChat(
    coachId: r['coach_id'] as int,
    id: r['id'] as String,
    dalCoach: r['dal_coach'] == 1,
    testo: r['testo'] as String,
    inviatoIl: analizzaDataOra(r['inviato_il'])!,
    stato: switch (r['stato']) {
      'in_invio' => StatoMessaggio.inInvio,
      'rifiutato' => StatoMessaggio.rifiutato,
      _ => StatoMessaggio.inviato,
    },
    letto: r['letto'] == 1,
    video: switch (r['video']) {
      final String testo => jsonDecode(testo) as Map<String, Object?>,
      _ => null,
    },
    riferimento: switch (r['riferimento']) {
      final String testo => jsonDecode(testo) as Map<String, Object?>,
      _ => null,
    },
    fileVideo: r['file_video'] as String?,
    rifiuto: r['rifiuto'] as String?,
  );

  final int coachId;
  final String id;
  final bool dalCoach;
  final String testo;
  final DateTime inviatoIl;
  final StatoMessaggio stato;
  final bool letto;

  /// Metadati del video allegato: id, dimensione, parti, sha256, durata_s.
  final Map<String, Object?>? video;

  /// La serie a cui si riferisce il video: log_id, esercizio, serie.
  final Map<String, Object?>? riferimento;

  /// Il file del video sul telefono, se c'è ancora.
  final String? fileVideo;
  final String? rifiuto;

  int? get durataVideoS => video?['durata_s'] as int?;

  String? get esercizio => riferimento?['esercizio'] as String?;

  int? get serie => riferimento?['serie'] as int?;

  /// Il messaggio come lo riceve il coach.
  Map<String, Object?> get perProtocollo => {
    'id': id,
    'autore': dalCoach ? 'coach' : 'atleta',
    'testo': testo,
    'inviato_il': formattaDataOra(inviatoIl),
    'video': ?video,
    'riferimento': ?riferimento,
  };
}

/// Chat con i coach (§8.7). I messaggi dell'atleta partono alla sync
/// successiva; un video parte a pezzi da 1 MiB prima del suo messaggio.
///
/// I video stanno in file sotto [cartellaVideo], già compressi dall'app;
/// l'archivio tiene solo il percorso.
class ChatCoach {
  ChatCoach(this._c, this.cartellaVideo, {required void Function(int coachId) cambiato})
    : _cambiato = cambiato;

  final ContestoAtleta _c;
  final String cartellaVideo;
  final void Function(int coachId) _cambiato;

  Database get _db => _c.db;

  /// La conversazione con il coach, dal messaggio più vecchio.
  List<MessaggioChat> elenco(int coachId) => [
    for (final riga in _db.select(
      'SELECT * FROM messaggi WHERE coach_id = ? ORDER BY ordine, rowid',
      [coachId],
    ))
      MessaggioChat.daRiga(riga),
  ];

  MessaggioChat? cerca(int coachId, String id) {
    final riga = _db.select('SELECT * FROM messaggi WHERE coach_id = ? AND id = ?', [
      coachId,
      id,
    ]).firstOrNull;
    return riga == null ? null : MessaggioChat.daRiga(riga);
  }

  /// Per quanto dopo l'ultimo messaggio la conversazione conta come in corso.
  static const durataConversazione = Duration(minutes: 10);

  /// Vero se con il coach ci si è scritti da poco: con l'app chiusa conviene
  /// controllare presto se ha risposto (§7.4).
  bool conversazioneInCorso(int coachId) {
    final ultimo = _db.select(
      'SELECT inviato_il FROM messaggi WHERE coach_id = ? ORDER BY ordine DESC, rowid DESC LIMIT 1',
      [coachId],
    ).firstOrNull;
    if (ultimo == null) return false;
    final trascorso = _c.orologio.adesso().difference(analizzaDataOra(ultimo['inviato_il'])!);
    return trascorso < durataConversazione;
  }

  /// Messaggi del coach non ancora letti.
  int nonLetti(int coachId) =>
      _db.select(
            'SELECT COUNT(*) AS n FROM messaggi WHERE coach_id = ? AND dal_coach = 1 AND letto = 0',
            [coachId],
          ).first['n']
          as int;

  void segnaLetti(int coachId) {
    _db.execute('UPDATE messaggi SET letto = 1 WHERE coach_id = ? AND letto = 0', [coachId]);
    if (_db.updatedRows > 0) _c.segnala(coachId);
  }

  /// Scrive un messaggio al coach.
  MessaggioChat scrivi(int coachId, String testo) {
    final pulito = testo.trim();
    if (pulito.isEmpty || pulito.length > LimitiChat.testo) {
      throw const OperazioneNonAmmessa('Il messaggio deve avere da 1 a 4000 caratteri');
    }
    return _salva(coachId, pulito);
  }

  /// Manda al coach il video in [file], già compresso dall'app, con la serie
  /// a cui si riferisce. Il file passa nella cartella dei video: l'app non
  /// deve più usarlo.
  MessaggioChat allegaVideo(
    int coachId, {
    required String file,
    required int durataS,
    String testo = '',
    String? logId,
    String? esercizio,
    int? serie,
  }) {
    final origine = File(file);
    if (durataS < 1 || durataS > LimitiChat.durataVideoS) {
      throw const OperazioneNonAmmessa('Il video deve durare al massimo 90 secondi');
    }
    final grezzo = origine.readAsBytesSync();
    cancellaMetadatiMp4(grezzo);
    final dati = compattaMp4(grezzo);
    final dimensione = dati.length;
    if (dimensione == 0 || dimensione > LimitiChat.videoMassimo) {
      throw const OperazioneNonAmmessa('Il video deve essere di al massimo 32 MB');
    }
    final id = nuovoUuid();
    final destinazione = p.join(cartellaVideo, '$coachId', '$id.mp4');
    Directory(p.dirname(destinazione)).createSync(recursive: true);
    final provvisorio = File('$destinazione.tmp')..writeAsBytesSync(dati, flush: true);
    provvisorio.renameSync(destinazione);
    origine.deleteSync();
    final impronta = sha256.convert(dati).toString();
    try {
      return _salva(
        coachId,
        testo.trim(),
        video: {
          'id': id,
          'dimensione': dimensione,
          'parti': partiVideo(dimensione),
          'sha256': impronta,
          'durata_s': durataS,
        },
        riferimento: esercizio == null || serie == null
            ? null
            : {'log_id': ?logId, 'esercizio': esercizio, 'serie': serie},
        fileVideo: destinazione,
      );
    } catch (_) {
      File(destinazione).deleteSync();
      rethrow;
    }
  }

  /// Toglie un messaggio dell'atleta non ancora arrivato al coach, con il
  /// suo video.
  void ritira(int coachId, String id) {
    final m = cerca(coachId, id);
    if (m == null || m.dalCoach || m.stato == StatoMessaggio.inviato) {
      throw const OperazioneNonAmmessa('Il coach ha già ricevuto il messaggio');
    }
    _db.execute('DELETE FROM messaggi WHERE coach_id = ? AND id = ?', [coachId, id]);
    if (m.fileVideo case final String file when File(file).existsSync()) File(file).deleteSync();
    _c.segnala(coachId);
  }

  /// Rimette in coda un messaggio rifiutato.
  void ritenta(int coachId, String id) {
    _db.execute(
      "UPDATE messaggi SET stato = 'in_invio', rifiuto = NULL, parti_caricate = 0, ricaricamenti = 0 "
      "WHERE coach_id = ? AND id = ? AND stato = 'rifiutato'",
      [coachId, id],
    );
    if (_db.updatedRows == 0) return;
    _c.segnala(coachId);
    _cambiato(coachId);
  }

  /// Cancella i video dei coach con cui i dati sono stati cancellati.
  void eliminaVideoCoach(int coachId) {
    final cartella = Directory(p.join(cartellaVideo, '$coachId'));
    if (cartella.existsSync()) cartella.deleteSync(recursive: true);
  }

  MessaggioChat _salva(
    int coachId,
    String testo, {
    Map<String, Object?>? video,
    Map<String, Object?>? riferimento,
    String? fileVideo,
  }) {
    final id = nuovoUuid();
    final ora = _c.orologio.adesso();
    final messaggio = {
      'id': id,
      'autore': 'atleta',
      'testo': testo,
      'inviato_il': formattaDataOra(ora),
      'video': ?video,
      'riferimento': ?riferimento,
    };
    final errori = validaMessaggio(messaggio);
    if (errori.isNotEmpty) throw OperazioneNonAmmessa(errori.first);
    _c.archivio.transazione(() {
      final stato = _db.select('SELECT stato FROM coach WHERE id = ?', [coachId]).firstOrNull?['stato'];
      if (stato != 'attivo') {
        throw const OperazioneNonAmmessa('Il collegamento con questo coach è chiuso');
      }
      _db.execute(
        'INSERT INTO messaggi (coach_id, id, dal_coach, testo, inviato_il, ordine, video, riferimento, '
        "file_video, stato, letto) VALUES (?, ?, 0, ?, ?, ?, ?, ?, ?, 'in_invio', 1)",
        [
          coachId,
          id,
          testo,
          messaggio['inviato_il'],
          istante(ora),
          video == null ? null : jsonEncode(video),
          riferimento == null ? null : jsonEncode(riferimento),
          fileVideo,
        ],
      );
    });
    _c.segnala(coachId);
    _cambiato(coachId);
    return cerca(coachId, id)!;
  }
}

/// Toglie da un MP4 i metadati che possono dire dove e con che telefono è
/// stato girato il video: la posizione (`©xyz`), il modello, i dati XMP. Le
/// scatole `udta`, `meta` e `uuid`, al primo livello, in `moov` e nelle
/// tracce, diventano `free`, che i lettori saltano. Le dimensioni non
/// cambiano, quindi i riferimenti ai campioni restano validi; il contenuto
/// si azzera.
void cancellaMetadatiMp4(Uint8List dati) {
  final lettore = ByteData.sublistView(dati);
  const daTogliere = {'udta', 'meta', 'uuid'};
  void scorri(int inizio, int fine) {
    var i = inizio;
    while (i + 8 <= fine) {
      var dimensione = lettore.getUint32(i);
      var intestazione = 8;
      if (dimensione == 1) {
        if (i + 16 > fine) return;
        dimensione = lettore.getUint64(i + 8);
        intestazione = 16;
      } else if (dimensione == 0) {
        dimensione = fine - i;
      }
      if (dimensione < intestazione || dimensione > fine - i) return;
      final tipo = String.fromCharCodes(dati, i + 4, i + 8);
      if (daTogliere.contains(tipo)) {
        dati.setRange(i + 4, i + 8, 'free'.codeUnits);
        dati.fillRange(i + intestazione, i + dimensione, 0);
      } else if (tipo == 'moov' || tipo == 'trak') {
        scorri(i + intestazione, i + dimensione);
      }
      i += dimensione;
    }
  }

  scorri(0, dati.length);
}

/// Toglie dall'MP4 le scatole `free` e `skip` del primo livello: i muxer le
/// usano per riservare spazio, e attraverso Tor sono byte inutili. Dopo
/// [cancellaMetadatiMp4] ci finiscono anche i metadati tolti. Gli offset dei
/// campioni (`stco`, `co64`) si spostano di conseguenza. Un MP4 frammentato
/// (`moof`) resta com'è, perché i suoi offset non stanno solo lì.
Uint8List compattaMp4(Uint8List dati) {
  /// Le scatole di [buffer] in [inizio, fine): tipo, inizio, intestazione e
  /// dimensione.
  List<({String tipo, int inizio, int intestazione, int dimensione})> scatole(
    Uint8List buffer,
    int inizio,
    int fine,
  ) {
    final lettore = ByteData.sublistView(buffer);
    final elenco = <({String tipo, int inizio, int intestazione, int dimensione})>[];
    var i = inizio;
    while (i + 8 <= fine) {
      var dimensione = lettore.getUint32(i);
      var intestazione = 8;
      if (dimensione == 1) {
        if (i + 16 > fine) break;
        dimensione = lettore.getUint64(i + 8);
        intestazione = 16;
      } else if (dimensione == 0) {
        dimensione = fine - i;
      }
      if (dimensione < intestazione || dimensione > fine - i) break;
      elenco.add((
        tipo: String.fromCharCodes(buffer, i + 4, i + 8),
        inizio: i,
        intestazione: intestazione,
        dimensione: dimensione,
      ));
      i += dimensione;
    }
    // Una struttura che non si capisce fino in fondo non si tocca.
    return i == fine ? elenco : const [];
  }

  final primo = scatole(dati, 0, dati.length);
  if (primo.isEmpty || primo.any((s) => s.tipo == 'moof')) return dati;
  final tolte = primo.where((s) => s.tipo == 'free' || s.tipo == 'skip').toList();
  if (tolte.isEmpty) return dati;

  /// Di quanto si sposta un byte che stava in [posizione].
  int spostamento(int posizione) => [
    for (final s in tolte)
      if (s.inizio < posizione) s.dimensione,
  ].fold(0, (a, b) => a + b);

  final uscita = BytesBuilder(copy: false);
  for (final s in primo) {
    if (tolte.contains(s)) continue;
    uscita.add(Uint8List.sublistView(dati, s.inizio, s.inizio + s.dimensione));
  }
  final compatto = uscita.takeBytes();
  final scrittore = ByteData.sublistView(compatto);
  void correggi(int inizio, int fine) {
    for (final s in scatole(compatto, inizio, fine)) {
      final contenuto = s.inizio + s.intestazione;
      switch (s.tipo) {
        case 'moov' || 'trak' || 'mdia' || 'minf' || 'stbl':
          correggi(contenuto, s.inizio + s.dimensione);
        case 'stco':
          final n = scrittore.getUint32(contenuto + 4);
          for (var k = 0; k < n; k++) {
            final o = contenuto + 8 + 4 * k;
            final vecchio = scrittore.getUint32(o);
            scrittore.setUint32(o, vecchio - spostamento(vecchio));
          }
        case 'co64':
          final n = scrittore.getUint32(contenuto + 4);
          for (var k = 0; k < n; k++) {
            final o = contenuto + 8 + 8 * k;
            final vecchio = scrittore.getUint64(o);
            scrittore.setUint64(o, vecchio - spostamento(vecchio));
          }
      }
    }
  }

  correggi(0, compatto.length);
  return compatto;
}

/// Salva un messaggio arrivato dal coach, se non c'è già; vero se è nuovo.
/// Un messaggio dell'atleta che il coach ha già si considera inviato.
bool salvaMessaggioRicevuto(Database db, int coachId, Map<String, Object?> m) {
  final dalCoach = m['autore'] == 'coach';
  db.execute(
    'INSERT INTO messaggi (coach_id, id, dal_coach, testo, inviato_il, ordine, video, riferimento, stato, letto) '
    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'inviato', ?) ON CONFLICT (coach_id, id) DO NOTHING",
    [
      coachId,
      m['id'],
      dalCoach ? 1 : 0,
      m['testo'],
      m['inviato_il'],
      istante(analizzaDataOra(m['inviato_il'])!),
      m['video'] == null ? null : jsonEncode(m['video']),
      m['riferimento'] == null ? null : jsonEncode(m['riferimento']),
      dalCoach ? 0 : 1,
    ],
  );
  if (db.updatedRows > 0) return dalCoach;
  if (!dalCoach) {
    db.execute(
      "UPDATE messaggi SET stato = 'inviato', rifiuto = NULL WHERE coach_id = ? AND id = ? AND dal_coach = 0",
      [coachId, m['id']],
    );
  }
  return false;
}
