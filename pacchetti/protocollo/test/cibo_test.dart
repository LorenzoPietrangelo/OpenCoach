import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

Map<String, Object?> _voce({Object? grammi = 24, Map<String, Object?>? per100g}) => {
  'id': nuovoUuid(),
  'pasto': 'colazione',
  'nome': 'Fette biscottate integrali',
  'codice': '8001234567890',
  'fonte': FonteCibo.openFoodFacts,
  'grammi': grammi,
  'per_100g': per100g ?? {'kcal': 395, 'proteine': 13, 'carboidrati': 68, 'grassi': 5.6},
};

Map<String, Object?> _giornata(List<Map<String, Object?>> voci) => {
  'id': nuovoUuid(),
  'rev': 1,
  'eliminato': false,
  'giorno': '2026-11-07',
  'voci': voci,
  'modificato_il': '2026-11-07T08:10:00+01:00',
};

void main() {
  group('validaGiornata', () {
    test('accetta una giornata valida e una eliminata', () {
      expect(validaGiornata(_giornata([_voce()])), isEmpty);
      expect(validaGiornata({'id': nuovoUuid(), 'rev': 2, 'eliminato': true}), isEmpty);
    });

    test('rifiuta valori fuori intervallo e campi mancanti', () {
      expect(validaGiornata(_giornata([])), isNotEmpty);
      expect(validaGiornata(_giornata([_voce(grammi: 0)])), isNotEmpty);
      expect(validaGiornata(_giornata([_voce(per100g: {'kcal': 1000})])), isNotEmpty);
      expect(validaGiornata(_giornata([_voce(per100g: {'kcal': 100, 'grassi': 120})])), isNotEmpty);
      expect(validaGiornata(_giornata([{..._voce()}..remove('per_100g')])), isNotEmpty);
      expect(validaGiornata(_giornata([{..._voce(), 'pasto': 'merenda'}])), isNotEmpty);
      expect(validaGiornata(_giornata([{..._voce(), 'codice': '12AB'}])), isNotEmpty);
      final voce = _voce();
      expect(validaGiornata(_giornata([voce, voce])), isNotEmpty);
    });

    test('i macronutrienti sono facoltativi', () {
      expect(validaGiornata(_giornata([_voce(per100g: {'kcal': 50})])), isEmpty);
    });
  });

  test('i totali sommano le porzioni', () {
    final giornata = GiornataCibo.fromJson(
      _giornata([
        _voce(),
        {..._voce(grammi: 150, per100g: {'kcal': 110, 'proteine': 23}), 'pasto': 'pranzo'},
      ]),
    );
    final totali = giornata.totali;
    expect(totali.kcal, closeTo(395 * 0.24 + 165, 0.001));
    expect(totali.proteine, closeTo(13 * 0.24 + 34.5, 0.001));
    expect(totali.grassi, closeTo(5.6 * 0.24, 0.001));
    expect(giornata.delPasto('pranzo'), hasLength(1));
  });

  group('obiettivo', () {
    test('validazione', () {
      expect(validaObiettivoCibo({'kcal': 2200, 'proteine_g': 140}), isEmpty);
      expect(validaObiettivoCibo({'kcal': 100}), isNotEmpty);
      expect(validaObiettivoCibo({'proteine_g': 140}), isNotEmpty);
    });

    test('nella risposta della sync distingue assente, tolto e fissato', () {
      Map<String, Object?> base() => const RispostaSync(
        epoca: 'e',
        completo: false,
        logAccettati: [],
        logRifiutati: [],
        schede: [],
        schedeEliminate: [],
        log: [],
        cursore: 'c',
        altro: false,
      ).toJson();

      final assente = RispostaSync.fromJson(base());
      expect(assente.conObiettivoCibo, isFalse);
      expect(assente.giornateAccettate, isNull);

      final tolto = RispostaSync.fromJson({...base(), 'obiettivo_cibo': null});
      expect(tolto.conObiettivoCibo, isTrue);
      expect(tolto.obiettivoCibo, isNull);

      final fissato = RispostaSync.fromJson({
        ...base(),
        'obiettivo_cibo': {'kcal': 2200, 'grassi_g': 70},
        'giornate_accettate': [
          {'id': 'a', 'rev': 2},
        ],
      });
      expect(fissato.obiettivoCibo, const ObiettivoCibo(kcal: 2200, grassiG: 70));
      expect(fissato.giornateAccettate!.single.rev, 2);
      expect(RispostaSync.fromJson(fissato.toJson()).obiettivoCibo, fissato.obiettivoCibo);

      expect(
        () => RispostaSync.fromJson({...base(), 'obiettivo_cibo': {'kcal': 'tanto'}}),
        throwsFormatException,
      );
    });
  });

  group('prodottoDaOff', () {
    test('nome italiano, prima marca, valori per 100 g e porzione', () {
      final p = prodottoDaOff({
        'code': '8001234567890',
        'product_name': 'Rusks',
        'product_name_it': 'Fette biscottate integrali',
        'brands': 'Forno Rossi, Gruppo Verdi',
        'serving_quantity': '8',
        'nutriments': {
          'energy-kcal_100g': 395,
          'proteins_100g': 13,
          'carbohydrates_100g': '68',
          'fat_100g': 5.6,
        },
      })!;
      expect(p.nome, 'Fette biscottate integrali');
      expect(p.marca, 'Forno Rossi');
      expect(p.porzioneG, 8);
      expect(p.per100g.carboidrati, 68);
      expect(validaProdottoCibo(p.toJson()), isEmpty);
      expect(ProdottoCibo.fromJson(p.toJson()).nome, p.nome);
    });

    test('senza kcal le ricava dai kJ; senza energia, nome o codice è nulla', () {
      expect(
        prodottoDaOff({
          'code': '80012345',
          'product_name': 'Mela',
          'brands': ['', ' Melinda'],
          'nutriments': {'energy-kj_100g': '218'},
        })!.per100g.kcal,
        52,
      );
      expect(prodottoDaOff({'code': '80012345', 'product_name': 'Sale'}), isNull);
      expect(prodottoDaOff({'code': '80012345', 'nutriments': {'energy-kcal_100g': 10}}), isNull);
      expect(prodottoDaOff({'code': '123', 'product_name': 'X', 'nutriments': {'energy-kcal_100g': 10}}), isNull);
    });

    test('scarta i macronutrienti fuori intervallo', () {
      final p = prodottoDaOff({
        'code': '80012345',
        'product_name': 'Strano',
        'nutriments': {'energy-kcal_100g': 120, 'fat_100g': 400, 'proteins_100g': -2},
      })!;
      expect(p.per100g.grassi, isNull);
      expect(p.per100g.proteine, isNull);
    });
  });
}
