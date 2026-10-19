import 'dart:async';
import 'dart:convert';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:protocollo/protocollo.dart';
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

  Set<String> idSchede(int coachId, {bool archiviate = false}) => {
    for (final s in telefono.nucleo.schede.elenco(
      coachId,
      archiviate: archiviate,
    ))
      s.id,
  };

  CoachCollegato stato(int coachId) =>
      telefono.nucleo.collegamenti.cerca(coachId)!;

  /// Coach con pagine piccole e sei schede da circa 1 KB: lo stato completo
  /// richiede più pagine.
  Future<(PcCoach, String, List<String>)> coachConPagine() async {
    final grande = await ambiente.avviaCoach(
      nome: 'Paola Neri',
      budgetPagina: 3000,
    );
    final atleta = grande.nucleo.atleti.crea('Luca').id;
    final schede = [
      for (var i = 0; i < 6; i++)
        grande.pubblicaScheda(atleta, 'Scheda $i', note: 'n' * 1000),
    ];
    return (grande, atleta, schede);
  }

  test(
    'sync incrementale: schede nuove, cambiate, archiviate ed eliminate',
    () async {
      final a = pc.pubblicaScheda(atletaId, 'A');
      final b = pc.pubblicaScheda(atletaId, 'B');
      final coach = await ambiente.abbina(telefono, pc, atletaId);
      expect(idSchede(coach.id), {a, b});
      telefono.nucleo.schede.segnaVista(coach.id, a);
      telefono.nucleo.schede.segnaVista(coach.id, b);

      pc.nucleo.schede.salvaBozza(a, contenutoScheda('A, seconda versione'));
      pc.nucleo.schede.pubblica(a);
      pc.nucleo.schede.archivia(b);
      final c = pc.pubblicaScheda(atletaId, 'C');

      final esito = await telefono.nucleo.sync.sincronizza(coach.id);
      expect(esito.riuscita, isTrue);
      expect(esito.completa, isFalse);
      expect({for (final s in esito.schedeNuove) s.id}, {a, c});
      expect(idSchede(coach.id), {a, c});
      final nuovaA = telefono.nucleo.schede.cerca(coach.id, a)!;
      expect(nuovaA.revisione, 2);
      expect(nuovaA.titolo, 'A, seconda versione');
      expect(nuovaA.daVedere, isTrue, reason: 'è arrivata una nuova revisione');
      final archiviata = telefono.nucleo.schede.elenco(
        coach.id,
        archiviate: true,
      );
      expect(archiviata.single.id, b);
      expect(archiviata.single.daVedere, isFalse);

      pc.nucleo.schede.elimina(c);
      await telefono.nucleo.sync.sincronizza(coach.id);
      expect(idSchede(coach.id), {a});
      // Il cursore inviato dice al coach che la revisione è arrivata.
      expect(pc.nucleo.schede.cerca(a)!.revisioni.first.ricevutaIl, isNotNull);
    },
  );

  test("stato completo su più pagine, applicato solo dopo l'ultima", () async {
    final (grande, atleta, schede) = await coachConPagine();
    final invito = await telefono.nucleo.leggiInvito(
      await grande.invito(atleta),
    );
    // Il PC si spegne mentre invia la seconda pagina.
    grande.dopoRichiesteSync(2, grande.spegni);
    final coach = await invito.collega();
    expect(coach.problema, ProblemaSync.coachIrraggiungibile);
    expect(coach.confermaInSospeso, isFalse);
    expect(coach.cursore, isNull);
    expect(
      telefono.nucleo.schede.elenco(coach.id),
      isEmpty,
      reason: 'le pagine già ricevute non si applicano',
    );

    // La sync successiva ricomincia da capo.
    grande.accendi();
    final prima = grande.richiesteSync;
    final esito = await telefono.nucleo.sync.sincronizza(coach.id);
    expect(esito.riuscita, isTrue);
    expect(esito.completa, isTrue);
    expect(grande.richiesteSync - prima, greaterThan(2));
    expect(idSchede(coach.id), schede.toSet());
    expect(stato(coach.id).epoca, grande.archivio.epoca);
  });

  test('modifiche incrementali su più pagine', () async {
    final (grande, atleta, schede) = await coachConPagine();
    final coach = await ambiente.abbina(telefono, grande, atleta);
    for (final id in schede) {
      grande.nucleo.schede.pubblica(id);
    }
    final prima = grande.richiesteSync;
    final esito = await telefono.nucleo.sync.sincronizza(coach.id);
    expect(esito.riuscita, isTrue);
    expect(esito.completa, isFalse);
    expect(grande.richiesteSync - prima, greaterThan(1));
    expect(esito.schedeNuove, hasLength(6));
    expect(
      {for (final s in telefono.nucleo.schede.elenco(coach.id)) s.revisione},
      {2},
    );
  });

  test("epoca cambiata a metà dello stato completo: si ricomincia", () async {
    final (grande, atleta, schede) = await coachConPagine();
    final prima = (List.of(schede)..sort()).first;
    final invito = await telefono.nucleo.leggiInvito(
      await grande.invito(atleta),
    );
    // Dopo la prima pagina, che contiene la scheda con l'id più basso, il
    // coach la elimina e torna a un backup: nuova epoca.
    grande.dopoRichiesteSync(1, () {
      grande.nucleo.schede.elimina(prima);
      grande.archivio.rigeneraEpoca();
    });
    final coach = await invito.collega();
    expect(coach.problema, isNull);
    expect(coach.epoca, grande.archivio.epoca);
    expect(idSchede(coach.id), schede.toSet()..remove(prima));
  });

  test('dopo un ripristino del coach i log persi si reinviano', () async {
    final (grande, atleta, schede) = await coachConPagine();
    final coach = await ambiente.abbina(telefono, grande, atleta);
    final diario = telefono.nucleo.diario;
    final log = [
      for (var i = 0; i < 12; i++)
        diario.salva(coach.id, allenamento(note: 'l' * 300)),
    ];
    diario.modifica(coach.id, log[1].id, allenamento(note: 'modificato'));
    await telefono.nucleo.sync.sincronizza(coach.id);

    // Dopo l'ultimo backup il coach ha pubblicato una scheda e ricevuto un
    // log; poi ripristina il backup.
    final persa = grande.pubblicaScheda(atleta, 'Persa');
    final dopo = diario.salva(coach.id, allenamento(note: 'dopo il backup'));
    await telefono.nucleo.sync.sincronizza(coach.id);
    expect(idSchede(coach.id), {...schede, persa});
    final db = grande.archivio.db;
    db.execute('DELETE FROM log WHERE id = ?', [dopo.id]);
    db.execute('UPDATE log SET rev = 1, contenuto = ? WHERE id = ?', [
      jsonEncode(log[1].perProtocollo),
      log[1].id,
    ]);
    db.execute('DELETE FROM revisioni WHERE scheda_id = ?', [persa]);
    db.execute('DELETE FROM schede WHERE id = ?', [persa]);
    grande.archivio.rigeneraEpoca();

    final prima = grande.richiesteSync;
    final esito = await telefono.nucleo.sync.sincronizza(coach.id);
    expect(esito.riuscita, isTrue);
    expect(esito.completa, isTrue);
    expect(esito.logRimessiInCoda, 2);
    expect(esito.logConfermati, 2);
    expect(
      grande.richiesteSync - prima,
      greaterThan(2),
      reason: 'stato completo su più pagine, poi il reinvio',
    );
    // Il telefono segue il coach per le schede...
    expect(idSchede(coach.id), schede.toSet());
    // ...e il coach riceve di nuovo i log che aveva perso.
    expect(grande.log(dopo.id)?.rev, 1);
    expect(grande.log(log[1].id)?.rev, 2);
    expect(grande.log(log[1].id)?.contenuto?['note'], 'modificato');
    expect(stato(coach.id).logInAttesa, 0);
    expect(stato(coach.id).epoca, grande.archivio.epoca);
  });

  test('troppe richieste (429): aspetta Retry-After e continua', () async {
    final coach = await ambiente.abbina(telefono, pc, atletaId);
    // Conferma e prima sync hanno già fatto due richieste in questo minuto.
    for (var i = 0; i < 30; i++) {
      expect(
        (await telefono.nucleo.sync.sincronizza(coach.id)).riuscita,
        isTrue,
      );
    }
    final attesa = ambiente.orologio.attese.single;
    expect(attesa, greaterThan(Duration.zero));
    expect(attesa, lessThanOrEqualTo(const Duration(minutes: 1)));
  });

  test('errore interno del coach: ritenta con attesa crescente', () async {
    final coach = await ambiente.abbina(telefono, pc, atletaId);
    // Una revisione mancante nell'archivio del coach fa rispondere 500.
    final rovinata = pc.pubblicaScheda(atletaId, 'Rovinata');
    pc.archivio.db.execute('DELETE FROM revisioni WHERE scheda_id = ?', [
      rovinata,
    ]);
    final esito = await telefono.nucleo.sync.sincronizza(coach.id);
    expect(esito.problema, ProblemaSync.coachOccupato);
    expect(ambiente.orologio.attese, const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
    ]);
    expect(pc.registro, isNotEmpty);

    pc.nucleo.schede.elimina(rovinata);
    expect((await telefono.nucleo.sync.sincronizza(coach.id)).riuscita, isTrue);
  });

  test('lotto oltre i limiti del coach (413): si divide', () async {
    final largo = ambiente.telefono(logPerRichiesta: 150);
    final coach = await ambiente.abbina(largo, pc, atletaId);
    for (var i = 0; i < 120; i++) {
      largo.nucleo.diario.salva(coach.id, allenamento());
    }
    final esito = await largo.nucleo.sync.sincronizza(coach.id);
    expect(esito.riuscita, isTrue);
    expect(esito.logConfermati, 120);
    expect(pc.nucleo.allenamenti.elenco(atletaId), hasLength(120));
    expect(largo.nucleo.diario.inAttesa(coach.id), 0);
  });

  test(
    "stati per l'interfaccia: offline, Tor, coach irraggiungibile",
    () async {
      final coach = await ambiente.abbina(telefono, pc, atletaId);
      final riuscita = stato(coach.id).ultimaSync;
      ambiente.orologio.avanza(const Duration(hours: 1));
      telefono.nucleo.diario.salva(coach.id, allenamento());
      Future<ProblemaSync?> problema() async =>
          (await telefono.nucleo.sync.sincronizza(coach.id)).problema;

      telefono.rete.connessa = false;
      expect(await problema(), ProblemaSync.offline);
      expect(
        stato(coach.id).problema!.messaggio,
        'Sei offline. Gli allenamenti restano salvati sul telefono.',
      );
      telefono.rete.connessa = true;

      telefono.tor.nonParte = true;
      expect(await problema(), ProblemaSync.torNonParte);
      telefono.tor.nonParte = false;

      for (final guasto in <Object>[
        const ErroreSocks(ErroreSocks.descrittoreNonTrovato),
        const ErroreSocks(ErroreSocks.introduzioneFallita),
        const ErroreSocks(ErroreSocks.rendezvousFallito),
        const ErroreSocks(ErroreSocks.introduzioneScaduta),
        TimeoutException('connessione'),
      ]) {
        telefono.tor.guasti.add(guasto);
        expect(
          await problema(),
          ProblemaSync.coachIrraggiungibile,
          reason: '$guasto',
        );
      }
      final dopoGuasti = stato(coach.id);
      expect(
        dopoGuasti.problema!.messaggio,
        'Il PC del coach non è raggiungibile. '
        'I tuoi allenamenti partiranno appena tornerà acceso.',
      );
      expect(
        dopoGuasti.ultimaSync,
        riuscita,
        reason: "resta l'ultima riuscita",
      );
      expect(dopoGuasti.logInAttesa, 1);

      expect(await problema(), isNull);
      final dopo = stato(coach.id);
      expect(dopo.problema, isNull);
      expect(dopo.ultimaSync, ambiente.orologio.ora);
      expect(dopo.logInAttesa, 0);
    },
  );

  test('F4 o F5 in 3 sync consecutive: chiave non accettata', () async {
    final coach = await ambiente.abbina(telefono, pc, atletaId);
    Future<ProblemaSync?> problema() async =>
        (await telefono.nucleo.sync.sincronizza(coach.id)).problema;

    // Due rifiuti della chiave, poi una risposta del coach: si ricomincia.
    telefono.tor.guasti.addAll(const [
      ErroreSocks(ErroreSocks.autorizzazioneErrata),
      ErroreSocks(ErroreSocks.autorizzazioneMancante),
    ]);
    expect(await problema(), ProblemaSync.coachIrraggiungibile);
    expect(await problema(), ProblemaSync.coachIrraggiungibile);
    expect(await problema(), isNull);

    // Il coach toglie la chiave del telefono dal servizio. Un PC spento in
    // mezzo non azzera il conteggio.
    pc.nucleo.dispositivi.revoca(coach.dispositivoId);
    expect(await problema(), ProblemaSync.coachIrraggiungibile);
    pc.spegni();
    expect(await problema(), ProblemaSync.coachIrraggiungibile);
    pc.accendi();
    expect(await problema(), ProblemaSync.coachIrraggiungibile);
    expect(await problema(), ProblemaSync.chiaveNonAccettata);
    final dopo = stato(coach.id);
    expect(
      dopo.problema!.messaggio,
      'Il collegamento con il coach non è più valido. Chiedi un nuovo invito.',
    );
    expect(dopo.stato, StatoCollegamento.attivo);
  });

  test("app troppo vecchia (426): chiede di aggiornare", () async {
    final coach = await ambiente.abbina(telefono, pc, atletaId);
    telefono.nucleo.diario.salva(coach.id, allenamento());
    pc.archivio.scriviImpostazione(Impostazioni.versioneAppMinima, '1.1.0');
    final esito = await telefono.nucleo.sync.sincronizza(coach.id);
    expect(esito.problema, ProblemaSync.aggiornaApp);
    expect(
      esito.problema!.messaggio,
      "Aggiorna l'app per continuare a sincronizzare.",
    );
    expect(esito.problema!.temporaneo, isFalse);
    expect(stato(coach.id).logInAttesa, 1);
    expect(pc.nucleo.allenamenti.elenco(atletaId), isEmpty);
  });

  test('risposta non conforme al protocollo: non applica nulla', () async {
    final coach = await ambiente.abbina(telefono, pc, atletaId);
    final cursore = stato(coach.id).cursore;
    final id = pc.pubblicaScheda(atletaId, 'Senza sedute');
    pc.archivio.db.execute(
      'UPDATE revisioni SET contenuto = ? WHERE scheda_id = ?',
      [
        jsonEncode({'titolo': 'Senza sedute', 'sedute': <Object?>[]}),
        id,
      ],
    );
    final esito = await telefono.nucleo.sync.sincronizza(coach.id);
    expect(esito.problema, ProblemaSync.erroreImprevisto);
    expect(telefono.nucleo.schede.elenco(coach.id), isEmpty);
    expect(stato(coach.id).cursore, cursore);
    expect(telefono.registro, isNotEmpty);
  });

  test('più coach: schede e log separati, sync indipendenti', () async {
    final altro = await ambiente.avviaCoach(nome: 'Anna Verdi');
    final atletaAltro = altro.nucleo.atleti.crea('Giulia R.').id;
    pc.pubblicaScheda(atletaId, 'Forza');
    altro.pubblicaScheda(atletaAltro, 'Corsa');
    final marco = await ambiente.abbina(telefono, pc, atletaId);
    final anna = await ambiente.abbina(telefono, altro, atletaAltro);

    expect(
      [for (final c in telefono.nucleo.collegamenti.elenco()) c.nomeCoach],
      ['Anna Verdi', 'Marco Bianchi'],
    );
    expect(telefono.nucleo.schede.elenco(marco.id).single.titolo, 'Forza');
    expect(telefono.nucleo.schede.elenco(anna.id).single.titolo, 'Corsa');
    expect(telefono.tor.chiavi.keys.toSet(), {pc.indirizzo, altro.indirizzo});

    final diario = telefono.nucleo.diario;
    final perMarco = diario.salva(marco.id, allenamento(note: 'per Marco'));
    final perAnna = diario.salva(anna.id, allenamento(note: 'per Anna'));
    altro.spegni();
    final esiti = await telefono.nucleo.sync.sincronizzaTutti();
    expect(
      {for (final e in esiti) e.coachId: e.problema},
      {marco.id: null, anna.id: ProblemaSync.coachIrraggiungibile},
    );
    expect(pc.log(perMarco.id), isNotNull);
    expect(diario.inAttesa(anna.id), 1);

    altro.accendi();
    await telefono.nucleo.sync.sincronizzaTutti();
    expect(altro.log(perAnna.id), isNotNull);
    expect(altro.log(perMarco.id), isNull);
    expect(pc.log(perAnna.id), isNull);
    expect(diario.elenco(marco.id).single.id, perMarco.id);
  });
}
