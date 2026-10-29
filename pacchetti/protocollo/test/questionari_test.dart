import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

void main() {
  final nome = nuovoUuid();
  final giorni = nuovoUuid();
  final attrezzi = nuovoUuid();
  final altezza = nuovoUuid();
  final energia = nuovoUuid();
  final questionario = <String, Object?>{
    'id': nuovoUuid(),
    'inviato_il': '2026-10-27T10:00:00+01:00',
    'titolo': 'Questionario iniziale',
    'descrizione': 'Mi serve per costruire il tuo programma.',
    'domande': [
      {'id': nome, 'tipo': 'testo_breve', 'testo': 'Come ti chiami?', 'obbligatoria': true},
      {
        'id': giorni,
        'tipo': 'scelta_singola',
        'testo': 'Quanti giorni a settimana?',
        'obbligatoria': true,
        'opzioni': ['2 giorni', '3 giorni', '4 giorni'],
        'altro': true,
      },
      {
        'id': attrezzi,
        'tipo': 'scelta_multipla',
        'testo': 'Quali attrezzi hai?',
        'obbligatoria': false,
        'opzioni': ['Leg press', 'Lat machine'],
        'altro': true,
      },
      {'id': altezza, 'tipo': 'numero', 'testo': 'Quanto sei alto?', 'obbligatoria': true, 'unita': 'cm'},
      {'id': energia, 'tipo': 'scala', 'testo': 'Energia', 'obbligatoria': false},
    ],
    'foto': {'numero': 2, 'istruzioni': 'Fronte e retro, corpo intero.'},
  };

  test('un questionario ben fatto è valido', () {
    expect(validaQuestionario(questionario), isEmpty);
  });

  test('domande senza testo, scelte senza opzioni, foto fuori misura', () {
    expect(
      validaContenutoQuestionario({
        'titolo': '',
        'domande': [
          {'id': nome, 'tipo': 'scelta_multipla', 'testo': ' ', 'obbligatoria': true, 'opzioni': <Object?>[]},
          {'id': nome, 'tipo': 'disegno', 'testo': 'x', 'obbligatoria': false},
        ],
        'foto': {'numero': 11},
      }),
      [
        'titolo: da 1 a 200 caratteri',
        'domande[0].testo: da 1 a 500 caratteri',
        'domande[0].opzioni: da 1 a 50 opzioni diverse, non vuote',
        'domande[1].id: UUID mancante o ripetuto',
        'domande[1].tipo: tipo sconosciuto',
        'foto.numero: da 1 a 10',
      ],
    );
    expect(
      validaContenutoQuestionario({'titolo': 'Vuoto', 'domande': <Object?>[]}),
      ['domande: serve almeno una domanda o una richiesta di foto'],
    );
  });

  Map<String, Object?> risposta(List<Map<String, Object?>> risposte, {int foto = 2}) => {
    'questionario_id': questionario['id'],
    'inviata_il': '2026-10-27T18:00:00+01:00',
    'risposte': risposte,
    'foto': [for (var i = 0; i < foto; i++) nuovoUuid()],
  };

  test('risposte valide: scelte, «altro», numeri, scala e foto', () {
    expect(
      validaRisposta(
        risposta([
          {'domanda_id': nome, 'valore': 'Giulia'},
          {
            'domanda_id': giorni,
            'valore': {'altro': 'Giorni alterni'},
          },
          {
            'domanda_id': attrezzi,
            'valore': {
              'scelte': ['Leg press'],
              'altro': 'Vulken',
            },
          },
          {'domanda_id': altezza, 'valore': 168.5},
          {'domanda_id': energia, 'valore': 7},
        ]),
        questionario,
      ),
      isEmpty,
    );
  });

  test('risposte non valide', () {
    expect(
      validaRisposta(
        risposta([
          {'domanda_id': nome, 'valore': ''},
          {
            'domanda_id': giorni,
            'valore': {'scelta': '5 giorni'},
          },
          {'domanda_id': energia, 'valore': 11},
          {'domanda_id': nuovoUuid(), 'valore': 'x'},
        ], foto: 1),
        questionario,
      ),
      [
        'risposte[0].valore: testo da 1 a 500 caratteri',
        'risposte[1].valore: opzione sconosciuta',
        'risposte[2].valore: intero da 1 a 10',
        'risposte[3].domanda_id: domanda sconosciuta o ripetuta',
        'risposte: manca la risposta obbligatoria a «Quanto sei alto?»',
        'foto: servono 2 id di foto diversi',
      ],
    );
  });

  test('i questionari nella sync sono facoltativi', () {
    final vecchia = RispostaSync.fromJson({
      'epoca': 'e',
      'completo': false,
      'log_accettati': <Object?>[],
      'log_rifiutati': <Object?>[],
      'schede': <Object?>[],
      'schede_eliminate': <Object?>[],
      'log': <Object?>[],
      'cursore': 'c',
      'altro': false,
    });
    expect(vecchia.questionari, isEmpty);
    final nuova = RispostaSync.fromJson({
      ...vecchia.toJson(),
      'questionari': [questionario],
      'questionari_annullati': ['x'],
      'risposte_accettate': ['y'],
    });
    expect(nuova.questionari.single['titolo'], 'Questionario iniziale');
    expect(nuova.questionariAnnullati, ['x']);
    expect(nuova.risposteAccettate, ['y']);
  });

  test('una foto è un JPEG', () {
    expect(sembraJpeg([0xFF, 0xD8, 0xFF, 0xE0]), isTrue);
    expect(sembraJpeg([0x89, 0x50, 0x4E, 0x47]), isFalse);
  });
}
