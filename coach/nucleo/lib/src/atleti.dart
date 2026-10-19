import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'errori.dart';
import 'inviti.dart';
import 'modelli.dart';
import 'tempo.dart';

/// Atleti del coach (§9.3).
class GestioneAtleti {
  GestioneAtleti(this._c, this._inviti);

  final ContestoCoach _c;
  final GestioneInviti _inviti;

  Database get _db => _c.archivio.db;

  Atleta crea(String nome, {String note = ''}) {
    final atleta = Atleta(
      id: nuovoUuid(),
      nome: _nomeValido(nome),
      note: note,
      archiviato: false,
      creatoIl: _c.adesso().toUtc(),
    );
    _db.execute(
      'INSERT INTO atleti (id, nome, note, stato, creato_il) '
      "VALUES (?, ?, ?, 'attivo', ?)",
      [atleta.id, atleta.nome, atleta.note, istante(atleta.creatoIl)],
    );
    return atleta;
  }

  Atleta? cerca(String id) {
    final riga = _db.select('SELECT * FROM atleti WHERE id = ?', [id]).firstOrNull;
    return riga == null ? null : Atleta.daRiga(riga);
  }

  void modifica(String id, {String? nome, String? note}) {
    _esistente(id);
    if (nome != null) {
      _db.execute('UPDATE atleti SET nome = ? WHERE id = ?', [_nomeValido(nome), id]);
    }
    if (note != null) {
      _db.execute('UPDATE atleti SET note = ? WHERE id = ?', [note, id]);
    }
  }

  /// Toglie l'atleta dall'elenco principale. Il telefono resta collegato.
  void archivia(String id) {
    _esistente(id);
    _db.execute("UPDATE atleti SET stato = 'archiviato' WHERE id = ?", [id]);
  }

  void riattiva(String id) {
    _esistente(id);
    _db.execute("UPDATE atleti SET stato = 'attivo' WHERE id = ?", [id]);
  }

  /// Revoca il dispositivo e cancella tutti i dati dell'atleta.
  void elimina(String id) {
    _esistente(id);
    _db.execute('DELETE FROM atleti WHERE id = ?', [id]);
    _c.segnalaChiaviCambiate();
  }

  List<RiepilogoAtleta> elenco({bool archiviati = false}) {
    final righe = _db.select(
      'SELECT * FROM atleti WHERE stato = ? ORDER BY nome COLLATE NOCASE',
      [archiviati ? 'archiviato' : 'attivo'],
    );
    return [
      for (final riga in righe)
        RiepilogoAtleta(
          Atleta.daRiga(riga),
          _dispositivoAttivo(riga['id'] as String),
          _inviti.inCorso(riga['id'] as String),
        ),
    ];
  }

  Dispositivo? _dispositivoAttivo(String atletaId) {
    final riga = _db.select(
      "SELECT * FROM dispositivi WHERE atleta_id = ? AND stato = 'attivo'",
      [atletaId],
    ).firstOrNull;
    return riga == null ? null : Dispositivo.daRiga(riga);
  }

  void _esistente(String id) {
    if (cerca(id) == null) throw const OperazioneNonValida('Atleta inesistente');
  }

  String _nomeValido(String nome) {
    final pulito = nome.trim();
    if (pulito.isEmpty || pulito.length > 200) {
      throw const OperazioneNonValida(
        'Il nome deve avere da 1 a 200 caratteri',
      );
    }
    return pulito;
  }
}
