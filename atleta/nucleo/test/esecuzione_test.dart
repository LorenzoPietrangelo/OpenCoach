import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

import 'supporto.dart';

void main() {
  final sedutaId = nuovoUuid();
  final squat = nuovoUuid();
  final panca = nuovoUuid();
  final inizio = DateTime.utc(2026, 10, 21, 16, 30);

  final scheda = SchedaRicevuta(
    coachId: 1,
    id: nuovoUuid(),
    revisione: 3,
    archiviata: false,
    ricevutaIl: DateTime.utc(2026, 10, 18),
    daVedere: false,
    contenuto: {
      'titolo': 'Forza – blocco 2',
      'sedute': [
        {
          'id': sedutaId,
          'nome': 'Giorno A',
          'esercizi': [
            {
              'id': squat,
              'nome': 'Squat',
              'note': 'Pausa di 1 s in buca',
              'prescrizione': [
                {
                  'serie': 4,
                  'ripetizioni': '6-8',
                  'carico': '75% 1RM',
                  'recupero_s': 150,
                },
              ],
            },
            {
              'id': panca,
              'nome': 'Panca',
              'prescrizione': [
                {
                  'serie': 2,
                  'ripetizioni': '8',
                  'carico': '60 kg',
                  'recupero_s': 90,
                },
                {'serie': 1, 'ripetizioni': '12', 'carico': '50,5'},
              ],
            },
            {
              'id': nuovoUuid(),
              'nome': 'Plank',
              'prescrizione': [
                {'serie': 3, 'ripetizioni': '30 s'},
              ],
            },
            {'id': nuovoUuid(), 'nome': 'Mobilità'},
          ],
        },
      ],
    },
  );

  List<String> erroriDelLog(Map<String, Object?> contenuto) => validaLog({
    'id': nuovoUuid(),
    'rev': 1,
    'eliminato': false,
    ...contenuto,
  });

  test('una seduta prepara esercizi e serie dalla prescrizione', () {
    final allenamento = AllenamentoInCorso.daSeduta(
      scheda,
      sedutaId,
      inizio: inizio,
    );
    expect(allenamento.coachId, 1);
    expect(allenamento.libero, isFalse);
    expect(
      [for (final e in allenamento.esercizi) e.nome],
      ['Squat', 'Panca', 'Plank', 'Mobilità'],
    );
    expect(allenamento.esercizi.every((e) => e.previsto), isTrue);

    // Intervalli e percentuali restano come obiettivo, senza valori.
    final squatInCorso = allenamento.esercizi[0];
    expect(squatInCorso.noteCoach, 'Pausa di 1 s in buca');
    expect(squatInCorso.serie, hasLength(4));
    for (final serie in squatInCorso.serie) {
      expect(serie.ripetizioni, isNull);
      expect(serie.caricoKg, isNull);
      expect(serie.obiettivoRipetizioni, '6-8');
      expect(serie.obiettivoCarico, '75% 1RM');
      expect(serie.recupero, const Duration(seconds: 150));
      expect(serie.completata, isFalse);
    }

    // Anche i numeri semplici restano obiettivi: i valori li scrive l'atleta.
    final pancaInCorso = allenamento.esercizi[1];
    expect([for (final s in pancaInCorso.serie) s.ripetizioni], [null, null, null]);
    expect([for (final s in pancaInCorso.serie) s.obiettivoRipetizioni], ['8', '8', '12']);
    expect([for (final s in pancaInCorso.serie) s.caricoKg], [null, null, null]);
    expect(
      [for (final s in pancaInCorso.serie) s.recupero],
      [const Duration(seconds: 90), const Duration(seconds: 90), null],
    );

    // «30 s» è una durata.
    final plank = allenamento.esercizi[2];
    expect([for (final s in plank.serie) s.durataS], [null, null, null]);
    expect([for (final s in plank.serie) s.obiettivoDurataS], [30, 30, 30]);
    expect(plank.serie.first.ripetizioni, isNull);

    // Senza prescrizione c'è una serie vuota.
    expect(allenamento.esercizi[3].serie, hasLength(1));
  });

  test('il contenuto è un log valido, collegato alla seduta', () {
    final allenamento = AllenamentoInCorso.daSeduta(
      scheda,
      sedutaId,
      inizio: inizio,
    );
    allenamento.esercizi[0].serie.first
      ..ripetizioni = 7
      ..caricoKg = 100
      ..rpe = 8.5;
    allenamento.aggiungiEsercizio('Trazioni').serie.single.ripetizioni = 6;
    allenamento
      ..note = 'Buone sensazioni'
      ..rpe = 8;

    final contenuto = allenamento.contenuto(
      fine: inizio.add(const Duration(minutes: 65, seconds: 20)),
    );
    expect(erroriDelLog(contenuto), isEmpty);
    expect(contenuto['scheda_id'], scheda.id);
    expect(contenuto['scheda_revisione'], 3);
    expect(contenuto['seduta_id'], sedutaId);
    expect(contenuto['eseguito_il'], formattaDataOra(inizio));
    expect(contenuto['durata_min'], 65);
    expect(contenuto['rpe'], 8);
    final esercizi = contenuto['esercizi'] as List<Object?>;
    expect(esercizi, hasLength(5));
    final primo = esercizi.first as Map<String, Object?>;
    expect(primo['esercizio_id'], squat);
    expect(primo['nome'], 'Squat');
    expect((primo['serie'] as List<Object?>).first, {
      'ripetizioni': 7,
      'carico_kg': 100,
      'rpe': 8.5,
      'completata': true,
    });
    expect(esercizi.last, {
      'esercizio_id': null,
      'nome': 'Trazioni',
      'note': '',
      'serie': [
        {'ripetizioni': 6, 'completata': true},
      ],
    });
  });

  test("una serie aggiunta è vuota e mostra l'obiettivo dell'ultima", () {
    final allenamento = AllenamentoInCorso.daSeduta(
      scheda,
      sedutaId,
      inizio: inizio,
    );
    final pancaInCorso = allenamento.esercizi[1];
    pancaInCorso.serie.last.caricoKg = 52.5;
    final aggiunta = pancaInCorso.aggiungiSerie();
    expect(pancaInCorso.serie, hasLength(4));
    expect(aggiunta.ripetizioni, isNull);
    expect(aggiunta.caricoKg, isNull);
    expect(aggiunta.obiettivoRipetizioni, '12');
    expect(aggiunta.completata, isFalse);
  });

  test('allenamento libero, senza scheda', () {
    final allenamento = AllenamentoInCorso.libero(inizio: inizio);
    expect(allenamento.libero, isTrue);
    expect(allenamento.coachId, isNull);
    allenamento.aggiungiEsercizio('Corsa').serie.single.durataS = 1800;
    final contenuto = allenamento.contenuto(
      fine: inizio.add(const Duration(minutes: 32)),
    );
    expect(erroriDelLog(contenuto), isEmpty);
    expect(contenuto['scheda_id'], isNull);
    expect(contenuto['seduta_id'], isNull);
    expect(contenuto['durata_min'], 32);
  });

  test('seduta che non è nella scheda', () {
    expect(
      () => AllenamentoInCorso.daSeduta(scheda, nuovoUuid(), inizio: inizio),
      throwsArgumentError,
    );
  });

  test('dalla scheda del coach al log, e di nuovo dallo storico', () async {
    final ambiente = Ambiente();
    addTearDown(ambiente.chiudi);
    final pc = await ambiente.avviaCoach();
    final atletaId = pc.nucleo.atleti.crea('Giulia Rossi').id;
    pc.pubblicaScheda(atletaId, 'Forza');
    final telefono = ambiente.telefono();
    final coach = await ambiente.abbina(telefono, pc, atletaId);
    final ricevuta = telefono.nucleo.schede.elenco(coach.id).single;
    final seduta =
        (ricevuta.contenuto['sedute'] as List<Object?>).single
            as Map<String, Object?>;

    final inizio = ambiente.orologio.ora;
    final allenamento = AllenamentoInCorso.daSeduta(
      ricevuta,
      seduta['id'] as String,
      inizio: inizio,
    );
    for (final serie in allenamento.esercizi.single.serie) {
      serie
        ..ripetizioni = 7
        ..caricoKg = 100;
    }
    final log = telefono.nucleo.diario.salva(
      allenamento.coachId!,
      allenamento.contenuto(fine: inizio.add(const Duration(minutes: 50))),
    );
    await telefono.nucleo.sync.sincronizza(coach.id);

    // Il coach confronta il log con la prescrizione della revisione usata.
    final ricevuto = pc.nucleo.allenamenti.elenco(atletaId).single;
    expect(ricevuto.id, log.id);
    expect(ricevuto.revisioneNonAttuale, isFalse);
    expect(
      pc.nucleo.allenamenti.sedutaPrescritta(ricevuto)?['nome'],
      'Giorno A',
    );

    // Riaperto dallo storico e corretto, conserva data e durata.
    final riaperto = AllenamentoInCorso.daLog(
      telefono.nucleo.diario.cerca(coach.id, log.id)!,
    );
    expect(riaperto.sedutaId, seduta['id']);
    riaperto.esercizi.single.serie.first.ripetizioni = 5;
    final modificato = telefono.nucleo.diario.modifica(
      coach.id,
      log.id,
      riaperto.contenuto(),
    );
    expect(modificato.rev, 2);
    expect(modificato.contenuto?['durata_min'], 50);
    expect(modificato.contenuto?['eseguito_il'], log.contenuto?['eseguito_il']);
    await telefono.nucleo.sync.sincronizza(coach.id);
    expect(pc.log(log.id)?.rev, 2);
  });
}
