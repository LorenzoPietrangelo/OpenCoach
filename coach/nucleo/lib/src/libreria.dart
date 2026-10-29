import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'errori.dart';
import 'modelli.dart';
import 'schede.dart';
import 'tempo.dart';

/// Chiave con cui un esercizio delle schede trova il suo esercizio della
/// libreria: il nome senza spazi ai lati e senza maiuscole.
String chiaveEsercizio(String nome) => nome.trim().toLowerCase();

/// Libreria degli esercizi del coach (§9.3): nome, note e link a un video.
///
/// Le schede la seguono per nome: alla pubblicazione ogni esercizio prende
/// il video dell'esercizio con lo stesso nome. Le note si copiano nella
/// scheda solo quando il coach sceglie l'esercizio nell'editor.
class GestioneLibreria {
  GestioneLibreria(this._c, this._schede);

  final ContestoCoach _c;
  final GestioneSchede _schede;

  Database get _db => _c.archivio.db;

  List<EsercizioLibreria> elenco() => [
    for (final riga in _db.select(
      'SELECT * FROM libreria ORDER BY nome COLLATE NOCASE',
    ))
      _daRiga(riga),
  ];

  EsercizioLibreria? perNome(String nome) {
    final riga = _db.select('SELECT * FROM libreria WHERE chiave = ?', [
      chiaveEsercizio(nome),
    ]).firstOrNull;
    return riga == null ? null : _daRiga(riga);
  }

  /// Crea l'esercizio, o lo modifica se [id] non è null, e ne restituisce
  /// l'id. [video] deve essere un link https (§8.1).
  String salva({
    String? id,
    required String nome,
    String note = '',
    String? video,
  }) {
    final pulito = nome.trim();
    if (pulito.isEmpty || pulito.length > 200) {
      throw const OperazioneNonValida('Il nome deve avere da 1 a 200 caratteri');
    }
    if (note.length > 5000) {
      throw const OperazioneNonValida('Le note sono troppo lunghe');
    }
    final link = video == null || video.trim().isEmpty ? null : video.trim();
    if (link != null && analizzaLinkVideo(link) == null) {
      throw const OperazioneNonValida('Il video deve essere un link https');
    }
    final ora = istante(_c.adesso());
    return _c.archivio.transazione(() {
      final doppio = _db.select('SELECT id FROM libreria WHERE chiave = ?', [
        chiaveEsercizio(pulito),
      ]).firstOrNull;
      if (doppio != null && doppio['id'] != id) {
        throw const OperazioneNonValida('Esiste già un esercizio con questo nome');
      }
      final String risultato;
      if (id == null) {
        risultato = nuovoUuid();
        _db.execute(
          'INSERT INTO libreria (id, nome, chiave, note, video, creato_il, '
          'modificato_il) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [risultato, pulito, chiaveEsercizio(pulito), note, link, ora, ora],
        );
      } else {
        _db.execute(
          'UPDATE libreria SET nome = ?, chiave = ?, note = ?, video = ?, '
          'modificato_il = ? WHERE id = ?',
          [pulito, chiaveEsercizio(pulito), note, link, ora, id],
        );
        if (_db.updatedRows == 0) {
          throw const OperazioneNonValida('Esercizio inesistente');
        }
        risultato = id;
      }
      _schede.ricalcolaModifiche();
      return risultato;
    });
  }

  void elimina(String id) {
    _c.archivio.transazione(() {
      _db.execute('DELETE FROM libreria WHERE id = ?', [id]);
      _schede.ricalcolaModifiche();
    });
  }

  EsercizioLibreria _daRiga(Row r) => EsercizioLibreria(
    id: r['id'] as String,
    nome: r['nome'] as String,
    note: r['note'] as String,
    video: r['video'] as String?,
  );
}
