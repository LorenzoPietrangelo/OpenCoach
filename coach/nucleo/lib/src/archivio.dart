import 'dart:async';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

/// Archivio SQLite del programma del coach (§8.3).
///
/// Tutte le operazioni sono sincrone: una transazione non si interrompe mai
/// per lasciare spazio ad altro codice Dart.
class Archivio {
  Archivio._(this.db);

  /// Apre l'archivio nel file [percorso], creandolo se non esiste.
  factory Archivio.apri(String percorso) => _prepara(sqlite3.open(percorso));

  /// Archivio temporaneo, per i test.
  factory Archivio.inMemoria() => _prepara(sqlite3.openInMemory());

  static Archivio _prepara(Database db) {
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = FULL');
    return Archivio._(db).._migra();
  }

  final Database db;

  void _migra() {
    final versione = db.userVersion;
    if (versione > _migrazioni.length) {
      throw StateError(
        'Archivio creato da una versione più recente del programma',
      );
    }
    for (var v = versione; v < _migrazioni.length; v++) {
      transazione(() {
        db.execute(_migrazioni[v]);
        db.userVersion = v + 1;
      });
    }
    transazione(() {
      if (impostazione(Impostazioni.epoca) == null) rigeneraEpoca();
      if (impostazione(Impostazioni.sequenza) == null) {
        scriviImpostazione(Impostazioni.sequenza, '0');
      }
    });
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

  String? impostazione(String chiave) =>
      db
              .select('SELECT valore FROM impostazioni WHERE chiave = ?', [
                chiave,
              ])
              .firstOrNull?['valore']
          as String?;

  void scriviImpostazione(String chiave, String valore) => db.execute(
    'INSERT INTO impostazioni (chiave, valore) VALUES (?, ?) '
    'ON CONFLICT (chiave) DO UPDATE SET valore = excluded.valore',
    [chiave, valore],
  );

  /// Identificativo dello stato dell'archivio. Cambia a ogni ripristino da
  /// backup, così le app si riallineano (§7.2).
  String get epoca => impostazione(Impostazioni.epoca)!;

  void rigeneraEpoca() => scriviImpostazione(Impostazioni.epoca, nuovoUuid());

  /// Ultimo numero di sequenza assegnato a una modifica visibile agli atleti.
  int get sequenzaCorrente => int.parse(impostazione(Impostazioni.sequenza)!);

  /// Assegna il prossimo numero di sequenza. Va chiamata in una transazione.
  int prossimaSequenza() {
    final sequenza = sequenzaCorrente + 1;
    scriviImpostazione(Impostazioni.sequenza, '$sequenza');
    _sequenzaCambiata.add(null);
    return sequenza;
  }

  final _sequenzaCambiata = StreamController<void>.broadcast();

  /// Una modifica visibile agli atleti. Arriva dopo la fine della transazione
  /// in corso, che è sincrona.
  Stream<void> get sequenzaCambiata => _sequenzaCambiata.stream;

  void chiudi() {
    unawaited(_sequenzaCambiata.close());
    db.close();
  }
}

/// Chiavi della tabella `impostazioni`.
abstract final class Impostazioni {
  static const epoca = 'epoca';
  static const sequenza = 'sequenza';
  static const nomeCoach = 'nome_coach';
  static const versioneAppMinima = 'versione_app_minima';
  static const cartellaBackup = 'cartella_backup';
  static const giorniTraBackup = 'giorni_tra_backup';
  static const ultimoBackup = 'ultimo_backup';
}

const _migrazioni = [
  '''
CREATE TABLE impostazioni (
  chiave TEXT PRIMARY KEY,
  valore TEXT NOT NULL
);

CREATE TABLE identita (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  seme_cifrato BLOB NOT NULL,
  indirizzo TEXT NOT NULL,
  creata_il TEXT NOT NULL
);

CREATE TABLE atleti (
  id TEXT PRIMARY KEY,
  nome TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  stato TEXT NOT NULL CHECK (stato IN ('attivo', 'archiviato')),
  creato_il TEXT NOT NULL
);

CREATE TABLE inviti (
  id TEXT PRIMARY KEY,
  atleta_id TEXT NOT NULL REFERENCES atleti (id) ON DELETE CASCADE,
  segreto TEXT,
  chiave_privata TEXT,
  chiave_pubblica TEXT NOT NULL,
  creato_il TEXT NOT NULL,
  scade_il TEXT NOT NULL,
  stato TEXT NOT NULL CHECK (
    stato IN ('aperto', 'in_abbinamento', 'usato', 'scaduto', 'annullato')
  ),
  dispositivo_id TEXT
);
CREATE INDEX inviti_atleta ON inviti (atleta_id, stato);

CREATE TABLE dispositivi (
  id TEXT PRIMARY KEY,
  atleta_id TEXT NOT NULL REFERENCES atleti (id) ON DELETE CASCADE,
  chiave_pubblica TEXT NOT NULL,
  hash_token BLOB NOT NULL UNIQUE,
  nome TEXT NOT NULL,
  piattaforma TEXT NOT NULL,
  versione_app TEXT NOT NULL,
  abbinato_il TEXT NOT NULL,
  ultimo_contatto TEXT,
  ultima_sequenza INTEGER NOT NULL DEFAULT 0,
  stato TEXT NOT NULL CHECK (stato IN ('attivo', 'revocato')),
  revocato_il TEXT
);
CREATE INDEX dispositivi_atleta ON dispositivi (atleta_id, stato);

CREATE TABLE schede (
  id TEXT PRIMARY KEY,
  atleta_id TEXT NOT NULL REFERENCES atleti (id) ON DELETE CASCADE,
  bozza TEXT NOT NULL,
  bozza_modificata INTEGER NOT NULL,
  stato TEXT NOT NULL CHECK (
    stato IN ('bozza', 'pubblicata', 'archiviata', 'eliminata')
  ),
  revisione INTEGER NOT NULL DEFAULT 0,
  sequenza INTEGER,
  creata_il TEXT NOT NULL,
  modificata_il TEXT NOT NULL
);
CREATE INDEX schede_atleta ON schede (atleta_id, sequenza);

CREATE TABLE revisioni (
  scheda_id TEXT NOT NULL REFERENCES schede (id) ON DELETE CASCADE,
  revisione INTEGER NOT NULL,
  contenuto TEXT NOT NULL,
  pubblicata_il TEXT NOT NULL,
  sequenza INTEGER NOT NULL,
  ricevuta_il TEXT,
  PRIMARY KEY (scheda_id, revisione)
);

CREATE TABLE log (
  id TEXT PRIMARY KEY,
  atleta_id TEXT NOT NULL REFERENCES atleti (id) ON DELETE CASCADE,
  dispositivo_id TEXT,
  rev INTEGER NOT NULL,
  eliminato INTEGER NOT NULL,
  contenuto TEXT,
  eseguito_il TEXT,
  ricevuto_il TEXT NOT NULL
);
CREATE INDEX log_atleta ON log (atleta_id, eseguito_il);
''',
  '''
CREATE TABLE libreria (
  id TEXT PRIMARY KEY,
  nome TEXT NOT NULL,
  chiave TEXT NOT NULL UNIQUE,
  note TEXT NOT NULL DEFAULT '',
  video TEXT,
  creato_il TEXT NOT NULL,
  modificato_il TEXT NOT NULL
);
''',
  '''
CREATE TABLE pesi (
  id TEXT PRIMARY KEY,
  atleta_id TEXT NOT NULL REFERENCES atleti (id) ON DELETE CASCADE,
  rev INTEGER NOT NULL,
  eliminato INTEGER NOT NULL,
  giorno TEXT,
  kg REAL,
  ricevuto_il TEXT NOT NULL
);
CREATE INDEX pesi_atleta ON pesi (atleta_id, giorno);
''',
  '''
CREATE TABLE questionari (
  id TEXT PRIMARY KEY,
  contenuto TEXT NOT NULL,
  creato_il TEXT NOT NULL,
  modificato_il TEXT NOT NULL
);

CREATE TABLE questionari_inviati (
  id TEXT PRIMARY KEY,
  atleta_id TEXT NOT NULL REFERENCES atleti (id) ON DELETE CASCADE,
  modello_id TEXT,
  contenuto TEXT NOT NULL,
  inviato_il TEXT NOT NULL,
  sequenza INTEGER NOT NULL,
  stato TEXT NOT NULL CHECK (stato IN ('inviato', 'risposto', 'annullato')),
  risposta TEXT,
  risposto_il TEXT,
  letto INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX questionari_inviati_atleta ON questionari_inviati (atleta_id, sequenza);

CREATE TABLE foto (
  id TEXT PRIMARY KEY,
  atleta_id TEXT NOT NULL REFERENCES atleti (id) ON DELETE CASCADE,
  questionario_id TEXT,
  dati BLOB NOT NULL,
  ricevuta_il TEXT NOT NULL
);
CREATE INDEX foto_questionario ON foto (questionario_id);
''',
  '''
CREATE TABLE messaggi (
  id TEXT PRIMARY KEY,
  atleta_id TEXT NOT NULL REFERENCES atleti (id) ON DELETE CASCADE,
  autore TEXT NOT NULL CHECK (autore IN ('coach', 'atleta')),
  testo TEXT NOT NULL,
  inviato_il TEXT NOT NULL,
  ordine TEXT NOT NULL,
  video TEXT,
  riferimento TEXT,
  video_eliminato INTEGER NOT NULL DEFAULT 0,
  sequenza INTEGER,
  letto INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX messaggi_atleta ON messaggi (atleta_id, ordine);
CREATE INDEX messaggi_sequenza ON messaggi (atleta_id, sequenza);
''',
  '''
CREATE TABLE telefoni_coach (
  id TEXT PRIMARY KEY,
  chiave_pubblica TEXT NOT NULL,
  hash_token BLOB NOT NULL UNIQUE,
  nome TEXT NOT NULL,
  piattaforma TEXT NOT NULL,
  versione_app TEXT NOT NULL,
  abbinato_il TEXT NOT NULL,
  ultimo_contatto TEXT,
  stato TEXT NOT NULL CHECK (stato IN ('attivo', 'revocato')),
  revocato_il TEXT
);

CREATE TABLE inviti_telefono_coach (
  id TEXT PRIMARY KEY,
  segreto TEXT,
  chiave_privata TEXT,
  chiave_pubblica TEXT NOT NULL,
  creato_il TEXT NOT NULL,
  scade_il TEXT NOT NULL,
  stato TEXT NOT NULL CHECK (
    stato IN ('aperto', 'in_abbinamento', 'usato', 'scaduto', 'annullato')
  ),
  telefono_id TEXT
);
''',
];
