import 'dart:typed_data';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

import 'supporto.dart';

/// Un modello con una domanda obbligatoria e la richiesta di [foto] foto.
Map<String, Object?> checkMensile({int? foto, String titolo = 'Check mensile'}) => {
  'titolo': titolo,
  'descrizione': 'Come è andato il mese?',
  'domande': [
    {'id': nuovoUuid(), 'tipo': 'scala', 'testo': 'Energia', 'obbligatoria': true},
  ],
  if (foto != null) 'foto': {'numero': foto, 'istruzioni': 'Fronte e retro'},
};

/// Le risposte del telefono a [questionario], con le [foto] già caricate.
Map<String, Object?> risposta(Map<String, Object?> questionario, {List<String> foto = const []}) => {
  'questionario_id': questionario['id'],
  'inviata_il': '2026-10-18T20:00:00+02:00',
  'risposte': [
    {
      'domanda_id': ((questionario['domande']! as List<Object?>).first! as Map<String, Object?>)['id'],
      'valore': 8,
    },
  ],
  'foto': foto,
};

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);

void main() {
  late Ambiente a;
  late String atletaId;
  late TelefonoFinto telefono;

  setUp(() async {
    a = await Ambiente.avvia();
    atletaId = a.nucleo.atleti.crea('Giulia').id;
    telefono = await a.abbinaTelefono(atletaId);
    await telefono.sincronizza();
  });
  tearDown(() => a.chiudi());

  GestioneQuestionari q() => a.nucleo.questionari;

  test('un modello incompleto non si salva', () {
    expect(
      () => q().creaModello({'titolo': '', 'domande': <Object?>[]}),
      throwsA(isA<QuestionarioNonValido>()),
    );
    final id = q().creaModello(checkMensile());
    expect(q().modello(id)!.titolo, 'Check mensile');
    final copia = q().modello(q().duplicaModello(id))!;
    expect(copia.titolo, 'Check mensile (copia)');
  });

  test('mandato, arriva alla sync; annullato, sparisce', () async {
    final modello = q().creaModello(checkMensile());
    final inviato = q().invia(modello, atletaId);
    // Cambiare il modello dopo non cambia quello mandato.
    q().salvaModello(modello, checkMensile(titolo: 'Check di novembre'));

    var r = (await telefono.sincronizza()).single;
    expect(r.questionari.single['id'], inviato);
    expect(r.questionari.single['titolo'], 'Check mensile');
    expect(validaQuestionario(r.questionari.single), isEmpty);

    q().annulla(inviato);
    r = (await telefono.sincronizza()).single;
    expect(r.questionari, isEmpty);
    expect(r.questionariAnnullati, [inviato]);
    expect(q().inviati(atletaId).single.stato, StatoQuestionario.annullato);
  });

  test('lo stato completo contiene solo i questionari senza risposta', () async {
    final modello = q().creaModello(checkMensile());
    final aperto = q().invia(modello, atletaId);
    q().annulla(q().invia(modello, atletaId));
    final risposto = q().invia(modello, atletaId);
    final r = (await telefono.sincronizza()).single;
    await telefono.sincronizza(
      risposteQuestionari: [risposta(r.questionari.firstWhere((x) => x['id'] == risposto))],
    );

    telefono.cursore = null;
    final completa = (await telefono.sincronizza()).single;
    expect(completa.completo, isTrue);
    expect([for (final x in completa.questionari) x['id']], [aperto]);
  });

  test('risposte con le foto: senza le foto si rifiutano, poi si accettano una volta sola', () async {
    final inviato = q().invia(q().creaModello(checkMensile(foto: 2)), atletaId);
    final questionario = (await telefono.sincronizza()).single.questionari.single;
    final fronte = nuovoUuid();
    final retro = nuovoUuid();

    await telefono.cliente.caricaFoto(fronte, jpeg);
    var r = (await telefono.sincronizza(
      risposteQuestionari: [risposta(questionario, foto: [fronte, retro])],
    )).single;
    expect(r.risposteRifiutate.single.errore, RifiutoRisposta.fotoMancanti);
    expect(q().inviato(inviato)!.stato, StatoQuestionario.inviato);

    await telefono.cliente.caricaFoto(retro, jpeg);
    await telefono.cliente.caricaFoto(retro, jpeg);
    a.eventi.clear();
    r = (await telefono.sincronizza(
      risposteQuestionari: [risposta(questionario, foto: [fronte, retro])],
    )).single;
    expect(r.risposteAccettate, [inviato]);
    final ricevuto = q().inviato(inviato)!;
    expect(ricevuto.stato, StatoQuestionario.risposto);
    expect(ricevuto.foto, [fronte, retro]);
    expect(ricevuto.letto, isFalse);
    expect(q().foto(retro), jpeg);
    expect(q().nonLette(atletaId), 1);
    expect(a.eventi.whereType<QuestionarioRisposto>().single.titolo, 'Check mensile');

    // Ripetere l'invio, per esempio dopo una risposta persa, non cambia nulla.
    a.eventi.clear();
    r = (await telefono.sincronizza(
      risposteQuestionari: [risposta(questionario, foto: [fronte, retro])],
    )).single;
    expect(r.risposteAccettate, [inviato]);
    expect(a.eventi.whereType<QuestionarioRisposto>(), isEmpty);

    q().segnaLetto(inviato);
    expect(q().nonLette(atletaId), 0);
    expect(q().risposte(atletaId).single.id, inviato);
  });

  test('risposte non valide o a questionari di altri atleti si rifiutano', () async {
    final altro = a.nucleo.atleti.crea('Luca').id;
    final modello = q().creaModello(checkMensile());
    final suo = q().invia(modello, altro);
    q().invia(modello, atletaId);
    final questionario = (await telefono.sincronizza()).single.questionari.single;

    final r = (await telefono.sincronizza(
      risposteQuestionari: [
        risposta({...questionario, 'id': suo}),
        {...risposta(questionario), 'risposte': <Object?>[]},
      ],
    )).single;
    expect([for (final x in r.risposteRifiutate) x.errore], [
      RifiutoRisposta.sconosciuto,
      RifiutoRisposta.nonValida,
    ]);
  });

  test('una foto deve essere un JPEG e non si condivide tra atleti', () async {
    expect(
      () => telefono.cliente.caricaFoto(nuovoUuid(), Uint8List.fromList([1, 2, 3, 4])),
      throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 400)),
    );
    final id = nuovoUuid();
    await telefono.cliente.caricaFoto(id, jpeg);
    final altro = await a.abbinaTelefono(a.nucleo.atleti.crea('Luca').id);
    expect(
      () => altro.cliente.caricaFoto(id, jpeg),
      throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 409)),
    );
  });
}
