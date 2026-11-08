import 'dart:convert';
import 'dart:io';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:coach_nucleo/coach_nucleo.dart' show CatalogoCibo, generaCatalogo;
import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'supporto.dart';

const _pasta = AlimentoCibo(
  nome: 'Pasta di semola',
  marca: 'Pastificio',
  codice: '8001234567890',
  fonte: FonteCibo.openFoodFacts,
  per100g: ValoriCibo(kcal: 353, proteine: 12, carboidrati: 72, grassi: 1.5),
  porzioneG: 80,
);

const _pollo = AlimentoCibo(
  nome: 'Petto di pollo',
  fonte: FonteCibo.atleta,
  per100g: ValoriCibo(kcal: 110, proteine: 23),
);

void main() {
  late Ambiente ambiente;
  late PcCoach pc;
  late Telefono telefono;
  late String atletaId;
  late CoachCollegato coach;

  setUp(() async {
    ambiente = Ambiente();
    pc = await ambiente.avviaCoach();
    atletaId = pc.nucleo.atleti.crea('Giulia Rossi').id;
    telefono = ambiente.telefono();
    coach = await ambiente.abbina(telefono, pc, atletaId);
  });
  tearDown(() => ambiente.chiudi());

  RegistroCibo cibo() => telefono.nucleo.cibo;
  final oggi = DateTime(2026, 10, 18);
  final ieri = DateTime(2026, 10, 17);

  Future<EsitoSync> sincronizza() => telefono.nucleo.sync.sincronizza(coach.id);

  List<(int, int)> delCoach() => [
    for (final g in pc.nucleo.cibo.elenco(atletaId)) (g.giorno.day, g.totali.kcal.round()),
  ];

  test('voci aggiunte, corrette ed eliminate arrivano al coach', () async {
    cibo().aggiungi(oggi, 'pranzo', _pasta, 80);
    cibo().aggiungi(oggi, 'cena', _pollo, 150);
    cibo().aggiungi(ieri, 'colazione', _pasta, 50);
    final giornata = cibo().giornata(oggi);
    expect(giornata.voci, hasLength(2));
    expect(giornata.totali.kcal, closeTo(353 * 0.8 + 165, 0.01));
    expect(giornata.totali.proteine, closeTo(9.6 + 34.5, 0.01));

    await sincronizza();
    expect(delCoach(), [(17, 177), (18, 447)]);

    cibo().cambiaGrammi(oggi, giornata.voci.first.id, 100);
    cibo().elimina(ieri, cibo().giornata(ieri).voci.single.id);
    expect(cibo().elenco(), hasLength(1));
    await sincronizza();
    expect(delCoach(), [(18, 518)]);
  });

  test('valori fuori intervallo o giorno futuro non si salvano', () {
    expect(
      () => cibo().aggiungi(oggi, 'pranzo', _pasta, 0),
      throwsA(isA<OperazioneNonAmmessa>()),
    );
    expect(
      () => cibo().aggiungi(
        oggi,
        'pranzo',
        _pasta.conValori(const ValoriCibo(kcal: 2000)),
        100,
      ),
      throwsA(isA<OperazioneNonAmmessa>()),
    );
    expect(
      () => cibo().aggiungi(DateTime(2026, 10, 19), 'pranzo', _pasta, 80),
      throwsA(isA<OperazioneNonAmmessa>()),
    );
    expect(cibo().elenco(), isEmpty);
  });

  test('i cibi usati restano sul telefono: recenti, ricerca e codice', () {
    cibo().aggiungi(ieri, 'pranzo', _pasta, 80);
    cibo().aggiungi(oggi, 'pranzo', _pollo, 150);
    cibo().aggiungi(oggi, 'cena', _pasta, 90);
    final recenti = cibo().recenti();
    expect([for (final r in recenti) r.nome], ['Pasta di semola', 'Petto di pollo']);
    expect(recenti.first.porzioneG, 90);
    expect(recenti.first.fonte, FonteCibo.openFoodFacts);

    expect([for (final a in cibo().cercaSalvati('PETTO pol')) a.nome], ['Petto di pollo']);
    expect([for (final a in cibo().cercaSalvati('pastificio')) a.nome], ['Pasta di semola'], reason: 'anche per marca');
    expect(cibo().cercaSalvati('pasta pollo'), isEmpty);
    expect(cibo().salvatoPerCodice('8001234567890')!.nome, 'Pasta di semola');
    expect(cibo().salvatoPerCodice('8009999999999'), isNull);

    // Eliminare una voce non lo toglie dai cibi usati.
    cibo().elimina(oggi, cibo().giornata(oggi).voci.first.id);
    expect(cibo().recenti(), hasLength(2));
  });

  test('si cerca nel catalogo del PC del coach, per nome e per codice', () async {
    final ricerca = telefono.nucleo.ricercaCibo;
    await expectLater(
      ricerca.cerca('pasta'),
      throwsA(isA<ErroreCibo>().having((e) => e.guasto, 'guasto', GuastoCibo.senzaCatalogo)),
    );
    final db = sqlite3.openInMemory();
    await generaCatalogo(
      Stream.fromIterable([
        'code	product_name	brands	countries_tags	energy-kcal_100g	proteins_100g	serving_quantity',
        '8001234567890	Pasta di semola	Pastificio	en:italy	353	12	80',
      ]),
      db,
      adesso: DateTime.utc(2026, 10, 18),
    );
    pc.nucleo.catalogoCibo = CatalogoCibo.da(db);
    addTearDown(db.close);

    final trovati = await ricerca.cerca('semola');
    expect([for (final p in trovati) (p.nome, p.porzioneG)], [('Pasta di semola', 80)]);
    final pasta = AlimentoCibo.daProdotto((await ricerca.perCodice('8001234567890'))!);
    expect((pasta.fonte, pasta.per100g.kcal), (FonteCibo.openFoodFacts, 353));
    expect(await ricerca.perCodice('8009999999999'), isNull);

    pc.spegni();
    await expectLater(
      ricerca.cerca('pasta'),
      throwsA(isA<ErroreCibo>().having((e) => e.guasto, 'guasto', GuastoCibo.coachIrraggiungibile)),
    );
  });

  test('gli alimenti già nel diario diventano cibi usati con la migrazione', () {
    final cartella = Directory.systemTemp.createTempSync('opencoach-cibo-');
    addTearDown(() => cartella.deleteSync(recursive: true));
    final percorso = '${cartella.path}${Platform.pathSeparator}atleta.db';
    // Un archivio della versione 5, con una giornata nel diario.
    var archivio = ArchivioAtleta.apri(percorso);
    archivio.db.execute(
      "INSERT INTO giornate (giorno, id, rev, eliminato, voci, modificato_il) VALUES ('2026-10-17', ?, 1, 0, ?, '2026-10-17T12:00:00Z')",
      [
        nuovoUuid(),
        jsonEncode([
          VoceCibo(
            id: nuovoUuid(),
            pasto: 'pranzo',
            nome: 'Pasta di semola',
            codice: '8001234567890',
            fonte: FonteCibo.openFoodFacts,
            grammi: 80,
            per100g: const ValoriCibo(kcal: 353, proteine: 12),
          ).toJson(),
        ]),
      ],
    );
    archivio.db.execute('DROP TABLE alimenti');
    archivio.db.userVersion = 5;
    archivio.chiudi();

    archivio = ArchivioAtleta.apri(percorso);
    addTearDown(archivio.chiudi);
    final riga = archivio.db.select('SELECT * FROM alimenti').single;
    expect((riga['nome'], riga['codice'], riga['porzione']), ('Pasta di semola', '8001234567890', 80));
    expect(jsonDecode(riga['per_100g'] as String), {'kcal': 353, 'proteine': 12});
  });

  test('smettere di condividere toglie il cibo al coach; ricominciare lo rimanda', () async {
    cibo().aggiungi(oggi, 'pranzo', _pasta, 80);
    await sincronizza();
    expect(delCoach(), hasLength(1));

    cibo().condividi(coach.id, condividi: false);
    expect(telefono.nucleo.collegamenti.cerca(coach.id)!.condivideCibo, isFalse);
    await sincronizza();
    expect(delCoach(), isEmpty);

    cibo().condividi(coach.id, condividi: true);
    await sincronizza();
    expect(delCoach(), hasLength(1));
  });

  test("l'obiettivo del coach arriva, cambia e si toglie", () async {
    await sincronizza();
    expect(cibo().obiettivo(coach.id), isNull);
    pc.nucleo.cibo.fissaObiettivo(atletaId, const ObiettivoCibo(kcal: 2200, proteineG: 140));
    await sincronizza();
    expect(cibo().obiettivo(coach.id), const ObiettivoCibo(kcal: 2200, proteineG: 140));

    // Anche dopo uno stato completo, per esempio dopo un ripristino.
    pc.archivio.rigeneraEpoca();
    await sincronizza();
    expect(cibo().obiettivo(coach.id)!.kcal, 2200);

    pc.nucleo.cibo.fissaObiettivo(atletaId, null);
    await sincronizza();
    expect(cibo().obiettivo(coach.id), isNull);
  });

  test('dopo un ripristino del coach le giornate che mancano tornano in coda', () async {
    cibo().aggiungi(ieri, 'pranzo', _pasta, 80);
    cibo().aggiungi(oggi, 'pranzo', _pasta, 80);
    await sincronizza();
    pc.archivio.db.execute('DELETE FROM giornate');
    pc.archivio.rigeneraEpoca();
    await sincronizza();
    await sincronizza();
    expect(delCoach(), hasLength(2));
  });

  test("l'esportazione completa contiene il cibo", () {
    cibo().aggiungi(oggi, 'pranzo', _pasta, 80);
    final esportato = telefono.nucleo.esporta()['cibo']! as List<Object?>;
    expect((esportato.single! as Map<String, Object?>)['giorno'], '2026-10-18');
  });
}
