import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

/// Il catalogo dei cibi che il programma del coach tiene sul PC (§10.3): i
/// prodotti venduti in Italia di Open Food Facts, con le calorie. Gli atleti
/// lo interrogano con `GET /v1/cibo`.
///
/// Il file lo prepara `bin/genera_catalogo_cibo.dart` dall'esportazione CSV
/// di Open Food Facts e arriva con l'installer; il programma lo apre in sola
/// lettura.
class CatalogoCibo {
  CatalogoCibo._(this._db);

  /// Apre in sola lettura il catalogo nel file [percorso].
  factory CatalogoCibo.apri(String percorso) =>
      CatalogoCibo._(sqlite3.open(percorso, mode: OpenMode.readOnly));

  /// Un catalogo su un database già aperto, per i test.
  factory CatalogoCibo.da(Database db) => CatalogoCibo._(db);

  final Database _db;

  /// Prodotti al massimo in una ricerca.
  static const risultatiMassimi = 30;

  /// Prodotti nel catalogo.
  int get prodotti => _db.select('SELECT COUNT(*) AS n FROM prodotti').first['n'] as int;

  /// Quando è stato generato, come lo scrive il generatore.
  String? get generatoIl =>
      _db.select("SELECT valore FROM info WHERE chiave = 'generato_il'").firstOrNull?['valore'] as String?;

  /// I prodotti che contengono tutte le parole di [testo], anche come inizio
  /// di parola e senza badare agli accenti, dal più pertinente.
  List<ProdottoCibo> cerca(String testo, {int massimo = risultatiMassimi}) {
    final parole = RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(testo.toLowerCase())
        .map((m) => m[0]!)
        .take(8)
        .toList();
    if (parole.isEmpty) return const [];
    final query = parole.map((p) => '"$p"*').join(' ');
    return [
      for (final riga in _db.select(
        'SELECT p.* FROM ricerca JOIN prodotti p ON p.codice = ricerca.codice '
        'WHERE ricerca MATCH ? ORDER BY bm25(ricerca, 0.0, 10.0, 2.0) LIMIT ?',
        [query, massimo],
      ))
        _prodotto(riga),
    ];
  }

  /// Il prodotto con il codice a barre [codice], o null.
  ProdottoCibo? perCodice(String codice) {
    final riga = _db.select('SELECT * FROM prodotti WHERE codice = ?', [codice]).firstOrNull;
    return riga == null ? null : _prodotto(riga);
  }

  void chiudi() => _db.close();

  static ProdottoCibo _prodotto(Row r) => ProdottoCibo(
    codice: r['codice'] as String,
    nome: r['nome'] as String,
    marca: r['marca'] as String?,
    porzioneG: (r['porzione'] as num?)?.toDouble(),
    per100g: ValoriCibo(
      kcal: (r['kcal'] as num).toDouble(),
      proteine: (r['proteine'] as num?)?.toDouble(),
      carboidrati: (r['carboidrati'] as num?)?.toDouble(),
      grassi: (r['grassi'] as num?)?.toDouble(),
    ),
  );
}

/// Esito di [generaCatalogo].
class CatalogoGenerato {
  const CatalogoGenerato({required this.righe, required this.prodotti});

  /// Righe lette dal CSV, senza l'intestazione.
  final int righe;

  /// Prodotti italiani con le calorie, finiti nel catalogo.
  final int prodotti;
}

/// Riempie [db], vuoto, con i prodotti venduti in Italia che hanno nome,
/// codice a barre e calorie, letti dalle [righe] dell'esportazione CSV di
/// Open Food Facts (separata da tabulazioni, con l'intestazione in testa).
/// Tiene anche il sale, che il protocollo per ora non usa.
Future<CatalogoGenerato> generaCatalogo(
  Stream<String> righe,
  Database db, {
  required DateTime adesso,
}) async {
  db.execute('''
CREATE TABLE info (chiave TEXT PRIMARY KEY, valore TEXT NOT NULL);
CREATE TABLE prodotti (
  codice TEXT PRIMARY KEY,
  nome TEXT NOT NULL,
  marca TEXT,
  kcal REAL NOT NULL,
  grassi REAL,
  proteine REAL,
  carboidrati REAL,
  sale REAL,
  porzione REAL
) WITHOUT ROWID;
''');
  Map<String, int>? colonne;
  var lette = 0;
  var lotto = <List<Object?>>[];
  final inserisci = db.prepare(
    'INSERT OR REPLACE INTO prodotti VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
  );
  void svuota() {
    db.execute('BEGIN');
    for (final valori in lotto) {
      inserisci.execute(valori);
    }
    db.execute('COMMIT');
    lotto = [];
  }

  await for (final riga in righe) {
    final campi = riga.split('\t');
    if (colonne == null) {
      colonne = {for (final (i, nome) in campi.indexed) nome: i};
      for (final necessaria in const ['code', 'product_name', 'brands', 'countries_tags', 'energy-kcal_100g']) {
        if (!colonne.containsKey(necessaria)) {
          throw FormatException('Colonna "$necessaria" mancante nel CSV');
        }
      }
      continue;
    }
    lette++;
    String campo(String nome) {
      final i = colonne![nome];
      return i == null || i >= campi.length ? '' : campi[i];
    }

    if (!campo('countries_tags').contains('en:italy')) continue;
    final prodotto = prodottoDaOff({
      'code': campo('code'),
      'product_name': campo('product_name'),
      'brands': campo('brands'),
      'serving_quantity': campo('serving_quantity'),
      'nutriments': {
        'energy-kcal_100g': campo('energy-kcal_100g'),
        'energy-kj_100g': campo('energy-kj_100g'),
        'proteins_100g': campo('proteins_100g'),
        'carbohydrates_100g': campo('carbohydrates_100g'),
        'fat_100g': campo('fat_100g'),
      },
    });
    if (prodotto == null) continue;
    final valori = prodotto.per100g;
    final sale = double.tryParse(campo('salt_100g'));
    lotto.add([
      prodotto.codice,
      prodotto.nome,
      prodotto.marca,
      valori.kcal,
      valori.grassi,
      valori.proteine,
      valori.carboidrati,
      sale != null && sale >= 0 && sale <= 100 ? sale : null,
      prodotto.porzioneG,
    ]);
    if (lotto.length >= 20000) svuota();
  }
  svuota();
  inserisci.close();
  if (colonne == null) throw const FormatException('CSV vuoto');

  db.execute('''
CREATE VIRTUAL TABLE ricerca USING fts5(
  codice UNINDEXED, nome, marca,
  tokenize = 'unicode61 remove_diacritics 2'
);
INSERT INTO ricerca SELECT codice, nome, COALESCE(marca, '') FROM prodotti;
INSERT INTO ricerca (ricerca) VALUES ('optimize');
''');
  final prodotti = db.select('SELECT COUNT(*) AS n FROM prodotti').first['n'] as int;
  db.execute('INSERT INTO info VALUES (?, ?), (?, ?), (?, ?)', [
    'generato_il',
    formattaDataOra(adesso),
    'fonte',
    'Open Food Facts, https://world.openfoodfacts.org',
    'licenza',
    'Open Database License (ODbL) 1.0',
  ]);
  db.execute('VACUUM');
  return CatalogoGenerato(righe: lette, prodotti: prodotti);
}
