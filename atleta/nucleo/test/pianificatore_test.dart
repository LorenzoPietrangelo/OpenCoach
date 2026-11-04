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

  PianificatoreSync pianificatore() => telefono.nucleo.pianificatore;

  Future<void> avanza(Duration durata) async {
    ambiente.orologio.avanza(durata);
    await pianificatore().attendi();
  }

  test(
    "in primo piano: all'apertura, dopo ogni log e ogni 10 minuti",
    () async {
      var richieste = pc.richiesteSync;
      int nuove() {
        final n = pc.richiesteSync - richieste;
        richieste = pc.richiesteSync;
        return n;
      }

      pianificatore().entraInPrimoPiano();
      await pianificatore().attendi();
      expect(nuove(), 1);

      final log = telefono.nucleo.diario.salva(coach.id, allenamento());
      await pianificatore().attendi();
      expect(nuove(), 1);
      expect(pc.log(log.id), isNotNull);

      await avanza(const Duration(minutes: 9));
      expect(nuove(), 0);
      await avanza(const Duration(minutes: 1));
      expect(nuove(), 1);
      await avanza(const Duration(minutes: 10));
      expect(nuove(), 1);

      expect((await pianificatore().sincronizzaOra(coach.id)).riuscita, isTrue);
      expect(nuove(), 1);
    },
  );

  test(
    'coach irraggiungibile: ritenta dopo 30 s, 2 e 5 minuti, poi aspetta',
    () async {
      var tentativi = telefono.tor.connessioni;
      int nuovi() {
        final n = telefono.tor.connessioni - tentativi;
        tentativi = telefono.tor.connessioni;
        return n;
      }

      pc.spegni();
      pianificatore().entraInPrimoPiano();
      await pianificatore().attendi();
      expect(nuovi(), 1);

      await avanza(const Duration(seconds: 29));
      expect(nuovi(), 0);
      await avanza(const Duration(seconds: 1));
      expect(nuovi(), 1);
      await avanza(const Duration(minutes: 2));
      expect(nuovi(), 1);
      await avanza(const Duration(minutes: 5));
      expect(nuovi(), 1);

      // Poi aspetta l'occasione successiva: la sync periodica, a 10 minuti
      // dall'apertura.
      await avanza(const Duration(minutes: 2));
      expect(nuovi(), 0);
      await avanza(const Duration(seconds: 30));
      expect(nuovi(), 1);

      // Il coach torna raggiungibile prima del primo ritentativo.
      pc.accendi();
      await avanza(const Duration(seconds: 30));
      expect(nuovi(), 1);
      expect(telefono.nucleo.collegamenti.cerca(coach.id)!.problema, isNull);
      await avanza(const Duration(minutes: 5));
      expect(nuovi(), 0);
    },
  );

  test('i problemi che non passano da soli non si ritentano', () async {
    var tentativi = telefono.tor.connessioni;
    telefono.rete.connessa = false;
    pianificatore().entraInPrimoPiano();
    await pianificatore().attendi();
    await avanza(const Duration(minutes: 8));
    expect(telefono.tor.connessioni, tentativi);

    // Quando la rete torna, la sync parte subito.
    telefono.rete.connessa = true;
    pianificatore().reteTornata();
    await pianificatore().attendi();
    expect(telefono.tor.connessioni, tentativi + 1);
    tentativi = telefono.tor.connessioni;
    expect(telefono.nucleo.collegamenti.cerca(coach.id)!.problema, isNull);
  });

  test('in background: niente sync automatiche e Tor spento', () async {
    pianificatore().entraInPrimoPiano();
    await pianificatore().attendi();
    expect(telefono.tor.attivo, isTrue);

    await pianificatore().vaiInBackground();
    expect(telefono.tor.attivo, isFalse);
    expect(ambiente.orologio.inAttesa, isEmpty);
    final richieste = pc.richiesteSync;
    telefono.nucleo.diario.salva(coach.id, allenamento());
    await avanza(const Duration(hours: 1));
    expect(pc.richiesteSync, richieste);

    // In background la sync la chiede il sistema operativo; poi Tor si
    // spegne di nuovo.
    final esiti = await telefono.nucleo.sincronizzaInBackground();
    expect(esiti.single.logConfermati, 1);
    expect(telefono.tor.attivo, isFalse);
  });

  group('con la chat aperta', () {
    /// Aspetta, senza far passare il tempo dell'orologio finto, finché
    /// [condizione] non è vera.
    Future<void> finche(bool Function() condizione) async {
      final limite = DateTime.now().add(const Duration(seconds: 10));
      while (!condizione()) {
        if (DateTime.now().isAfter(limite)) fail('Non è successo in tempo');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    Future<ClienteApi> cliente() async => ClienteApi(
      indirizzo: pc.indirizzo,
      http: telefono.tor.creaHttpClient(),
      token: (await telefono.nucleo.contesto.credenziali(coach.id))!.token,
    );

    RichiestaAttesa richiesta({int attesaS = 25}) {
      final aggiornato = telefono.nucleo.collegamenti.cerca(coach.id)!;
      return RichiestaAttesa(epoca: aggiornato.epoca, cursore: aggiornato.cursore, attesaS: attesaS);
    }

    test('il messaggio del coach arriva appena lo scrive', () async {
      pianificatore()
        ..entraInPrimoPiano()
        ..segui(coach.id);
      await pianificatore().attendi();
      // La richiesta che parte dopo la sync resta in sospeso sul PC.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final sync = pc.richiesteSync;
      expect(telefono.nucleo.chat.elenco(coach.id), isEmpty);

      pc.nucleo.messaggi.invia(atletaId, 'Domani carichi pesanti');
      await finche(() => telefono.nucleo.chat.elenco(coach.id).isNotEmpty);
      expect(telefono.nucleo.chat.elenco(coach.id).single.testo, 'Domani carichi pesanti');
      expect(pc.richiesteSync, sync + 1);

      // E l'attesa riparte: anche il secondo arriva subito.
      pc.nucleo.messaggi.invia(atletaId, 'E dormi bene');
      await finche(() => telefono.nucleo.chat.elenco(coach.id).length == 2);
      pianificatore().smettiDiSeguire(coach.id);
    });

    test('quello che scrive l\'atleta non aspetta la risposta del coach', () async {
      pianificatore()
        ..entraInPrimoPiano()
        ..segui(coach.id);
      await pianificatore().attendi();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final messaggio = telefono.nucleo.chat.scrivi(coach.id, 'Finita la panca');
      await pianificatore().attendi();
      expect(telefono.nucleo.chat.cerca(coach.id, messaggio.id)!.stato, StatoMessaggio.inviato);
      pianificatore().smettiDiSeguire(coach.id);
    });

    test('chiudendo la chat o l\'app non si aspetta più', () async {
      pianificatore()
        ..entraInPrimoPiano()
        ..segui(coach.id);
      await pianificatore().attendi();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      pianificatore().smettiDiSeguire(coach.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final sync = pc.richiesteSync;
      pc.nucleo.messaggi.invia(atletaId, 'Chat chiusa');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(pc.richiesteSync, sync);

      // In background si ferma; al ritorno in primo piano riprende.
      pianificatore().segui(coach.id);
      await pianificatore().attendi();
      await pianificatore().vaiInBackground();
      final inBackground = pc.richiesteSync;
      pc.nucleo.messaggi.invia(atletaId, 'App chiusa');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(pc.richiesteSync, inBackground);
      pianificatore().entraInPrimoPiano();
      await finche(() => telefono.nucleo.chat.elenco(coach.id).length == 2);
      pianificatore().smettiDiSeguire(coach.id);
    });

    test('con un programma che non conosce l\'attesa sincronizza ogni 15 s', () async {
      pianificatore().entraInPrimoPiano();
      await pianificatore().attendi();
      // Dopo la prossima sync, l'attesa si trova davanti un programma vecchio.
      pc.dopoRichiesteSync(1, () => telefono.tor.guasti.add(const ErroreApi(404, 'non_trovato')));
      pianificatore().segui(coach.id);
      await pianificatore().attendi();
      await finche(() => telefono.tor.guasti.isEmpty && ambiente.orologio.inAttesa.length > 1);
      final sync = pc.richiesteSync;
      ambiente.orologio.avanza(PianificatoreSync.intervalloSenzaAttesa);
      await finche(() => pc.richiesteSync == sync + 1);
      pianificatore().smettiDiSeguire(coach.id);
    });

    test('senza novità il coach risponde allo scadere dell\'attesa', () async {
      await telefono.nucleo.sync.sincronizza(coach.id);
      final api = await cliente();
      expect(await api.attendiNovita(richiesta(attesaS: 1)), isFalse);
      pc.nucleo.messaggi.invia(atletaId, 'Già qui');
      // C'è già qualcosa: risponde subito.
      final inizio = DateTime.now();
      expect(await api.attendiNovita(richiesta()), isTrue);
      expect(DateTime.now().difference(inizio), lessThan(const Duration(seconds: 5)));
    });

    test('una sola attesa per dispositivo, e cede alla ripubblicazione', () async {
      await telefono.nucleo.sync.sincronizza(coach.id);
      final prima = await cliente();
      final seconda = await cliente();
      final inizio = DateTime.now();
      final attesaPrima = prima.attendiNovita(richiesta());
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final attesaSeconda = seconda.attendiNovita(richiesta());
      expect(await attesaPrima, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await pc.server.attendiRichiesteInCorso(const Duration(seconds: 5));
      expect(await attesaSeconda, isFalse);
      expect(DateTime.now().difference(inizio), lessThan(const Duration(seconds: 10)));
    });
  });

  test('la sync in background dice quali schede annunciare', () async {
    pc.pubblicaScheda(atletaId, 'Già archiviata');
    final nuova = pc.pubblicaScheda(atletaId, 'Nuova');
    final esiti = await telefono.nucleo.sincronizzaInBackground();
    expect([for (final s in esiti.single.schedeNuove) s.id], [nuova]);
  });
}
