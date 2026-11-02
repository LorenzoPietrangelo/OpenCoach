import 'package:sqlite3/sqlite3.dart';

/// Archivio SQLite dell'app (§8.4). Per ogni coach: indirizzo, nome, id
/// dell'atleta e del dispositivo, cursore, epoca e data dell'ultima sync; le
/// sue schede; i log, ciascuno con la `rev` locale e l'ultima `rev`
/// confermata. Chiavi e token non stanno qui ma nella cassaforte del
/// telefono (§4).
///
/// L'app lo apre nel proprio spazio privato. Su iOS il file va creato con la
/// classe di protezione `CompleteUntilFirstUserAuthentication`, così la sync
/// in background può leggerlo.
///
/// Tutte le operazioni sono sincrone: una transazione non si interrompe mai
/// per lasciare spazio ad altro codice Dart.
class ArchivioAtleta {
  ArchivioAtleta._(this.db);

  /// Apre l'archivio nel file [percorso], creandolo se non esiste.
  factory ArchivioAtleta.apri(String percorso) =>
      _prepara(sqlite3.open(percorso));

  /// Archivio temporaneo, per i test.
  factory ArchivioAtleta.inMemoria() => _prepara(sqlite3.openInMemory());

  static ArchivioAtleta _prepara(Database db) {
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = FULL');
    return ArchivioAtleta._(db).._migra();
  }

  final Database db;

  void _migra() {
    final versione = db.userVersion;
    if (versione > _migrazioni.length) {
      throw StateError("Archivio creato da una versione più recente dell'app");
    }
    for (var v = versione; v < _migrazioni.length; v++) {
      transazione(() {
        db.execute(_migrazioni[v]);
        db.userVersion = v + 1;
      });
    }
  }

  /// Esegue [operazione] in una transazione. Se una transazione è già aperta,
  /// [operazione] ne fa parte.
  T transazione<T>(T Function() operazione) {
    if (!db.autocommit) return operazione();
    db.execute('BEGIN IMMEDIATE');
    try {
      final risultato = operazione();
      db.execute('COMMIT');
      return risultato;
    } catch (_) {
      if (!db.autocommit) db.execute('ROLLBACK');
      rethrow;
    }
  }

  void chiudi() => db.close();
}

const _migrazioni = [
  '''
CREATE TABLE coach (
  id INTEGER PRIMARY KEY,
  indirizzo TEXT NOT NULL,
  nome_coach TEXT NOT NULL,
  nome_atleta TEXT NOT NULL,
  atleta_id TEXT NOT NULL,
  dispositivo_id TEXT NOT NULL,
  stato TEXT NOT NULL CHECK (stato IN ('attivo', 'revocato', 'scollegato')),
  conferma_in_sospeso INTEGER NOT NULL,
  abbinato_il TEXT NOT NULL,
  epoca TEXT,
  cursore TEXT,
  ultima_sync TEXT,
  problema TEXT,
  problema_il TEXT,
  rifiuti_chiave INTEGER NOT NULL DEFAULT 0,
  UNIQUE (indirizzo, atleta_id)
);
CREATE UNIQUE INDEX coach_attivo ON coach (indirizzo) WHERE stato = 'attivo';

CREATE TABLE schede (
  coach_id INTEGER NOT NULL REFERENCES coach (id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  revisione INTEGER NOT NULL,
  archiviata INTEGER NOT NULL,
  contenuto TEXT NOT NULL,
  ricevuta_il TEXT NOT NULL,
  revisione_vista INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (coach_id, id)
);

CREATE TABLE log (
  coach_id INTEGER NOT NULL REFERENCES coach (id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  rev INTEGER NOT NULL,
  rev_confermata INTEGER NOT NULL,
  eliminato INTEGER NOT NULL,
  contenuto TEXT,
  eseguito_il TEXT,
  rifiuto TEXT,
  PRIMARY KEY (coach_id, id)
);
CREATE INDEX log_eseguiti ON log (coach_id, eseguito_il);
''',
  '''
CREATE TABLE pesi (
  giorno TEXT PRIMARY KEY,
  id TEXT NOT NULL UNIQUE,
  rev INTEGER NOT NULL,
  eliminato INTEGER NOT NULL,
  kg REAL,
  modificato_il TEXT NOT NULL
);

CREATE TABLE pesi_inviati (
  coach_id INTEGER NOT NULL REFERENCES coach (id) ON DELETE CASCADE,
  peso_id TEXT NOT NULL,
  rev INTEGER NOT NULL,
  PRIMARY KEY (coach_id, peso_id)
);

ALTER TABLE coach ADD COLUMN condividi_pesi INTEGER NOT NULL DEFAULT 1;
ALTER TABLE coach ADD COLUMN pesi_supportati INTEGER;
''',
  '''
CREATE TABLE questionari (
  coach_id INTEGER NOT NULL REFERENCES coach (id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  contenuto TEXT NOT NULL,
  ricevuto_il TEXT NOT NULL,
  stato TEXT NOT NULL CHECK (stato IN ('da_compilare', 'in_invio', 'inviato')),
  bozza TEXT,
  risposta TEXT,
  rifiuto TEXT,
  PRIMARY KEY (coach_id, id)
);

CREATE TABLE foto (
  id TEXT PRIMARY KEY,
  coach_id INTEGER NOT NULL,
  questionario_id TEXT NOT NULL,
  posizione INTEGER NOT NULL,
  dati BLOB NOT NULL,
  caricata INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (coach_id, questionario_id) REFERENCES questionari (coach_id, id)
    ON DELETE CASCADE,
  UNIQUE (coach_id, questionario_id, posizione)
);
''',
  '''
CREATE TABLE messaggi (
  coach_id INTEGER NOT NULL REFERENCES coach (id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  dal_coach INTEGER NOT NULL,
  testo TEXT NOT NULL,
  inviato_il TEXT NOT NULL,
  ordine TEXT NOT NULL,
  video TEXT,
  riferimento TEXT,
  file_video TEXT,
  parti_caricate INTEGER NOT NULL DEFAULT 0,
  ricaricamenti INTEGER NOT NULL DEFAULT 0,
  stato TEXT NOT NULL CHECK (stato IN ('in_invio', 'inviato', 'rifiutato')),
  rifiuto TEXT,
  letto INTEGER NOT NULL,
  PRIMARY KEY (coach_id, id)
);
CREATE INDEX messaggi_ordine ON messaggi (coach_id, ordine);

ALTER TABLE coach ADD COLUMN chat_supportata INTEGER;
''',
];
