import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

import 'supporto.dart';

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

  DiarioAllenamenti diario() => telefono.nucleo.diario;

  CoachCollegato stato() => telefono.nucleo.collegamenti.cerca(coach.id)!;

  Future<EsitoSync> sincronizza() => telefono.nucleo.sync.sincronizza(coach.id);

  test(
    'salvare, modificare ed eliminare: la rev cresce e il log torna in coda',
    () async {
      final salvato = diario().salva(coach.id, allenamento(note: 'prima'));
      expect(salvato.rev, 1);
      expect(salvato.revConfermata, 0);
      expect(salvato.inAttesa, isTrue);
      expect(salvato.contenuto!['modificato_il'], isA<String>());
      expect(stato().logInAttesa, 1);

      expect((await sincronizza()).logConfermati, 1);
      expect(diario().cerca(coach.id, salvato.id)!.inAttesa, isFalse);
      expect(pc.log(salvato.id)?.rev, 1);

      final modificato = diario().modifica(
        coach.id,
        salvato.id,
        allenamento(note: 'dopo'),
      );
      expect(modificato.rev, 2);
      expect(modificato.revConfermata, 1);
      expect(modificato.inAttesa, isTrue);
      await sincronizza();
      expect(pc.log(salvato.id)?.rev, 2);
      expect(pc.log(salvato.id)?.contenuto?['note'], 'dopo');

      diario().elimina(coach.id, salvato.id);
      final eliminato = diario().cerca(coach.id, salvato.id)!;
      expect(eliminato.rev, 3);
      expect(eliminato.eliminato, isTrue);
      expect(eliminato.contenuto, isNull);
      expect(eliminato.perProtocollo, {
        'id': salvato.id,
        'rev': 3,
        'eliminato': true,
      });
      expect(diario().elenco(coach.id), isEmpty);
      await sincronizza();
      expect(pc.log(salvato.id), (rev: 3, eliminato: true, contenuto: null));
      expect(pc.nucleo.allenamenti.elenco(atletaId), isEmpty);
      expect(stato().logInAttesa, 0);

      expect(
        () => diario().modifica(coach.id, salvato.id, allenamento()),
        throwsA(isA<OperazioneNonAmmessa>()),
      );
    },
  );

  test('un log non valido non si salva', () {
    expect(
      () => diario().salva(coach.id, {
        ...allenamento(),
        'eseguito_il': '21/10/2026',
      }),
      throwsA(
        isA<LogNonValido>().having(
          (e) => e.errori.single,
          'errori',
          startsWith('eseguito_il'),
        ),
      ),
    );
    final esercizi = [
      for (var i = 0; i < 40; i++)
        {
          'nome': 'Esercizio $i',
          'note': 'n' * 2000,
          'serie': [
            {'completata': true},
          ],
        },
    ];
    expect(
      () => diario().salva(coach.id, {...allenamento(), 'esercizi': esercizi}),
      throwsA(isA<LogNonValido>()),
      reason: 'oltre 64 KiB',
    );
    expect(diario().elenco(coach.id), isEmpty);
  });

  test(
    'la conferma vale solo se la rev locale è ancora quella inviata',
    () async {
      final log = diario().salva(coach.id, allenamento(note: 'prima'));
      // Mentre la risposta viaggia, l'atleta modifica il log.
      pc.dopoRichiesteSync(
        1,
        () => diario().modifica(coach.id, log.id, allenamento(note: 'durante')),
      );
      final prima = pc.richiesteSync;
      final esito = await sincronizza();
      expect(esito.riuscita, isTrue);
      expect(
        pc.richiesteSync - prima,
        2,
        reason: 'la rev 2 parte nella stessa sync',
      );
      expect(pc.log(log.id)?.rev, 2);
      expect(pc.log(log.id)?.contenuto?['note'], 'durante');
      final dopo = diario().cerca(coach.id, log.id)!;
      expect(dopo.revConfermata, 2);
      expect(dopo.inAttesa, isFalse);
    },
  );

  test('log rifiutati: segnalati e non ritentati in automatico', () async {
    final log = diario().salva(coach.id, allenamento());
    // Sul PC del coach lo stesso id appartiene già a un altro atleta.
    final altro = pc.nucleo.atleti.crea('Altro').id;
    pc.archivio.db.execute(
      'INSERT INTO log (id, atleta_id, rev, eliminato, ricevuto_il) '
      "VALUES (?, ?, 1, 1, '2026-10-01T00:00:00.000Z')",
      [log.id, altro],
    );

    final esito = await sincronizza();
    expect(esito.riuscita, isTrue);
    expect(esito.logRifiutati, 1);
    final rifiutato = diario().rifiutati(coach.id).single;
    expect(rifiutato.id, log.id);
    expect(rifiutato.rifiuto, RifiutoLog.altroAtleta);
    expect(rifiutato.inAttesa, isFalse);
    expect(stato().logInAttesa, 0);
    expect(stato().logRifiutati, 1);

    // Senza il conflitto il coach lo accetterebbe, ma l'app non lo rimanda.
    pc.archivio.db.execute('DELETE FROM log WHERE id = ?', [log.id]);
    await sincronizza();
    expect(pc.log(log.id), isNull);

    // L'atleta lo ritenta a mano.
    diario().ritenta(coach.id, log.id);
    expect(stato().logInAttesa, 1);
    await sincronizza();
    expect(pc.log(log.id)?.rev, 1);
    expect(diario().rifiutati(coach.id), isEmpty);
  });

  test(
    'risposta persa: i log restano in coda e il coach non li duplica',
    () async {
      final log = diario().salva(coach.id, allenamento());
      pc.perdiProssimaRisposta = true;
      expect((await sincronizza()).problema, ProblemaSync.coachIrraggiungibile);
      expect(pc.log(log.id), isNotNull, reason: "il coach l'ha salvato");
      expect(diario().cerca(coach.id, log.id)!.inAttesa, isTrue);

      expect((await sincronizza()).logConfermati, 1);
      expect(pc.nucleo.allenamenti.elenco(atletaId), hasLength(1));
      expect(stato().logInAttesa, 0);
    },
  );

  test('più di 100 log in coda: lotti da 100 nella stessa sync', () async {
    for (var i = 0; i < 250; i++) {
      diario().salva(coach.id, allenamento());
    }
    final prima = pc.richiesteSync;
    final esito = await sincronizza();
    expect(esito.logConfermati, 250);
    expect(pc.richiesteSync - prima, 3);
    expect(pc.nucleo.allenamenti.elenco(atletaId), hasLength(250));
  });

  test('con il collegamento chiuso i log sono in sola lettura', () async {
    final log = diario().salva(coach.id, allenamento());
    await telefono.nucleo.collegamenti.scollega(coach.id);
    expect(
      () => diario().salva(coach.id, allenamento()),
      throwsA(isA<OperazioneNonAmmessa>()),
    );
    expect(
      () => diario().modifica(coach.id, log.id, allenamento()),
      throwsA(isA<OperazioneNonAmmessa>()),
    );
    expect(
      () => diario().elimina(coach.id, log.id),
      throwsA(isA<OperazioneNonAmmessa>()),
    );
    expect(diario().elenco(coach.id).single.id, log.id);
  });

  test('l\'ultima volta: le serie fatte nel log più recente con l\'esercizio', () {
    Map<String, Object?> conSerie(
      String eseguitoIl,
      String nome,
      List<Map<String, Object?>> serie, {
      String? esercizioId,
    }) => allenamento(eseguitoIl: eseguitoIl)
      ..['esercizi'] = [
        {'esercizio_id': esercizioId, 'nome': nome, 'note': '', 'serie': serie},
      ];
    Map<String, Object?> serie(int ripetizioni, num carico, {bool fatta = true}) => {
      'ripetizioni': ripetizioni,
      'carico_kg': carico,
      'completata': fatta,
    };
    final esercizioId = nuovoUuid();
    diario().salva(
      coach.id,
      conSerie('2026-10-01T08:00:00+02:00', 'Back squat', [serie(8, 70)], esercizioId: esercizioId),
    );
    diario().salva(
      coach.id,
      conSerie('2026-10-05T08:00:00+02:00', ' squat ', [serie(6, 80), serie(5, 80, fatta: false)]),
    );
    final eliminato = diario().salva(
      coach.id,
      conSerie('2026-10-08T08:00:00+02:00', 'Squat', [serie(1, 100)]),
    );
    diario().elimina(coach.id, eliminato.id);
    diario().salva(coach.id, conSerie('2026-10-20T08:00:00+02:00', 'Squat', [serie(3, 90)]));

    final dieci = DateTime.parse('2026-10-10T08:00:00+02:00');
    final ultime = diario().ultimaVolta(nome: 'SQUAT', prima: dieci);
    expect([for (final s in ultime) (s.ripetizioni, s.caricoKg)], [(6, 80)]);

    // Lo stesso esercizio della scheda vale anche con un altro nome.
    final perId = diario().ultimaVolta(esercizioId: esercizioId, nome: 'Panca', prima: dieci);
    expect([for (final s in perId) s.caricoKg], [70]);

    expect(diario().ultimaVolta(nome: 'Stacco', prima: dieci), isEmpty);
    expect(
      diario().ultimaVolta(nome: 'Squat', prima: DateTime.parse('2026-10-01T08:00:00+02:00')),
      isEmpty,
      reason: 'un log non è «l\'ultima volta» di se stesso',
    );
  });

  test('storico in ordine di esecuzione, eliminati esclusi', () {
    final vecchio = diario().salva(
      coach.id,
      allenamento(eseguitoIl: '2026-10-01T08:00:00+02:00'),
    );
    final recente = diario().salva(
      coach.id,
      allenamento(eseguitoIl: '2026-10-15T08:00:00+02:00'),
    );
    final eliminato = diario().salva(coach.id, allenamento());
    diario().elimina(coach.id, eliminato.id);
    expect(
      [for (final l in diario().elenco(coach.id)) l.id],
      [recente.id, vecchio.id],
    );
    expect(diario().inAttesa(coach.id), 3);
  });
}
