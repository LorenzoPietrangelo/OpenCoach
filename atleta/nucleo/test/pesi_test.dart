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

  RegistroPesi pesi() => telefono.nucleo.pesi;

  Future<EsitoSync> sincronizza([int? id]) => telefono.nucleo.sync.sincronizza(id ?? coach.id);

  List<(int, double)> delCoach(PcCoach pc, String atletaId) => [
    for (final p in pc.nucleo.pesi.elenco(atletaId)) (p.giorno.day, p.kg),
  ];

  test('un peso al giorno: salvato, corretto ed eliminato, anche dal coach', () async {
    pesi().salva(DateTime(2026, 10, 16), 72.44);
    pesi().salva(DateTime(2026, 10, 17), 72.1);
    pesi().salva(DateTime(2026, 10, 17), 71.9);
    expect([for (final p in pesi().elenco()) (p.giorno.day, p.kg)], [(16, 72.44), (17, 71.9)]);
    expect(pesi().delGiorno(DateTime(2026, 10, 17, 21))!.kg, 71.9);

    await sincronizza();
    expect(delCoach(pc, atletaId), [(16, 72.44), (17, 71.9)]);

    pesi().elimina(DateTime(2026, 10, 16));
    pesi().salva(DateTime(2026, 10, 17), 71.5);
    await sincronizza();
    expect(delCoach(pc, atletaId), [(17, 71.5)]);

    // Lo stesso giorno, eliminato e riscritto, resta un solo peso.
    pesi().salva(DateTime(2026, 10, 16), 73);
    await sincronizza();
    expect(delCoach(pc, atletaId), [(16, 73.0), (17, 71.5)]);
  });

  test('fuori intervallo o nel futuro non si salva', () {
    expect(
      () => pesi().salva(DateTime(2026, 10, 16), 12),
      throwsA(isA<OperazioneNonAmmessa>()),
    );
    expect(
      () => pesi().salva(DateTime(2026, 10, 19), 70),
      throwsA(isA<OperazioneNonAmmessa>()),
      reason: "l'orologio di prova è al 18 ottobre",
    );
    expect(pesi().elenco(), isEmpty);
  });

  test('smettere di condividere toglie i pesi al coach; ricominciare li rimanda', () async {
    pesi().salva(DateTime(2026, 10, 17), 72);
    await sincronizza();
    expect(delCoach(pc, atletaId), hasLength(1));

    pesi().condividi(coach.id, condividi: false);
    expect(telefono.nucleo.collegamenti.cerca(coach.id)!.condividePesi, isFalse);
    pesi().salva(DateTime(2026, 10, 18), 71.8);
    await sincronizza();
    expect(delCoach(pc, atletaId), isEmpty);

    pesi().condividi(coach.id, condividi: true);
    await sincronizza();
    expect(delCoach(pc, atletaId), [(17, 72.0), (18, 71.8)]);
  });

  test('con due coach il peso va solo a chi l\'atleta lo condivide', () async {
    final altroPc = await ambiente.avviaCoach(nome: 'Anna Verdi');
    final altroAtleta = altroPc.nucleo.atleti.crea('Giulia').id;
    final altro = await ambiente.abbina(telefono, altroPc, altroAtleta);
    pesi().condividi(altro.id, condividi: false);

    pesi().salva(DateTime(2026, 10, 17), 72);
    await telefono.nucleo.sync.sincronizzaTutti();
    expect(delCoach(pc, atletaId), hasLength(1));
    expect(delCoach(altroPc, altroAtleta), isEmpty);
  });

  test('dopo un ripristino del coach i pesi che mancano tornano in coda', () async {
    pesi().salva(DateTime(2026, 10, 16), 72.5);
    pesi().salva(DateTime(2026, 10, 17), 72);
    await sincronizza();

    // Come un backup di prima dei pesi: nuova epoca, pesi persi.
    pc.archivio.db.execute('DELETE FROM pesi');
    pc.archivio.rigeneraEpoca();
    await sincronizza();
    await sincronizza();
    expect(delCoach(pc, atletaId), [(16, 72.5), (17, 72.0)]);
  });

  test("l'esportazione completa contiene i pesi", () {
    pesi().salva(DateTime(2026, 10, 17), 72);
    expect(telefono.nucleo.esporta()['pesi'], [
      {'giorno': '2026-10-17', 'kg': 72.0},
    ]);
    expect(telefono.nucleo.esporta(coachId: coach.id).containsKey('pesi'), isFalse);
  });
}
