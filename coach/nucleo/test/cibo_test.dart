import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'supporto.dart';

Map<String, Object?> giornata(String id, int rev, String giorno, {num grammi = 100}) => {
  'id': id,
  'rev': rev,
  'eliminato': false,
  'giorno': giorno,
  'voci': [
    {
      'id': nuovoUuid(),
      'pasto': 'pranzo',
      'nome': 'Pasta di semola',
      'fonte': FonteCibo.openFoodFacts,
      'grammi': grammi,
      'per_100g': {'kcal': 353, 'proteine': 12, 'carboidrati': 72, 'grassi': 1.5},
    },
  ],
};

void main() {
  late Ambiente a;
  late String atletaId;
  late TelefonoFinto telefono;

  setUp(() async {
    a = await Ambiente.avvia();
    atletaId = a.nucleo.atleti.crea('Giulia').id;
    telefono = await a.abbinaTelefono(atletaId);
  });

  tearDown(() => a.chiudi());

  test('giornate salvate, corrette, eliminate e cancellate se l\'atleta smette di condividerle', () async {
    final lunedi = nuovoUuid();
    final martedi = nuovoUuid();
    var risposta = (await telefono.sincronizza(
      giornate: [
        giornata(lunedi, 1, '2026-11-02'),
        giornata(martedi, 1, '2026-11-03'),
        {'id': nuovoUuid(), 'rev': 1, 'eliminato': false, 'giorno': '2026-11-04', 'voci': []},
      ],
      ciboCondiviso: true,
    )).first;
    expect([for (final g in risposta.giornateAccettate!) g.id], [lunedi, martedi]);
    expect([for (final g in a.nucleo.cibo.elenco(atletaId)) g.giorno.day], [2, 3]);

    // Una rev più vecchia si conferma senza cambiare nulla.
    await telefono.sincronizza(giornate: [giornata(lunedi, 2, '2026-11-02', grammi: 80)]);
    risposta = (await telefono.sincronizza(giornate: [giornata(lunedi, 1, '2026-11-02', grammi: 500)])).single;
    expect(risposta.giornateAccettate!.single.rev, 1);
    expect(a.nucleo.cibo.elenco(atletaId).first.totali.kcal, closeTo(353 * 0.8, 0.01));

    await telefono.sincronizza(
      giornate: [
        {'id': martedi, 'rev': 2, 'eliminato': true},
      ],
    );
    expect(a.nucleo.cibo.elenco(atletaId), hasLength(1));

    // Lo stato completo elenca id e rev, anche delle lapidi.
    telefono.cursore = null;
    risposta = (await telefono.sincronizza()).single;
    expect({for (final g in risposta.giornate) g.id: g.rev}, {lunedi: 2, martedi: 2});

    await telefono.sincronizza(ciboCondiviso: false);
    expect(a.nucleo.cibo.elenco(atletaId), isEmpty);
  });

  test('lo stato completo pagina anche le giornate', () async {
    final piccolo = await Ambiente.avvia(budgetPagina: 200);
    addTearDown(piccolo.chiudi);
    final id = piccolo.nucleo.atleti.crea('Luca').id;
    final t = await piccolo.abbinaTelefono(id);
    final inviate = [for (var g = 1; g <= 9; g++) giornata(nuovoUuid(), 1, '2026-11-0$g')];
    await t.sincronizza(giornate: inviate, ciboCondiviso: true);
    t.cursore = null;
    final risposte = await t.sincronizza();
    expect(risposte.length, greaterThan(1));
    expect(
      {for (final r in risposte) ...r.giornate.map((g) => g.id)},
      {for (final g in inviate) g['id']},
    );
  });

  test('l\'obiettivo arriva quando cambia, e nello stato completo sempre', () async {
    var risposta = (await telefono.sincronizza()).single;
    expect(risposta.conObiettivoCibo, isTrue, reason: 'la prima sync è completa');
    expect(risposta.obiettivoCibo, isNull);
    expect((await telefono.sincronizza()).single.conObiettivoCibo, isFalse);

    const obiettivo = ObiettivoCibo(kcal: 2200, proteineG: 140);
    a.nucleo.cibo.fissaObiettivo(atletaId, obiettivo);
    expect(
      a.nucleo.sincronizzazione.haNovita(
        atletaId,
        RichiestaAttesa(epoca: telefono.epoca, cursore: telefono.cursore, attesaS: 0),
      ),
      isTrue,
    );
    risposta = (await telefono.sincronizza()).single;
    expect(risposta.obiettivoCibo, obiettivo);
    expect((await telefono.sincronizza()).single.conObiettivoCibo, isFalse);

    // Lo stesso obiettivo non è una novità.
    a.nucleo.cibo.fissaObiettivo(atletaId, obiettivo);
    expect((await telefono.sincronizza()).single.conObiettivoCibo, isFalse);

    a.nucleo.cibo.fissaObiettivo(atletaId, null);
    risposta = (await telefono.sincronizza()).single;
    expect(risposta.conObiettivoCibo, isTrue);
    expect(risposta.obiettivoCibo, isNull);
    expect(a.nucleo.cibo.obiettivo(atletaId), isNull);

    expect(
      () => a.nucleo.cibo.fissaObiettivo(atletaId, const ObiettivoCibo(kcal: 100)),
      throwsA(isA<OperazioneNonValida>()),
    );
  });

  test('il telefono del coach legge obiettivo e giornate, dalla più recente', () async {
    a.nucleo.cibo.fissaObiettivo(atletaId, const ObiettivoCibo(kcal: 2000));
    final prima = a.nucleo.vistaTelefono.impronta();
    await telefono.sincronizza(
      giornate: [giornata(nuovoUuid(), 1, '2026-11-02'), giornata(nuovoUuid(), 1, '2026-11-03')],
      ciboCondiviso: true,
    );
    expect(a.nucleo.vistaTelefono.impronta(), isNot(prima));
    final cibo = a.nucleo.vistaTelefono.cibo(atletaId);
    expect(cibo['obiettivo'], {'kcal': 2000});
    expect([for (final g in cibo['giornate']! as List<Object?>) (g! as Map)['giorno']], ['2026-11-03', '2026-11-02']);
    final vecchie = a.nucleo.vistaTelefono.cibo(atletaId, prima: '2026-11-03');
    expect((vecchie['giornate']! as List<Object?>).length, 1);
  });

  test("l'atleta cerca i cibi nel catalogo del PC, per nome e per codice", () async {
    final api = telefono.cliente;
    await expectLater(
      api.cercaCibo('pasta'),
      throwsA(isA<ErroreApi>().having((e) => e.codice, 'codice', CodiceErrore.catalogoAssente)),
    );

    final db = sqlite3.openInMemory();
    await generaCatalogo(
      Stream.fromIterable([
        'code	product_name	brands	countries_tags	energy-kcal_100g	proteins_100g',
        '8001234567890	Pasta di semola	Pastificio	en:italy	353	12',
        '8001234567891	Pasta integrale		en:italy	340	13',
      ]),
      db,
      adesso: DateTime.utc(2026, 11, 7),
    );
    a.nucleo.catalogoCibo = CatalogoCibo.da(db);
    addTearDown(() => a.nucleo.catalogoCibo!.chiudi());

    expect([for (final p in await api.cercaCibo('PASTA semo')) p.nome], ['Pasta di semola']);
    expect(await api.cercaCibo('pasta'), hasLength(2));
    expect(await api.cercaCibo(''), isEmpty);
    final pasta = (await api.ciboPerCodice('8001234567890'))!;
    expect((pasta.marca, pasta.per100g.kcal, pasta.per100g.proteine), ('Pastificio', 353, 12));
    expect(await api.ciboPerCodice('8009999999999'), isNull);
  });
}
