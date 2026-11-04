import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';

import 'supporto.dart';

void main() {
  late CoachDiProva coach;

  setUp(() => coach = CoachDiProva());

  Map<String, Object?> log(
    DateTime quando,
    List<Map<String, Object?>> esercizi, {
    String? schedaId,
    String? sedutaId,
  }) => {
    'id': nuovoUuid(),
    'rev': 1,
    'eliminato': false,
    'scheda_id': schedaId,
    'scheda_revisione': schedaId == null ? null : 1,
    'seduta_id': sedutaId,
    'eseguito_il': formattaDataOra(quando),
    'esercizi': esercizi,
  };

  Map<String, Object?> esercizio(String nome, List<Map<String, Object?>> serie, {String? id}) => {
    'esercizio_id': id,
    'nome': nome,
    'serie': serie,
  };

  test('il massimale stimato tiene conto di ripetizioni e RIR', () {
    expect(stima1Rm(100, 8), closeTo(126.67, 0.01));
    // Due ripetizioni in riserva valgono come due in più.
    expect(stima1Rm(100, 8, rir: 2), closeTo(133.33, 0.01));
    expect(stima1Rm(100, 10), closeTo(133.33, 0.01));
    // Una singola a cedimento è già il massimale.
    expect(stima1Rm(100, 1), 100);
    // 5 × 100 vale più di 3 × 105: il carico da solo non lo direbbe.
    expect(stima1Rm(100, 5), greaterThan(stima1Rm(105, 3)));
  });

  test('il RIR scritto dal coach', () {
    expect(rirDaTesto('2'), 2);
    expect(rirDaTesto('1-2'), 1.5);
    expect(rirDaTesto('1,5'), 1.5);
    expect(rirDaTesto('alto'), isNull);
    expect(rirDaTesto(null), isNull);
  });

  test('conta solo le serie fatte, settimana per settimana', () async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    final oggi = coach.nucleo.contesto.adesso();
    await coach.riceviLog(atleta.id, [
      log(oggi.subtract(const Duration(days: 14)), [
        esercizio('Panca', [
          {'ripetizioni': 8, 'carico_kg': 60, 'completata': true},
        ]),
        esercizio('Plank', [
          {'durata_s': 30, 'completata': true},
          {'durata_s': 45, 'completata': true},
        ]),
        esercizio('Trazioni', [
          {'ripetizioni': 6, 'completata': true},
          {'ripetizioni': 9, 'completata': false},
        ]),
        esercizio('Sled', [
          {'carico_kg': 40, 'completata': true},
        ]),
      ]),
      log(oggi, [
        // Stesso esercizio, scritto in un altro modo.
        esercizio(' panca', [
          {'ripetizioni': 5, 'carico_kg': 70, 'completata': true},
          // Non fatta: non conta, anche se è la più pesante.
          {'ripetizioni': 5, 'carico_kg': 100, 'completata': false},
        ]),
      ]),
      // Senza serie fatte non è un allenamento.
      log(oggi, [
        esercizio('Squat', [
          {'ripetizioni': 8, 'carico_kg': 80, 'completata': false},
        ]),
      ]),
    ]);

    final storico = coach.nucleo.allenamenti.storico(atleta.id);
    expect(storico.totale, 2);
    expect(storico.settimane, hasLength(12));
    expect(storico.settimane.last.allenamenti, 1);
    expect(storico.settimane[storico.settimane.length - 3].allenamenti, 1);
    expect(storico.settimane[storico.settimane.length - 2].allenamenti, 0);

    final esercizi = {for (final e in storico.esercizi) e.nome.trim().toLowerCase(): e};
    expect(esercizi.keys, isNot(contains('squat')));
    expect(esercizi['panca']!.misura, MisuraEsercizio.stima1Rm);
    expect(esercizi['panca']!.punti.map((p) => p.valore), [closeTo(76, 0.01), closeTo(81.67, 0.01)]);
    expect(esercizi['sled']!.misura, MisuraEsercizio.carico);
    expect(esercizi['sled']!.punti.single.valore, 40);
    expect(esercizi['plank']!.misura, MisuraEsercizio.durata);
    expect(esercizi['plank']!.punti.single.valore, 45);
    expect(esercizi['trazioni']!.misura, MisuraEsercizio.ripetizioni);
    expect(esercizi['trazioni']!.punti.single.valore, 6);
    // Il più frequente per primo.
    expect(storico.esercizi.first.nome.trim().toLowerCase(), 'panca');
  });

  test('il coach sceglie la scheda, e la stima usa il suo RIR', () async {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    final oggi = coach.nucleo.contesto.adesso();
    final sedutaId = nuovoUuid();
    final schedaId = coach.nucleo.schede.crea(
      atleta.id,
      contenuto: {
        'titolo': 'Forza',
        'sedute': [
          {
            'id': sedutaId,
            'nome': 'Giorno A',
            'esercizi': [
              {
                'id': nuovoUuid(),
                'nome': 'Squat',
                'prescrizione': [
                  {'serie': 1, 'ripetizioni': '8', 'rir': '1-2'},
                  {'serie': 1, 'ripetizioni': '8', 'rir': '3'},
                ],
              },
            ],
          },
        ],
      },
    );
    coach.nucleo.schede.pubblica(schedaId);
    final pubblicato =
        (((coach.nucleo.schede.contenutoRevisione(schedaId, 1)!['sedute']! as List<Object?>).single!
                    as Map<String, Object?>)['esercizi']!
                as List<Object?>)
            .single!
        as Map<String, Object?>;
    await coach.riceviLog(atleta.id, [
      log(
        oggi,
        [
          esercizio(
            'Squat',
            [
              {'ripetizioni': 8, 'carico_kg': 100, 'completata': true},
              // La seconda serie, con più riserva, dà la stima più alta.
              {'ripetizioni': 8, 'carico_kg': 100, 'completata': true},
            ],
            id: pubblicato['id']! as String,
          ),
        ],
        schedaId: schedaId,
        sedutaId: sedutaId,
      ),
      log(oggi, [
        esercizio('Corsa', [
          {'durata_s': 1800, 'completata': true},
        ]),
      ]),
    ]);
    final allenamenti = coach.nucleo.allenamenti;

    final diScheda = allenamenti.storico(atleta.id, schedaId: schedaId);
    expect(diScheda.totale, 1);
    expect(diScheda.esercizi.single.nome, 'Squat');
    expect(diScheda.esercizi.single.punti.single.valore, closeTo(100 * (1 + 11 / 30), 0.01));

    final liberi = allenamenti.storico(atleta.id, soloLiberi: true);
    expect(liberi.totale, 1);
    expect(liberi.esercizi.single.nome, 'Corsa');

    expect(allenamenti.storico(atleta.id).totale, 2);
  });

  test('senza allenamenti non ci sono numeri', () {
    final atleta = coach.nucleo.atleti.crea('Giulia');
    final storico = coach.nucleo.allenamenti.storico(atleta.id);
    expect(storico.totale, 0);
    expect(storico.ultimo, isNull);
    expect(storico.esercizi, isEmpty);
    expect(storico.settimane.every((s) => s.allenamenti == 0), isTrue);
  });
}
