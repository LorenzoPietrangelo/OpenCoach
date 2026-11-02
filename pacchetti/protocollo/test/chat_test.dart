import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> messaggio({Object? testo = 'Com\'è andata?', Map<String, Object?>? video}) => {
    'id': nuovoUuid(),
    'autore': 'atleta',
    'testo': testo,
    'inviato_il': '2026-11-01T18:00:00+01:00',
    'video': ?video,
  };

  test('un messaggio di testo è valido; vuoto, senza video, no', () {
    expect(validaMessaggio(messaggio()), isEmpty);
    expect(validaMessaggio(messaggio(testo: '  ')), ['testo: serve un testo o un video']);
    expect(validaMessaggio(messaggio(testo: 'x' * 4001)), ['testo: al massimo 4000 caratteri']);
    expect(validaMessaggio({...messaggio(), 'autore': 'altro'}), ['autore: coach o atleta']);
  });

  test('un video dichiara dimensione, parti, impronta e durata', () {
    final video = {
      'id': nuovoUuid(),
      'dimensione': 2500000,
      'parti': 3,
      'sha256': 'a' * 64,
      'durata_s': 32,
    };
    expect(partiVideo(2500000), 3);
    expect(partiVideo(LimitiChat.parteVideo), 1);
    expect(
      validaMessaggio({
        ...messaggio(testo: ''),
        'video': video,
        'riferimento': {'log_id': nuovoUuid(), 'esercizio': 'Squat', 'serie': 3},
      }),
      isEmpty,
    );
    expect(validaMessaggio(messaggio(video: {...video, 'parti': 2})), ['video.parti: deve essere 3']);
    expect(validaMessaggio(messaggio(video: {...video, 'durata_s': 120})), [
      'video.durata_s: da 1 a 90 secondi',
    ]);
    expect(validaMessaggio(messaggio(video: {...video, 'dimensione': 40 * 1024 * 1024})), [
      'video.dimensione: da 1 a 33554432 byte',
    ]);
  });

  test('i messaggi nella sync sono facoltativi', () {
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
    expect(vecchia.messaggiAccettati, isNull);
    expect(vecchia.messaggi, isEmpty);
    final nuova = RispostaSync.fromJson({...vecchia.toJson(), 'messaggi_accettati': ['a']});
    expect(nuova.messaggiAccettati, ['a']);
  });
}
