import 'dart:typed_data';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

import 'supporto.dart';

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 9, 9]);

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

  QuestionariRicevuti questionari() => telefono.nucleo.questionari;

  Future<EsitoSync> sincronizza() => telefono.nucleo.sync.sincronizza(coach.id);

  final giorni = nuovoUuid();
  final infortuni = nuovoUuid();
  String modello({int? foto}) => pc.nucleo.questionari.creaModello({
    'titolo': 'Questionario iniziale',
    'domande': [
      {
        'id': giorni,
        'tipo': 'scelta_singola',
        'testo': 'Quanti giorni a settimana?',
        'obbligatoria': true,
        'opzioni': ['3 giorni', '4 giorni'],
        'altro': true,
      },
      {'id': infortuni, 'tipo': 'testo_lungo', 'testo': 'Infortuni?', 'obbligatoria': false},
    ],
    if (foto != null) 'foto': {'numero': foto, 'istruzioni': 'Fronte e retro'},
  });

  test('compilato in più volte, con le foto, arriva al coach una volta sola', () async {
    final id = pc.nucleo.questionari.invia(modello(foto: 2), atletaId);
    final esito = await sincronizza();
    expect(esito.questionariNuovi, [id]);
    expect(questionari().daCompilare(coach.id), 1);
    final ricevuto = questionari().cerca(coach.id, id)!;
    expect(ricevuto.titolo, 'Questionario iniziale');
    expect(ricevuto.fotoRichieste, 2);

    // Senza la risposta obbligatoria e le foto non si invia.
    questionari().rispondi(coach.id, id, infortuni, 'Spalla destra');
    expect(() => questionari().invia(coach.id, id), throwsA(isA<RispostaNonValida>()));

    questionari().rispondi(coach.id, id, giorni, {'altro': 'Giorni alterni'});
    questionari().allegaFoto(coach.id, id, 0, jpeg);
    questionari().allegaFoto(coach.id, id, 1, jpeg);
    expect(
      () => questionari().allegaFoto(coach.id, id, 2, jpeg),
      throwsA(isA<OperazioneNonAmmessa>()),
    );
    questionari().invia(coach.id, id);
    expect(questionari().cerca(coach.id, id)!.stato, StatoQuestionario.inInvio);
    expect(
      () => questionari().rispondi(coach.id, id, infortuni, 'altro'),
      throwsA(isA<OperazioneNonAmmessa>()),
      reason: 'inviato, non si modifica più',
    );

    await sincronizza();
    expect(questionari().cerca(coach.id, id)!.stato, StatoQuestionario.inviato);
    expect(questionari().daCompilare(coach.id), 0);
    final alCoach = pc.nucleo.questionari.inviato(id)!;
    expect(alCoach.risposta!['risposte'], [
      {
        'domanda_id': giorni,
        'valore': {'altro': 'Giorni alterni'},
      },
      {'domanda_id': infortuni, 'valore': 'Spalla destra'},
    ]);
    expect([for (final f in alCoach.foto) pc.nucleo.questionari.foto(f)], [jpeg, jpeg]);
  });

  test('annullato dal coach sparisce dal telefono, se non è già stato inviato', () async {
    final primo = pc.nucleo.questionari.invia(modello(), atletaId);
    final secondo = pc.nucleo.questionari.invia(modello(), atletaId);
    await sincronizza();
    questionari().rispondi(coach.id, secondo, giorni, {'scelta': '3 giorni'});
    questionari().invia(coach.id, secondo);

    pc.nucleo.questionari.annulla(primo);
    await sincronizza();
    expect(questionari().cerca(coach.id, primo), isNull);
    expect(questionari().cerca(coach.id, secondo)!.stato, StatoQuestionario.inviato);
  });

  test('dopo una sync completa restano i da compilare del coach e gli inviati', () async {
    final aperto = pc.nucleo.questionari.invia(modello(), atletaId);
    final risposto = pc.nucleo.questionari.invia(modello(), atletaId);
    await sincronizza();
    questionari().rispondi(coach.id, risposto, giorni, {'scelta': '4 giorni'});
    questionari().invia(coach.id, risposto);
    await sincronizza();

    pc.archivio.rigeneraEpoca();
    final esito = await sincronizza();
    expect(esito.completa, isTrue);
    expect(esito.questionariNuovi, isEmpty);
    expect([for (final q in questionari().elenco(coach.id)) q.id], [aperto, risposto]);
  });
}
