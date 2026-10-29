import 'dart:convert';
import 'dart:typed_data';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'errori.dart';
import 'eventi.dart';
import 'modelli.dart';
import 'tempo.dart';

/// Questionari (§8.6, §9.3): i modelli che il coach scrive, quelli mandati
/// agli atleti con le risposte, e le foto allegate.
///
/// Mandare un questionario ne copia il contenuto: cambiare il modello dopo
/// non cambia quello che l'atleta ha già ricevuto. Ogni invio e ogni
/// annullamento riceve un numero di sequenza, come le schede (§7.2).
class GestioneQuestionari {
  GestioneQuestionari(this._c);

  final ContestoCoach _c;

  Database get _db => _c.archivio.db;

  // Modelli.

  List<ModelloQuestionario> modelli() => [
    for (final riga in _db.select('SELECT * FROM questionari ORDER BY modificato_il DESC'))
      _modello(riga),
  ];

  ModelloQuestionario? modello(String id) {
    final riga = _db.select('SELECT * FROM questionari WHERE id = ?', [id]).firstOrNull;
    return riga == null ? null : _modello(riga);
  }

  /// Crea un modello e ne restituisce l'id.
  String creaModello(Map<String, Object?> contenuto) {
    final id = nuovoUuid();
    final ora = istante(_c.adesso());
    _db.execute(
      'INSERT INTO questionari (id, contenuto, creato_il, modificato_il) VALUES (?, ?, ?, ?)',
      [id, jsonEncode(_contenutoValido(contenuto)), ora, ora],
    );
    return id;
  }

  /// Salva il modello. Lancia [QuestionarioNonValido] se non si potrebbe
  /// mandare così com'è.
  void salvaModello(String id, Map<String, Object?> contenuto) {
    final testo = jsonEncode(_contenutoValido(contenuto));
    _db.execute('UPDATE questionari SET contenuto = ?, modificato_il = ? WHERE id = ?', [
      testo,
      istante(_c.adesso()),
      id,
    ]);
    if (_db.updatedRows == 0) throw const OperazioneNonValida('Questionario inesistente');
  }

  void eliminaModello(String id) => _db.execute('DELETE FROM questionari WHERE id = ?', [id]);

  /// Duplica il modello, con nuovi id per le domande, e restituisce l'id.
  String duplicaModello(String id) {
    final originale = modello(id);
    if (originale == null) throw const OperazioneNonValida('Questionario inesistente');
    final copia = jsonDecode(jsonEncode(originale.contenuto)) as Map<String, Object?>;
    copia['titolo'] = '${originale.titolo} (copia)';
    for (final domanda in (copia['domande'] as List<Object?>?) ?? const []) {
      if (domanda is Map<String, Object?>) domanda['id'] = nuovoUuid();
    }
    return creaModello(copia);
  }

  Map<String, Object?> _contenutoValido(Map<String, Object?> contenuto) {
    final pulito = {
      'titolo': contenuto['titolo'],
      if (contenuto['descrizione'] case final String d when d.trim().isNotEmpty) 'descrizione': d,
      'domande': contenuto['domande'],
      if (contenuto['foto'] != null) 'foto': contenuto['foto'],
    };
    final errori = validaContenutoQuestionario(pulito);
    if (errori.isNotEmpty) throw QuestionarioNonValido(errori);
    return pulito;
  }

  ModelloQuestionario _modello(Row r) => ModelloQuestionario(
    id: r['id'] as String,
    contenuto: jsonDecode(r['contenuto'] as String) as Map<String, Object?>,
    modificatoIl: leggiIstante(r['modificato_il'] as String),
  );

  // Invii.

  /// Manda il modello all'atleta: arriva alla sua sync successiva. Restituisce
  /// l'id del questionario mandato.
  String invia(String modelloId, String atletaId) {
    return _c.archivio.transazione(() {
      final m = modello(modelloId);
      if (m == null) throw const OperazioneNonValida('Questionario inesistente');
      if (_db.select('SELECT 1 FROM atleti WHERE id = ?', [atletaId]).isEmpty) {
        throw const OperazioneNonValida('Atleta inesistente');
      }
      final id = nuovoUuid();
      _db.execute(
        'INSERT INTO questionari_inviati (id, atleta_id, modello_id, contenuto, '
        "inviato_il, sequenza, stato, letto) VALUES (?, ?, ?, ?, ?, ?, 'inviato', 1)",
        [
          id,
          atletaId,
          modelloId,
          jsonEncode(m.contenuto),
          formattaDataOra(_c.adesso()),
          _c.archivio.prossimaSequenza(),
        ],
      );
      return id;
    });
  }

  /// Ritira un questionario a cui l'atleta non ha ancora risposto: sparisce
  /// dal suo telefono alla sync successiva.
  void annulla(String id) {
    _c.archivio.transazione(() {
      _db.execute(
        "UPDATE questionari_inviati SET stato = 'annullato', sequenza = ? "
        "WHERE id = ? AND stato = 'inviato'",
        [_c.archivio.prossimaSequenza(), id],
      );
      if (_db.updatedRows == 0) {
        throw const OperazioneNonValida('Si possono annullare solo i questionari senza risposta');
      }
    });
  }

  /// I questionari mandati all'atleta, dal più recente.
  List<QuestionarioInviato> inviati(String atletaId) => [
    for (final riga in _db.select(
      'SELECT * FROM questionari_inviati WHERE atleta_id = ? ORDER BY inviato_il DESC, sequenza DESC',
      [atletaId],
    ))
      _inviato(riga),
  ];

  QuestionarioInviato? inviato(String id) {
    final riga = _db.select('SELECT * FROM questionari_inviati WHERE id = ?', [id]).firstOrNull;
    return riga == null ? null : _inviato(riga);
  }

  /// Le risposte dell'atleta, dalla più recente: per scrivere la scheda.
  List<QuestionarioInviato> risposte(String atletaId) => [
    for (final q in inviati(atletaId))
      if (q.stato == StatoQuestionario.risposto) q,
  ]..sort((a, b) => b.rispostoIl!.compareTo(a.rispostoIl!));

  /// Risposte che il coach non ha ancora aperto.
  int nonLette(String atletaId) =>
      _db.select(
            "SELECT COUNT(*) AS n FROM questionari_inviati WHERE atleta_id = ? "
            "AND stato = 'risposto' AND letto = 0",
            [atletaId],
          ).first['n']
          as int;

  void segnaLetto(String id) =>
      _db.execute('UPDATE questionari_inviati SET letto = 1 WHERE id = ?', [id]);

  QuestionarioInviato _inviato(Row r) => QuestionarioInviato(
    id: r['id'] as String,
    atletaId: r['atleta_id'] as String,
    contenuto: jsonDecode(r['contenuto'] as String) as Map<String, Object?>,
    inviatoIl: analizzaDataOra(r['inviato_il'])!,
    stato: StatoQuestionario.values.byName(r['stato'] as String),
    risposta: switch (r['risposta']) {
      final String testo => jsonDecode(testo) as Map<String, Object?>,
      _ => null,
    },
    rispostoIl: leggiIstanteFacoltativo(r['risposto_il']),
    letto: r['letto'] == 1,
  );

  // Foto.

  /// `PUT /v1/foto/<id>`. Idempotente; una foto con lo stesso id di un altro
  /// atleta si rifiuta.
  void salvaFoto(String atletaId, String id, Uint8List jpeg) {
    if (!uuidValido(id)) {
      throw const ErroreHttp(404, CodiceErrore.nonTrovato);
    }
    if (!sembraJpeg(jpeg) || jpeg.length > Limiti.fotoMassima) {
      throw const ErroreHttp(400, CodiceErrore.richiestaNonValida, messaggio: 'Serve un JPEG');
    }
    _c.archivio.transazione(() {
      final esistente = _db.select('SELECT atleta_id FROM foto WHERE id = ?', [id]).firstOrNull;
      if (esistente != null) {
        if (esistente['atleta_id'] != atletaId) {
          throw const ErroreHttp(409, CodiceErrore.richiestaNonValida, messaggio: 'Id già usato');
        }
        return;
      }
      _db.execute(
        'INSERT INTO foto (id, atleta_id, dati, ricevuta_il) VALUES (?, ?, ?, ?)',
        [id, atletaId, jpeg, istante(_c.adesso())],
      );
    });
  }

  Uint8List? foto(String id) =>
      _db.select('SELECT dati FROM foto WHERE id = ?', [id]).firstOrNull?['dati'] as Uint8List?;

  // Sync.

  /// Salva le risposte arrivate con una sync (§7.2): idempotente, in una
  /// transazione già aperta.
  void riceviRisposta(
    Dispositivo dispositivo,
    Object? risposta,
    List<String> accettate,
    List<LogRifiutato> rifiutate,
    List<EventoCoach> eventi,
  ) {
    final id = risposta is Map<String, Object?> && risposta['questionario_id'] is String
        ? risposta['questionario_id'] as String
        : '';
    final riga = _db.select(
      'SELECT * FROM questionari_inviati WHERE id = ? AND atleta_id = ?',
      [id, dispositivo.atletaId],
    ).firstOrNull;
    if (riga == null) {
      rifiutate.add(LogRifiutato(id, RifiutoRisposta.sconosciuto));
      return;
    }
    if (riga['stato'] == 'risposto') {
      accettate.add(id);
      return;
    }
    final questionario = {
      'id': id,
      ...jsonDecode(riga['contenuto'] as String) as Map<String, Object?>,
    };
    if (validaRisposta(risposta, questionario).isNotEmpty) {
      rifiutate.add(LogRifiutato(id, RifiutoRisposta.nonValida));
      return;
    }
    final m = risposta! as Map<String, Object?>;
    final foto = [for (final f in m['foto']! as List<Object?>) f! as String];
    for (final f in foto) {
      final presente = _db.select(
        'SELECT 1 FROM foto WHERE id = ? AND atleta_id = ? AND '
        '(questionario_id IS NULL OR questionario_id = ?)',
        [f, dispositivo.atletaId, id],
      );
      if (presente.isEmpty) {
        rifiutate.add(LogRifiutato(id, RifiutoRisposta.fotoMancanti));
        return;
      }
    }
    for (final f in foto) {
      _db.execute('UPDATE foto SET questionario_id = ? WHERE id = ?', [id, f]);
    }
    // Anche un questionario annullato nel frattempo tiene le risposte: le ha
    // scritte l'atleta.
    _db.execute(
      "UPDATE questionari_inviati SET stato = 'risposto', risposta = ?, "
      'risposto_il = ?, letto = 0 WHERE id = ?',
      [jsonEncode(m), istante(_c.adesso()), id],
    );
    accettate.add(id);
    eventi.add(
      QuestionarioRisposto(dispositivo.atletaId, id, questionario['titolo'] as String),
    );
  }

  /// Il questionario come lo riceve l'app.
  Map<String, Object?> perProtocollo(Row riga) => {
    'id': riga['id'],
    'inviato_il': riga['inviato_il'],
    ...jsonDecode(riga['contenuto'] as String) as Map<String, Object?>,
  };
}

/// Il questionario non si può salvare: [errori] elenca i campi da correggere.
class QuestionarioNonValido implements Exception {
  const QuestionarioNonValido(this.errori);

  final List<String> errori;

  @override
  String toString() => 'QuestionarioNonValido: ${errori.join('; ')}';
}
