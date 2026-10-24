import 'dart:async';

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

  test('flusso completo: invito, conferma e prima sync completa', () async {
    final schedaId = pc.pubblicaScheda(atletaId, 'Forza – blocco 2');
    final testo = await pc.invito(atletaId);

    final invito = await telefono.nucleo.leggiInvito(testo);
    expect(invito.nomeCoach, 'Marco Bianchi');
    expect(invito.collegamentoAttuale, isNull);
    // GET /v1/info passa con la chiave d'invito, che poi Tor non tiene
    // mentre l'atleta decide.
    final chiaveInvito = await CoppiaX25519.daPrivata(
      decodificaChiave32(invito.invito.chiave)!,
    );
    expect(telefono.tor.chiaviUsate, [chiaveInvito.pubblicaBase32]);
    expect(telefono.tor.chiavi, isEmpty);

    final coach = await invito.collega();
    expect(coach.nomeCoach, 'Marco Bianchi');
    expect(coach.nomeAtleta, 'Giulia Rossi');
    expect(coach.atletaId, atletaId);
    expect(coach.stato, StatoCollegamento.attivo);
    expect(coach.confermaInSospeso, isFalse);
    expect(coach.problema, isNull);
    expect(coach.ultimaSync, ambiente.orologio.ora);
    expect(coach.epoca, pc.archivio.epoca);

    final dispositivo = pc.nucleo.dispositivi.attivo(atletaId)!;
    expect(dispositivo.nome, 'Pixel 8');
    expect(coach.dispositivoId, dispositivo.id);
    // Dopo la conferma il servizio autorizza solo la chiave del telefono.
    final chiave = await CoppiaX25519.daPrivata(
      telefono.tor.chiavi[pc.indirizzo]!,
    );
    expect(pc.nucleo.chiaviAutorizzate(), [chiave.pubblicaBase32]);
    // Abbinamento con la chiave d'invito, conferma e sync con quella del
    // dispositivo.
    expect(telefono.tor.chiaviUsate, [
      chiaveInvito.pubblicaBase32,
      chiaveInvito.pubblicaBase32,
      chiave.pubblicaBase32,
    ]);
    expect(pc.eventi.whereType<AbbinamentoConfermato>(), hasLength(1));
    expect(pc.nucleo.inviti.inCorso(atletaId), isNull);
    // Chiave e token stanno solo nella cassaforte.
    expect(telefono.cassaforte.nomi, ['coach.${coach.id}']);

    final scheda = telefono.nucleo.schede.elenco(coach.id).single;
    expect(scheda.id, schedaId);
    expect(scheda.titolo, 'Forza – blocco 2');
    expect(scheda.daVedere, isTrue);
  });

  test('codici che non sono inviti o di versione sconosciuta', () async {
    await expectLater(
      telefono.nucleo.leggiInvito('https://esempio.it/invito'),
      throwsA(erroreAbbinamento(ProblemaAbbinamento.codiceNonValido)),
    );
    final testo = await pc.invito(atletaId);
    await expectLater(
      telefono.nucleo.leggiInvito(testo.replaceFirst('v=1', 'v=2')),
      throwsA(erroreAbbinamento(ProblemaAbbinamento.versioneInvito)),
    );
    expect(telefono.tor.connessioni, 0);
  });

  test('invito annullato o scaduto: non più valido', () async {
    // Annullato: il coach toglie la chiave d'invito dal servizio e Tor dà
    // F5 da tutte le directory, anche dopo quasi un minuto.
    final annullato = await pc.nucleo.inviti.crea(atletaId);
    pc.nucleo.inviti.annulla(annullato.id);
    await expectLater(
      telefono.nucleo.leggiInvito(annullato.uri!.toString()),
      throwsA(erroreAbbinamento(ProblemaAbbinamento.invitoNonValido)),
    );
    expect(ambiente.orologio.attese, const [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ]);
    expect(telefono.tor.connessioni, 4);
    expect(telefono.tor.chiavi, isEmpty);

    // Scaduto mentre l'atleta decide: il servizio non è ancora stato
    // ripubblicato e il coach risponde 410.
    final invito = await telefono.nucleo.leggiInvito(await pc.invito(atletaId));
    pc.congelaServizio();
    ambiente.orologio.avanza(const Duration(days: 8));
    await expectLater(
      invito.collega(),
      throwsA(erroreAbbinamento(ProblemaAbbinamento.invitoNonValido)),
    );
    expect(telefono.nucleo.collegamenti.elenco(), isEmpty);
    expect(telefono.tor.chiavi, isEmpty);
  });

  test(
    "directory con il descrittore di prima dell'invito: si ritenta",
    () async {
      final testo = await pc.invito(atletaId);
      // Le prime due directory interrogate non hanno ancora il descrittore
      // con la chiave d'invito.
      telefono.tor.guasti.addAll(const [
        ErroreSocks(ErroreSocks.autorizzazioneErrata),
        ErroreSocks(ErroreSocks.autorizzazioneErrata),
      ]);
      final invito = await telefono.nucleo.leggiInvito(testo);
      expect(invito.nomeCoach, 'Marco Bianchi');
      expect(ambiente.orologio.attese, const [
        Duration(seconds: 5),
        Duration(seconds: 15),
      ]);
      expect(telefono.tor.connessioni, 3);
      expect((await invito.collega()).problema, isNull);
    },
  );

  test('invito già usato da un altro telefono: 409', () async {
    final testo = await pc.invito(atletaId);
    final uri = UriInvito.analizza(testo);
    // Un altro telefono ha già mandato l'abbinamento con la sua chiave.
    pc.nucleo.abbinamento.abbina(
      RichiestaAbbinamento(
        invitoId: uri.id,
        segreto: uri.segreto,
        chiaveDispositivo: (await CoppiaX25519.genera()).pubblicaBase32,
        dispositivo: const DatiDispositivo(
          nome: 'Sconosciuto',
          piattaforma: 'ios',
          versioneApp: '1.0.0',
        ),
      ),
    );
    final invito = await telefono.nucleo.leggiInvito(testo);
    await expectLater(
      invito.collega(),
      throwsA(erroreAbbinamento(ProblemaAbbinamento.invitoInUso)),
    );
    expect(pc.eventi.whereType<InvitoContestato>(), hasLength(1));
    expect(telefono.nucleo.collegamenti.elenco(), isEmpty);
  });

  test('rete assente, Tor che non parte, coach spento', () async {
    final testo = await pc.invito(atletaId);

    telefono.rete.connessa = false;
    await expectLater(
      telefono.nucleo.leggiInvito(testo),
      throwsA(erroreAbbinamento(ProblemaAbbinamento.offline)),
    );
    telefono.rete.connessa = true;

    telefono.tor.nonParte = true;
    await expectLater(
      telefono.nucleo.leggiInvito(testo),
      throwsA(erroreAbbinamento(ProblemaAbbinamento.torNonParte)),
    );
    telefono.tor.nonParte = false;

    pc.spegni();
    await expectLater(
      telefono.nucleo.leggiInvito(testo),
      throwsA(erroreAbbinamento(ProblemaAbbinamento.coachIrraggiungibile)),
    );
    expect(telefono.tor.chiavi, isEmpty);

    // Acceso il PC, lo stesso invito funziona.
    pc.accendi();
    final invito = await telefono.nucleo.leggiInvito(testo);
    expect((await invito.collega()).problema, isNull);
  });

  test(
    "un invito appena creato si aspetta finché il servizio non è pubblicato",
    () async {
      final testo = await pc.invito(atletaId);
      // Il descrittore del servizio non è ancora sulla rete: Tor risponde F0
      // per due volte.
      telefono.tor.guasti.addAll(const [
        ErroreSocks(ErroreSocks.descrittoreNonTrovato),
        ErroreSocks(ErroreSocks.descrittoreNonTrovato),
      ]);
      final fasi = <String>[];
      void segui(AvanzamentoAbbinamento a) => fasi.add(switch (a.fase) {
        FaseAbbinamento.avvioTor => 'tor ${a.percentoTor}',
        FaseAbbinamento.attesaCoach => 'attesa ${a.tentativo}',
        final fase => fase.name,
      });

      final invito = await telefono.nucleo.leggiInvito(testo, avanzamento: segui);
      expect(invito.nomeCoach, 'Marco Bianchi');
      await invito.collega(avanzamento: segui);
      expect(fasi, [
        'tor 0',
        'tor 50',
        'tor 100',
        'collegamento',
        'attesa 1',
        'collegamento',
        'attesa 2',
        'collegamento',
        'abbinamento',
        'conferma',
      ]);
      expect(ambiente.orologio.attese.take(2), const [
        Duration(seconds: 5),
        Duration(seconds: 10),
      ]);
    },
  );

  test('un tentativo appeso non si aspetta fino al timeout', () async {
    final testo = await pc.invito(atletaId);
    telefono.nucleo.contesto.durataTentativiInvito = const [
      Duration(milliseconds: 200),
    ];
    // La prima connessione resta appesa, come quella di un Tor appena
    // avviato che arriverebbe al timeout di 90 s.
    final appesa = Completer<void>();
    telefono.tor.primaDellaConnessione = () => appesa.future;

    final inizio = DateTime.now();
    final invito = await telefono.nucleo.leggiInvito(testo);
    expect(invito.nomeCoach, 'Marco Bianchi');
    expect(DateTime.now().difference(inizio), lessThan(const Duration(seconds: 5)));
    // La connessione appesa non è mai arrivata al coach: è riuscita la
    // seconda, dopo la pausa di 5 s.
    expect(telefono.tor.connessioni, 1);
    expect(ambiente.orologio.attese, const [Duration(seconds: 5)]);
    appesa.complete();
  });

  test('il coach che non si trova si aspetta al massimo due minuti', () async {
    final testo = await pc.invito(atletaId);
    pc.spegni();
    final inizio = ambiente.orologio.ora;
    await expectLater(
      telefono.nucleo.leggiInvito(testo),
      throwsA(erroreAbbinamento(ProblemaAbbinamento.coachIrraggiungibile)),
    );
    final attesa = ambiente.orologio.ora.difference(inizio);
    expect(attesa, greaterThan(const Duration(minutes: 1)));
    expect(attesa, lessThanOrEqualTo(attesaMassimaCoach));
  });

  test('app troppo vecchia per il coach', () async {
    pc.archivio.scriviImpostazione(Impostazioni.versioneAppMinima, '1.2.0');
    await expectLater(
      telefono.nucleo.leggiInvito(await pc.invito(atletaId)),
      throwsA(erroreAbbinamento(ProblemaAbbinamento.aggiornaApp)),
    );

    // La versione minima sale tra GET /v1/info e l'abbinamento: 426.
    pc.archivio.scriviImpostazione(Impostazioni.versioneAppMinima, '1.0.0');
    final invito = await telefono.nucleo.leggiInvito(await pc.invito(atletaId));
    pc.archivio.scriviImpostazione(Impostazioni.versioneAppMinima, '1.2.0');
    await expectLater(
      invito.collega(),
      throwsA(erroreAbbinamento(ProblemaAbbinamento.aggiornaApp)),
    );
  });

  test(
    'la conferma si ritenta finché il nuovo descrittore non arriva',
    () async {
      final invito = await telefono.nucleo.leggiInvito(
        await pc.invito(atletaId),
      );
      // Il descrittore con la chiave del dispositivo arriva dopo 3 minuti.
      pc.congelaServizio(per: const Duration(minutes: 3));
      final inizio = ambiente.orologio.ora;

      final coach = await invito.collega();
      expect(coach.confermaInSospeso, isFalse);
      expect(coach.problema, isNull);
      expect(
        ambiente.orologio.ora.difference(inizio),
        greaterThanOrEqualTo(const Duration(minutes: 3)),
      );
      expect(ambiente.orologio.attese, const [
        Duration(seconds: 15),
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 2),
      ]);
      expect(pc.eventi.whereType<AbbinamentoConfermato>(), hasLength(1));
    },
  );

  test('senza conferma entro 10 minuti la ritenta a ogni apertura', () async {
    final invito = await telefono.nucleo.leggiInvito(await pc.invito(atletaId));
    pc.congelaServizio();
    final inizio = ambiente.orologio.ora;

    final coach = await invito.collega();
    expect(coach.confermaInSospeso, isTrue);
    expect(coach.problema, ProblemaSync.coachIrraggiungibile);
    expect(
      ambiente.orologio.ora.difference(inizio),
      greaterThanOrEqualTo(MotoreSync.durataConferma),
    );
    expect(telefono.nucleo.schede.elenco(coach.id), isEmpty);

    // Più tardi il servizio è ripubblicato e l'atleta riapre l'app.
    pc.ripubblica();
    pc.pubblicaScheda(atletaId, 'Forza');
    await telefono.riapri();
    final esito = await telefono.nucleo.sync.sincronizza(coach.id);
    expect(esito.riuscita, isTrue);
    expect(esito.completa, isTrue);
    expect(esito.schedeNuove.single.titolo, 'Forza');
    expect(
      telefono.nucleo.collegamenti.cerca(coach.id)!.confermaInSospeso,
      isFalse,
    );
    expect(pc.eventi.whereType<AbbinamentoConfermato>(), hasLength(1));
  });

  test(
    "risposta all'abbinamento persa: l'app la ripete da sola con la stessa chiave",
    () async {
      final testo = await pc.invito(atletaId);
      final invito = await telefono.nucleo.leggiInvito(testo);
      pc.perdiProssimaRisposta = true;
      final fasi = <FaseAbbinamento>[];
      final coach = await invito.collega(avanzamento: (a) => fasi.add(a.fase));
      // Il coach ha trattato la richiesta persa; la ripetizione con la stessa
      // chiave rinnova solo il token.
      expect(pc.eventi.whereType<DispositivoAbbinato>(), hasLength(1));
      expect(fasi, [
        FaseAbbinamento.abbinamento,
        FaseAbbinamento.attesaCoach,
        FaseAbbinamento.abbinamento,
        FaseAbbinamento.conferma,
      ]);
      expect(coach.confermaInSospeso, isFalse);
      expect(coach.problema, isNull);
      expect(pc.eventi.whereType<InvitoContestato>(), isEmpty);
      expect(pc.nucleo.dispositivi.elenco(atletaId), hasLength(1));
      expect(telefono.cassaforte.nomi, ['coach.${coach.id}']);
    },
  );

  test('un nuovo invito mentre il vecchio collegamento sincronizza', () async {
    final vecchio = await ambiente.abbina(telefono, pc, atletaId);
    // Il coach revoca il telefono e manda un nuovo invito allo stesso
    // atleta.
    pc.nucleo.dispositivi.revoca(vecchio.dispositivoId);
    final invito = await telefono.nucleo.leggiInvito(await pc.invito(atletaId));

    // Proprio mentre parte l'abbinamento, il vecchio collegamento
    // sincronizza: non deve togliere a Tor la chiave d'invito.
    EsitoSync? esitoVecchio;
    telefono.tor.primaDellaConnessione = () async =>
        esitoVecchio = await telefono.nucleo.sync.sincronizza(vecchio.id);
    final ripreso = await invito.collega();
    expect(esitoVecchio?.problema, ProblemaSync.revocato);
    expect(ripreso.id, vecchio.id);
    expect(ripreso.stato, StatoCollegamento.attivo);
    expect(ripreso.problema, isNull);
    expect(telefono.cassaforte.nomi, ['coach.${vecchio.id}']);
  });
}
