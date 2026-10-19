import 'package:atleta_nucleo/atleta_nucleo.dart';
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

  test('la sync in background dice quali schede annunciare', () async {
    final nuova = pc.pubblicaScheda(atletaId, 'Nuova');
    final archiviata = pc.pubblicaScheda(atletaId, 'Già archiviata');
    pc.nucleo.schede.archivia(archiviata);
    final esiti = await telefono.nucleo.sincronizzaInBackground();
    expect([for (final s in esiti.single.schedeNuove) s.id], [nuova]);
  });
}
