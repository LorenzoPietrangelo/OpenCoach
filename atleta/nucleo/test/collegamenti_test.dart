import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:test/test.dart';

import 'supporto.dart';

void main() {
  late Ambiente ambiente;
  late PcCoach pc;
  late Telefono telefono;
  late String atletaId;

  setUp(() async {
    ambiente = Ambiente();
    pc = await ambiente.avviaCoach();
    atletaId = pc.nucleo.atleti.crea('Giulia Rossi').id;
    telefono = ambiente.telefono();
  });
  tearDown(() => ambiente.chiudi());

  CoachCollegato stato(int coachId) =>
      telefono.nucleo.collegamenti.cerca(coachId)!;

  Future<EsitoSync> sincronizza(int coachId) =>
      telefono.nucleo.sync.sincronizza(coachId);

  test(
    'revoca (401): sync sospesa, dati consultabili ed esportabili',
    () async {
      pc.pubblicaScheda(atletaId, 'Forza');
      final coach = await ambiente.abbina(telefono, pc, atletaId);
      final diario = telefono.nucleo.diario;
      final inviato = diario.salva(coach.id, allenamento(note: 'inviato'));
      await sincronizza(coach.id);
      final inCoda = diario.salva(coach.id, allenamento(note: 'in coda'));

      // Il coach revoca il telefono prima di aver ripubblicato il servizio.
      pc.congelaServizio();
      pc.nucleo.dispositivi.revoca(coach.dispositivoId);
      expect((await sincronizza(coach.id)).problema, ProblemaSync.revocato);
      final revocato = stato(coach.id);
      expect(revocato.stato, StatoCollegamento.revocato);
      expect(
        revocato.problema!.messaggio,
        'Il coach ha chiuso il collegamento.',
      );
      expect(telefono.cassaforte.nomi, isEmpty);
      expect(telefono.tor.chiavi, isEmpty);

      // Schede e log restano consultabili ed esportabili.
      expect(telefono.nucleo.schede.elenco(coach.id).single.titolo, 'Forza');
      expect(
        {for (final l in diario.elenco(coach.id)) l.id},
        {inviato.id, inCoda.id},
      );
      final esportato = telefono.nucleo.esporta(coachId: coach.id);
      final voce =
          (esportato['coach'] as List<Object?>).single as Map<String, Object?>;
      expect(voce['stato'], 'revocato');
      expect(voce['nome_coach'], 'Marco Bianchi');
      expect(voce['schede'] as List<Object?>, hasLength(1));
      expect(voce['log'] as List<Object?>, hasLength(2));
      expect(jsonEncode(esportato), isNot(contains('token')));

      // Non si sincronizza più.
      final connessioni = telefono.tor.connessioni;
      expect((await sincronizza(coach.id)).problema, ProblemaSync.revocato);
      expect(await telefono.nucleo.sync.sincronizzaTutti(), isEmpty);
      expect(telefono.tor.connessioni, connessioni);
    },
  );

  test('dopo una revoca un nuovo invito riprende il collegamento', () async {
    final coach = await ambiente.abbina(telefono, pc, atletaId);
    pc.spegni();
    final inCoda = telefono.nucleo.diario.salva(
      coach.id,
      allenamento(note: 'mai arrivato'),
    );
    await sincronizza(coach.id);
    pc.accendi();
    pc.congelaServizio();
    pc.nucleo.dispositivi.revoca(coach.dispositivoId);
    expect((await sincronizza(coach.id)).problema, ProblemaSync.revocato);
    pc.ripubblica();

    // Il coach manda un nuovo invito allo stesso atleta: la prima sync,
    // completa, porta al coach anche il log rimasto in coda.
    final ripreso = await ambiente.abbina(telefono, pc, atletaId);
    expect(ripreso.id, coach.id);
    expect(ripreso.stato, StatoCollegamento.attivo);
    expect(ripreso.dispositivoId, isNot(coach.dispositivoId));
    expect(ripreso.problema, isNull);
    expect(ripreso.logInAttesa, 0);
    expect(pc.log(inCoda.id)?.contenuto?['note'], 'mai arrivato');
    expect(telefono.nucleo.collegamenti.elenco(), hasLength(1));
  });

  test(
    "scollegarsi: il coach revoca il dispositivo, i dati restano finché l'atleta non li cancella",
    () async {
      pc.pubblicaScheda(atletaId, 'Forza');
      final coach = await ambiente.abbina(telefono, pc, atletaId);
      telefono.nucleo.diario.salva(coach.id, allenamento());
      await sincronizza(coach.id);

      expect(await telefono.nucleo.collegamenti.scollega(coach.id), isTrue);
      expect(pc.nucleo.dispositivi.attivo(atletaId), isNull);
      expect(stato(coach.id).stato, StatoCollegamento.scollegato);
      expect(telefono.cassaforte.nomi, isEmpty);
      expect(telefono.tor.chiavi, isEmpty);
      expect(telefono.nucleo.schede.elenco(coach.id), hasLength(1));
      expect(telefono.nucleo.diario.elenco(coach.id), hasLength(1));
      expect((await sincronizza(coach.id)).problema, ProblemaSync.scollegato);

      await telefono.nucleo.collegamenti.cancellaDati(coach.id);
      expect(telefono.nucleo.collegamenti.elenco(), isEmpty);
      expect(telefono.nucleo.schede.elenco(coach.id), isEmpty);
      expect(telefono.nucleo.diario.elenco(coach.id), isEmpty);
    },
  );

  test('scollegarsi con il coach irraggiungibile', () async {
    final coach = await ambiente.abbina(telefono, pc, atletaId);
    pc.spegni();
    expect(await telefono.nucleo.collegamenti.scollega(coach.id), isFalse);
    expect(stato(coach.id).stato, StatoCollegamento.scollegato);
    expect(telefono.cassaforte.nomi, isEmpty);
    expect(
      pc.nucleo.dispositivi.attivo(atletaId),
      isNotNull,
      reason: 'il coach dovrà revocarlo dal suo PC',
    );
  });

  test('scollegarsi non aspetta un coach che non risponde', () async {
    final coach = await ambiente.abbina(telefono, pc, atletaId);
    final collegamenti = telefono.nucleo.collegamenti
      ..attesaAvviso = const Duration(milliseconds: 200);
    final bloccata = Completer<void>();
    telefono.tor.primaDellaConnessione = () => bloccata.future;

    final inizio = DateTime.now();
    expect(await collegamenti.scollega(coach.id), isFalse);
    expect(DateTime.now().difference(inizio), lessThan(const Duration(seconds: 5)));
    expect(stato(coach.id).stato, StatoCollegamento.scollegato);
    expect(telefono.cassaforte.nomi, isEmpty);
    expect(telefono.tor.chiavi, isEmpty);

    // La connessione che si sblocca dopo non cambia niente.
    bloccata.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(telefono.tor.chiavi, isEmpty);
    expect(stato(coach.id).stato, StatoCollegamento.scollegato);
  });

  test('scollegarsi non aspetta la sync in corso con il coach', () async {
    final coach = await ambiente.abbina(telefono, pc, atletaId);
    // La prossima connessione resta appesa, come quando Tor non raggiunge il
    // PC del coach e arriva al timeout di 90 s.
    final bloccata = Completer<void>();
    telefono.tor.primaDellaConnessione = () => bloccata.future;
    final sync = telefono.nucleo.sync.sincronizza(coach.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(telefono.nucleo.sync.inCorso(coach.id), isTrue);

    final inizio = DateTime.now();
    expect(await telefono.nucleo.collegamenti.scollega(coach.id), isTrue);
    expect(DateTime.now().difference(inizio), lessThan(const Duration(seconds: 5)));
    // La sync interrotta non registra un guasto: l'atleta si è scollegato.
    expect((await sync).problema, ProblemaSync.scollegato);
    expect(stato(coach.id).stato, StatoCollegamento.scollegato);
    expect(pc.nucleo.dispositivi.attivo(atletaId), isNull);
    expect(telefono.tor.chiavi, isEmpty);

    // Più tardi la connessione appesa si sblocca: non cambia niente.
    bloccata.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(stato(coach.id).stato, StatoCollegamento.scollegato);
    expect(telefono.tor.chiavi, isEmpty);
  });

  test('i dati di un collegamento attivo non si cancellano', () async {
    final coach = await ambiente.abbina(telefono, pc, atletaId);
    await expectLater(
      telefono.nucleo.collegamenti.cancellaDati(coach.id),
      throwsA(isA<OperazioneNonAmmessa>()),
    );
  });

  test(
    'cambio di telefono: il nuovo riceve schede e storico, il vecchio no',
    () async {
      final scheda = pc.pubblicaScheda(atletaId, 'Forza');
      final vecchio = telefono;
      final coachVecchio = await ambiente.abbina(vecchio, pc, atletaId);
      final diarioVecchio = vecchio.nucleo.diario;
      final tenuto = diarioVecchio.salva(
        coachVecchio.id,
        allenamento(note: 'tenuto'),
      );
      final eliminato = diarioVecchio.salva(coachVecchio.id, allenamento());
      await vecchio.nucleo.sync.sincronizza(coachVecchio.id);
      diarioVecchio.elimina(coachVecchio.id, eliminato.id);
      await vecchio.nucleo.sync.sincronizza(coachVecchio.id);

      final nuovo = ambiente.telefono(nome: 'iPhone 15');
      final coachNuovo = await ambiente.abbina(nuovo, pc, atletaId);
      expect(coachNuovo.problema, isNull);
      expect(nuovo.nucleo.schede.elenco(coachNuovo.id).single.id, scheda);
      final storico = nuovo.nucleo.diario.elenco(coachNuovo.id).single;
      expect(storico.id, tenuto.id);
      expect(storico.contenuto?['note'], 'tenuto');
      expect(storico.inAttesa, isFalse);
      final lapide = nuovo.nucleo.diario.cerca(coachNuovo.id, eliminato.id)!;
      expect(lapide.eliminato, isTrue);
      expect(lapide.rev, 2);
      expect(lapide.inAttesa, isFalse);
      expect(pc.nucleo.dispositivi.attivo(atletaId)?.nome, 'iPhone 15');

      // Il servizio non autorizza più la chiave del vecchio telefono: dopo 3
      // sync l'app chiede un nuovo invito.
      for (final atteso in [
        ProblemaSync.coachIrraggiungibile,
        ProblemaSync.coachIrraggiungibile,
        ProblemaSync.chiaveNonAccettata,
      ]) {
        final esito = await vecchio.nucleo.sync.sincronizza(coachVecchio.id);
        expect(esito.problema, atteso);
      }

      // Dal nuovo telefono lo storico si modifica come gli altri log.
      nuovo.nucleo.diario.modifica(
        coachNuovo.id,
        tenuto.id,
        allenamento(note: 'dal nuovo telefono'),
      );
      await nuovo.nucleo.sync.sincronizza(coachNuovo.id);
      expect(pc.log(tenuto.id)?.rev, 2);
      expect(pc.log(tenuto.id)?.contenuto?['note'], 'dal nuovo telefono');
    },
  );

  test(
    'stesso coach come un altro atleta: il collegamento precedente si chiude',
    () async {
      final coach = await ambiente.abbina(telefono, pc, atletaId);
      final altroAtleta = pc.nucleo.atleti.crea('Giulia, seconda squadra').id;
      final invito = await telefono.nucleo.leggiInvito(
        await pc.invito(altroAtleta),
      );
      expect(invito.collegamentoAttuale?.id, coach.id);

      final nuovo = await invito.collega();
      expect(nuovo.id, isNot(coach.id));
      expect(nuovo.problema, isNull);
      expect(stato(coach.id).stato, StatoCollegamento.scollegato);
      expect(telefono.cassaforte.nomi, ['coach.${nuovo.id}']);
      expect(telefono.nucleo.collegamenti.attivi().single.id, nuovo.id);
    },
  );

  test('archivio senza chiavi né token: serve un nuovo invito', () async {
    final coach = await ambiente.abbina(telefono, pc, atletaId);
    // Per esempio un archivio ripristinato su un altro telefono, senza la
    // cassaforte.
    await telefono.cassaforte.elimina('coach.${coach.id}');
    await telefono.riapri();
    final connessioni = telefono.tor.connessioni;
    expect(
      (await sincronizza(coach.id)).problema,
      ProblemaSync.chiaveNonAccettata,
    );
    expect(telefono.tor.connessioni, connessioni);
  });

  test("l'archivio su file conserva i dati tra un avvio e l'altro", () async {
    final cartella = await Directory.systemTemp.createTemp('atleta_nucleo');
    addTearDown(() => cartella.delete(recursive: true));
    final percorso = '${cartella.path}${Platform.pathSeparator}archivio.db';

    var archivio = ArchivioAtleta.apri(percorso);
    archivio.db.execute(
      'INSERT INTO coach (indirizzo, nome_coach, nome_atleta, atleta_id, '
      'dispositivo_id, stato, conferma_in_sospeso, abbinato_il) '
      "VALUES ('x', 'Marco', 'Giulia', 'a', 'd', 'attivo', 0, "
      "'2026-10-18T12:00:00.000Z')",
    );
    archivio.chiudi();

    archivio = ArchivioAtleta.apri(percorso);
    expect(archivio.db.userVersion, 6);
    expect(
      archivio.db.select('SELECT nome_coach FROM coach').single['nome_coach'],
      'Marco',
    );
    archivio.chiudi();
  });
}
