import 'dart:convert';
import 'dart:typed_data';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'errori.dart';
import 'tempo.dart';

enum StatoQuestionario {
  daCompilare,

  /// Inviato dall'atleta, in coda per il coach: non si modifica più.
  inInvio,

  /// Il coach ha ricevuto le risposte.
  inviato,
}

/// Questionario mandato da un coach (§8.6), con la bozza delle risposte o le
/// risposte inviate.
class QuestionarioRicevuto {
  const QuestionarioRicevuto({
    required this.coachId,
    required this.id,
    required this.contenuto,
    required this.ricevutoIl,
    required this.stato,
    required this.bozza,
    required this.risposta,
    required this.rifiuto,
  });

  factory QuestionarioRicevuto.daRiga(Row r) => QuestionarioRicevuto(
    coachId: r['coach_id'] as int,
    id: r['id'] as String,
    contenuto: jsonDecode(r['contenuto'] as String) as Map<String, Object?>,
    ricevutoIl: leggiIstante(r['ricevuto_il'] as String),
    stato: switch (r['stato']) {
      'da_compilare' => StatoQuestionario.daCompilare,
      'in_invio' => StatoQuestionario.inInvio,
      _ => StatoQuestionario.inviato,
    },
    bozza: switch (r['bozza']) {
      final String testo => jsonDecode(testo) as Map<String, Object?>,
      _ => const {},
    },
    risposta: switch (r['risposta']) {
      final String testo => jsonDecode(testo) as Map<String, Object?>,
      _ => null,
    },
    rifiuto: r['rifiuto'] as String?,
  );

  final int coachId;
  final String id;

  /// Il questionario come l'ha mandato il coach, già validato.
  final Map<String, Object?> contenuto;
  final DateTime ricevutoIl;
  final StatoQuestionario stato;

  /// Risposte salvate e non ancora inviate, per id della domanda.
  final Map<String, Object?> bozza;

  /// Le risposte inviate (§8.6).
  final Map<String, Object?>? risposta;

  /// Perché il coach non ha accettato le risposte: l'atleta le ricontrolla
  /// e le rimanda.
  final String? rifiuto;

  String get titolo => contenuto['titolo'] is String ? contenuto['titolo'] as String : '';

  String get descrizione => contenuto['descrizione'] is String ? contenuto['descrizione'] as String : '';

  List<Map<String, Object?>> get domande => [
    if (contenuto['domande'] case final List<Object?> lista)
      for (final d in lista)
        if (d is Map<String, Object?>) d,
  ];

  /// Quante foto chiede il coach; 0 se nessuna.
  int get fotoRichieste => switch (contenuto['foto']) {
    {'numero': final int numero} => numero,
    _ => 0,
  };

  String get istruzioniFoto => switch (contenuto['foto']) {
    {'istruzioni': final String istruzioni} => istruzioni,
    _ => '',
  };
}

/// Le risposte non rispettano il questionario: [errori] dice cosa manca.
class RispostaNonValida implements Exception {
  const RispostaNonValida(this.errori);

  final List<String> errori;

  @override
  String toString() => 'RispostaNonValida: ${errori.join('; ')}';
}

/// Questionari dei coach (§8.6): l'atleta li compila, anche in più volte,
/// allega le foto richieste e li invia. Inviati, non si modificano più.
class QuestionariRicevuti {
  QuestionariRicevuti(this._c, {required void Function(int coachId) cambiato})
    : _cambiato = cambiato;

  final ContestoAtleta _c;
  final void Function(int coachId) _cambiato;

  Database get _db => _c.db;

  /// I questionari del coach: prima quelli da compilare, poi gli altri, dal
  /// più recente.
  List<QuestionarioRicevuto> elenco(int coachId) => [
    for (final riga in _db.select(
      "SELECT * FROM questionari WHERE coach_id = ? "
      "ORDER BY stato != 'da_compilare', ricevuto_il DESC",
      [coachId],
    ))
      QuestionarioRicevuto.daRiga(riga),
  ];

  QuestionarioRicevuto? cerca(int coachId, String id) {
    final riga = _db.select('SELECT * FROM questionari WHERE coach_id = ? AND id = ?', [
      coachId,
      id,
    ]).firstOrNull;
    return riga == null ? null : QuestionarioRicevuto.daRiga(riga);
  }

  int daCompilare(int coachId) =>
      _db.select(
            "SELECT COUNT(*) AS n FROM questionari WHERE coach_id = ? AND stato = 'da_compilare'",
            [coachId],
          ).first['n']
          as int;

  /// Salva la risposta alla domanda [domandaId]; null la toglie.
  void rispondi(int coachId, String id, String domandaId, Object? valore) {
    _c.archivio.transazione(() {
      final q = _modificabile(coachId, id);
      final bozza = Map<String, Object?>.of(q.bozza);
      if (valore == null) {
        bozza.remove(domandaId);
      } else {
        bozza[domandaId] = valore;
      }
      _db.execute('UPDATE questionari SET bozza = ? WHERE coach_id = ? AND id = ?', [
        jsonEncode(bozza),
        coachId,
        id,
      ]);
    });
    _c.segnala(coachId);
  }

  /// Le foto allegate, per posizione: la posizione va da 0 al numero di foto
  /// richieste meno uno.
  Map<int, Uint8List> foto(int coachId, String id) => {
    for (final riga in _db.select(
      'SELECT posizione, dati FROM foto WHERE coach_id = ? AND questionario_id = ? ORDER BY posizione',
      [coachId, id],
    ))
      riga['posizione'] as int: riga['dati'] as Uint8List,
  };

  /// Allega la foto in [posizione], già compressa in JPEG dall'app e senza
  /// dati di posizione, sostituendo quella che c'era.
  void allegaFoto(int coachId, String id, int posizione, Uint8List jpeg) {
    if (!sembraJpeg(jpeg) || jpeg.length > Limiti.fotoMassima) {
      throw const OperazioneNonAmmessa('La foto deve essere un JPEG di al massimo 1,5 MB');
    }
    _c.archivio.transazione(() {
      final q = _modificabile(coachId, id);
      if (posizione < 0 || posizione >= q.fotoRichieste) {
        throw const OperazioneNonAmmessa('Il coach non ha chiesto questa foto');
      }
      _db.execute(
        'DELETE FROM foto WHERE coach_id = ? AND questionario_id = ? AND posizione = ?',
        [coachId, id, posizione],
      );
      _db.execute(
        'INSERT INTO foto (id, coach_id, questionario_id, posizione, dati) VALUES (?, ?, ?, ?, ?)',
        [nuovoUuid(), coachId, id, posizione, jpeg],
      );
    });
    _c.segnala(coachId);
  }

  void togliFoto(int coachId, String id, int posizione) {
    _c.archivio.transazione(() {
      _modificabile(coachId, id);
      _db.execute(
        'DELETE FROM foto WHERE coach_id = ? AND questionario_id = ? AND posizione = ?',
        [coachId, id, posizione],
      );
    });
    _c.segnala(coachId);
  }

  /// Invia le risposte: partono alla sync successiva e non si modificano
  /// più. Lancia [RispostaNonValida] se manca una risposta obbligatoria o una
  /// foto.
  void invia(int coachId, String id) {
    _c.archivio.transazione(() {
      final q = _modificabile(coachId, id);
      final foto = _db.select(
        'SELECT id FROM foto WHERE coach_id = ? AND questionario_id = ? ORDER BY posizione',
        [coachId, id],
      );
      final risposta = {
        'questionario_id': id,
        'inviata_il': formattaDataOra(_c.orologio.adesso()),
        'risposte': [
          for (final domanda in q.domande)
            if (q.bozza[domanda['id']] case final Object valore)
              {'domanda_id': domanda['id'], 'valore': valore},
        ],
        'foto': [for (final f in foto) f['id']],
      };
      final errori = validaRisposta(risposta, {'id': id, ...q.contenuto});
      if (errori.isNotEmpty) throw RispostaNonValida(errori);
      _db.execute(
        "UPDATE questionari SET stato = 'in_invio', risposta = ?, rifiuto = NULL "
        'WHERE coach_id = ? AND id = ?',
        [jsonEncode(risposta), coachId, id],
      );
    });
    _c.segnala(coachId);
    _cambiato(coachId);
  }

  QuestionarioRicevuto _modificabile(int coachId, String id) {
    final q = cerca(coachId, id);
    if (q == null) throw const OperazioneNonAmmessa('Questionario inesistente');
    if (q.stato != StatoQuestionario.daCompilare) {
      throw const OperazioneNonAmmessa('Il questionario è già stato inviato');
    }
    return q;
  }
}
