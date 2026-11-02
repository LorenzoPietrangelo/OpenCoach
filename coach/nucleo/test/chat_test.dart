import 'dart:io';
import 'dart:typed_data';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:crypto/crypto.dart';
import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

import 'supporto.dart';

/// Un messaggio dell'atleta, con il [video] se c'è.
Map<String, Object?> messaggio({String? id, String testo = 'Com\'è andata?', Map<String, Object?>? video}) => {
  'id': id ?? nuovoUuid(),
  'autore': 'atleta',
  'testo': testo,
  'inviato_il': '2026-10-18T20:00:00+02:00',
  if (video != null) ...{
    'video': video,
    'riferimento': {'log_id': nuovoUuid(), 'esercizio': 'Squat', 'serie': 2},
  },
};

/// I metadati di un video di [dati].
Map<String, Object?> datiVideo(String id, Uint8List dati) => {
  'id': id,
  'dimensione': dati.length,
  'parti': partiVideo(dati.length),
  'sha256': sha256.convert(dati).toString(),
  'durata_s': 12,
};

/// Un video finto di poco più di due parti.
final video = Uint8List.fromList([for (var i = 0; i < LimitiChat.parteVideo * 2 + 1000; i++) i % 251]);

void main() {
  late Directory cartella;
  late Ambiente a;
  late String atletaId;
  late TelefonoFinto telefono;

  setUp(() async {
    cartella = Directory.systemTemp.createTempSync('opencoach-chat-');
    a = await Ambiente.avvia(cartellaVideo: cartella.path);
    atletaId = a.nucleo.atleti.crea('Giulia').id;
    telefono = await a.abbinaTelefono(atletaId);
    await telefono.sincronizza();
  });
  tearDown(() async {
    await a.chiudi();
    cartella.deleteSync(recursive: true);
  });

  GestioneMessaggi m() => a.nucleo.messaggi;

  Future<void> caricaParti(String id, Uint8List dati) async {
    for (var i = 0; i < partiVideo(dati.length); i++) {
      final fine = (i + 1) * LimitiChat.parteVideo;
      await telefono.cliente.caricaParteVideo(
        id,
        i,
        Uint8List.sublistView(dati, i * LimitiChat.parteVideo, fine < dati.length ? fine : dati.length),
      );
      a.avanza(const Duration(seconds: 3));
    }
  }

  test('il messaggio del coach arriva alla sync, quello dell\'atleta una volta sola', () async {
    final mandato = m().invia(atletaId, '  Ottimo lavoro  ');
    expect(mandato.testo, 'Ottimo lavoro');
    var r = (await telefono.sincronizza()).single;
    expect(r.messaggi.single['id'], mandato.id);
    expect(r.messaggi.single['autore'], 'coach');
    expect(validaMessaggio(r.messaggi.single), isEmpty);

    final scritto = messaggio();
    r = (await telefono.sincronizza(messaggi: [scritto])).single;
    expect(r.messaggiAccettati, [scritto['id']]);
    expect(r.messaggi, isEmpty, reason: 'il telefono ha già il suo messaggio');
    r = (await telefono.sincronizza(messaggi: [scritto])).single;
    expect(r.messaggiAccettati, [scritto['id']]);

    expect([for (final x in m().conversazione(atletaId)) x.dalCoach], [true, false]);
    expect(m().nonLetti(atletaId), 1);
    expect(a.eventi.whereType<MessaggioRicevuto>(), hasLength(1));
    m().segnaLetti(atletaId);
    expect(m().nonLetti(atletaId), 0);
  });

  test('messaggi non validi, del coach o di un altro atleta si rifiutano', () async {
    final scritto = messaggio();
    await telefono.sincronizza(messaggi: [scritto]);
    final altro = await a.abbinaTelefono(a.nucleo.atleti.crea('Luca').id, nome: 'Galaxy');
    final r = (await altro.sincronizza(
      messaggi: [
        scritto,
        {...messaggio(), 'autore': 'coach'},
        messaggio(testo: ''),
      ],
    )).single;
    expect(r.messaggiAccettati, isEmpty);
    expect([for (final x in r.messaggiRifiutati) x.errore], [
      RifiutoMessaggio.altroAtleta,
      RifiutoMessaggio.nonValido,
      RifiutoMessaggio.nonValido,
    ]);
    expect(() => m().invia(atletaId, ' '), throwsA(isA<OperazioneNonValida>()));
  });

  test('il video arriva a parti e si ricompone con l\'impronta giusta', () async {
    final id = nuovoUuid();
    final conVideo = messaggio(testo: '', video: datiVideo(id, video));

    // Senza le parti il messaggio aspetta.
    var r = (await telefono.sincronizza(messaggi: [conVideo])).single;
    expect(r.messaggiRifiutati.single.errore, RifiutoMessaggio.videoMancante);

    await caricaParti(id, video);
    r = (await telefono.sincronizza(messaggi: [conVideo])).single;
    expect(r.messaggiAccettati, [conVideo['id']]);
    final ricevuto = m().conversazione(atletaId).single;
    expect(ricevuto.riferimento!['serie'], 2);
    expect(m().fileVideo(atletaId, ricevuto)!.readAsBytesSync(), video);
    expect(
      cartella.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.parte')),
      isEmpty,
    );

    m().eliminaVideo(atletaId, ricevuto.id);
    final dopo = m().conversazione(atletaId).single;
    expect(dopo.videoEliminato, isTrue);
    expect(m().fileVideo(atletaId, dopo), isNull);
  });

  test('parti che non corrispondono all\'impronta si scartano e si ricaricano', () async {
    final id = nuovoUuid();
    final conVideo = messaggio(video: datiVideo(id, video));
    final rovinato = Uint8List.fromList(video)..[10] ^= 1;
    await caricaParti(id, rovinato);
    var r = (await telefono.sincronizza(messaggi: [conVideo])).single;
    expect(r.messaggiRifiutati.single.errore, RifiutoMessaggio.videoMancante);

    await caricaParti(id, video);
    r = (await telefono.sincronizza(messaggi: [conVideo])).single;
    expect(r.messaggiAccettati, [conVideo['id']]);
  });

  test('parti fuori limite o troppo grandi si rifiutano', () async {
    expect(
      () => telefono.cliente.caricaParteVideo(nuovoUuid(), partiVideo(LimitiChat.videoMassimo), video.sublist(0, 10)),
      throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 404)),
    );
    expect(
      () => telefono.cliente.caricaParteVideo(nuovoUuid(), 0, video.sublist(0, LimitiChat.parteVideo + 1)),
      throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 413)),
    );
  });

  test('lo stato completo contiene tutta la chat; l\'atleta eliminato perde i video', () async {
    final id = nuovoUuid();
    await caricaParti(id, video);
    await telefono.sincronizza(messaggi: [messaggio(video: datiVideo(id, video))]);
    m().invia(atletaId, 'Visto, scendi un po\' di più');

    telefono.epoca = null;
    final r = await telefono.sincronizza();
    final chat = [for (final x in r) ...x.messaggi];
    expect(chat, hasLength(2));
    expect(chat.where((x) => x['video'] != null), hasLength(1));

    a.nucleo.atleti.elimina(atletaId);
    expect(Directory('${cartella.path}/$atletaId').existsSync(), isFalse);
  });
}
