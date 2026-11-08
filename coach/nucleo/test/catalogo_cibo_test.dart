import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _intestazione = [
  'code',
  'product_name',
  'brands',
  'countries_tags',
  'serving_quantity',
  'energy-kj_100g',
  'energy-kcal_100g',
  'fat_100g',
  'carbohydrates_100g',
  'proteins_100g',
  'salt_100g',
];

String _riga(List<String> campi) => campi.join('\t');

void main() {
  late CatalogoCibo catalogo;
  late CatalogoGenerato esito;

  setUp(() async {
    final db = sqlite3.openInMemory();
    esito = await generaCatalogo(
      Stream.fromIterable([
        _intestazione.join('\t'),
        _riga(['8001234567890', 'Pasta di semola', 'Pastificio Rossi,Altro', 'en:italy', '80', '', '353', '1.5', '72', '12', '0.01']),
        _riga(['8001234567891', 'Fette biscottate integrali', 'Forno', 'en:france,en:italy', '8', '', '395', '5.6', '68', '13', '1.2']),
        _riga(['8001234567892', 'Pâté de campagne', 'Bistrot', 'en:france', '', '', '300', '25', '2', '15', '1.8']),
        // Senza calorie, ma con i kJ: le ricava.
        _riga(['8001234567893', 'Mela golden', '', 'en:italy', '', '218', '', '0.2', '12', '0.3', '']),
        // Senza energia, senza nome, o con un codice interno: fuori.
        _riga(['8001234567894', 'Sale fino', '', 'en:italy', '', '', '', '', '', '', '99']),
        _riga(['8001234567895', '', '', 'en:italy', '', '', '100', '', '', '', '']),
        _riga(['123', 'Prodotto interno', '', 'en:italy', '', '', '100', '', '', '', '']),
        // Una riga corta non fa cadere niente.
        '8001234567896\tTroncato',
      ]),
      db,
      adesso: DateTime.utc(2026, 11, 7),
    );
    catalogo = CatalogoCibo.da(db);
  });

  tearDown(() => catalogo.chiudi());

  test('tiene solo i prodotti italiani con nome, codice e calorie', () {
    expect(esito.righe, 8);
    expect(esito.prodotti, 3);
    expect(catalogo.prodotti, 3);
    expect(catalogo.generatoIl, formattaDataOra(DateTime.utc(2026, 11, 7)));
    expect(catalogo.perCodice('8001234567892'), isNull, reason: 'venduto solo in Francia');
    final mela = catalogo.perCodice('8001234567893')!;
    expect(mela.per100g.kcal, 52);
    expect(mela.marca, isNull);
    final pasta = catalogo.perCodice('8001234567890')!;
    expect(pasta.marca, 'Pastificio Rossi');
    expect(pasta.porzioneG, 80);
    expect(pasta.per100g.proteine, 12);
  });

  test('la ricerca trova inizi di parola, senza badare ad accenti e maiuscole', () {
    expect([for (final p in catalogo.cerca('pasta')) p.nome], ['Pasta di semola']);
    expect([for (final p in catalogo.cerca('FETTE integ')) p.nome], ['Fette biscottate integrali']);
    expect([for (final p in catalogo.cerca('mèla')) p.nome], ['Mela golden']);
    expect([for (final p in catalogo.cerca('forno')) p.nome], ['Fette biscottate integrali'], reason: 'anche per marca');
    expect(catalogo.cerca('pasta mela'), isEmpty, reason: 'servono tutte le parole');
    expect(catalogo.cerca('"):*'), isEmpty, reason: 'la punteggiatura non rompe la query');
  });
}
