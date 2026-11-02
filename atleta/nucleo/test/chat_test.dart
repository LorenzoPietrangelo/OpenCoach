import 'dart:io';
import 'dart:typed_data';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:path/path.dart' as p;
import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

import 'supporto.dart';

void main() {
  late Ambiente ambiente;
  late PcCoach pc;
  late Telefono telefono;
  late String atletaId;
  late CoachCollegato coach;
  late Directory registrazioni;

  setUp(() async {
    ambiente = Ambiente();
    pc = await ambiente.avviaCoach();
    atletaId = pc.nucleo.atleti.crea('Giulia Rossi').id;
    telefono = ambiente.telefono();
    coach = await ambiente.abbina(telefono, pc, atletaId);
    registrazioni = Directory.systemTemp.createTempSync('opencoach-registrazioni-');
  });
  tearDown(() async {
    await ambiente.chiudi();
    registrazioni.deleteSync(recursive: true);
  });

  ChatCoach chat() => telefono.nucleo.chat;

  Future<EsitoSync> sincronizza() => telefono.nucleo.sync.sincronizza(coach.id);

  /// Un video compresso finto di poco più di due parti.
  final video = Uint8List.fromList([for (var i = 0; i < LimitiChat.parteVideo * 2 + 1000; i++) i % 241]);

  String registra() {
    final file = File(p.join(registrazioni.path, '${nuovoUuid()}.mp4'))..writeAsBytesSync(video);
    return file.path;
  }

  test('i messaggi vanno e vengono una volta sola', () async {
    final scritto = chat().scrivi(coach.id, '  Oggi ginocchio ok  ');
    expect(scritto.testo, 'Oggi ginocchio ok');
    expect(scritto.stato, StatoMessaggio.inInvio);
    await sincronizza();
    expect(chat().cerca(coach.id, scritto.id)!.stato, StatoMessaggio.inviato);
    expect(pc.nucleo.messaggi.conversazione(atletaId).single.testo, 'Oggi ginocchio ok');

    final risposta = pc.nucleo.messaggi.invia(atletaId, 'Bene, aumenta di 2,5 kg');
    var esito = await sincronizza();
    expect(esito.messaggiNuovi, [risposta.id]);
    expect([for (final m in chat().elenco(coach.id)) m.dalCoach], [false, true]);
    expect(chat().nonLetti(coach.id), 1);
    chat().segnaLetti(coach.id);
    expect(chat().nonLetti(coach.id), 0);

    esito = await sincronizza();
    expect(esito.messaggiNuovi, isEmpty);
    expect(pc.nucleo.messaggi.conversazione(atletaId), hasLength(2));
    expect(() => chat().scrivi(coach.id, ' '), throwsA(isA<OperazioneNonAmmessa>()));
  });

  test('il video di una serie arriva intero al coach', () async {
    final file = registra();
    final logId = nuovoUuid();
    final m = chat().allegaVideo(coach.id, file: file, durataS: 14, logId: logId, esercizio: 'Squat', serie: 3);
    expect(File(file).existsSync(), isFalse, reason: 'il video passa nella cartella della chat');
    expect(m.video!['parti'], 3);
    expect(m.esercizio, 'Squat');

    await sincronizza();
    expect(chat().cerca(coach.id, m.id)!.stato, StatoMessaggio.inviato);
    final ricevuto = pc.nucleo.messaggi.conversazione(atletaId).single;
    expect(ricevuto.riferimento, {'log_id': logId, 'esercizio': 'Squat', 'serie': 3});
    expect(ricevuto.durataVideoS, 14);
    expect(pc.nucleo.messaggi.fileVideo(atletaId, ricevuto)!.readAsBytesSync(), video);
    expect(pc.eventi.whereType<MessaggioRicevuto>().single.conVideo, isTrue);
  });

  test('un video che non arriva giusto si ricarica, poi si rinuncia', () async {
    final m = chat().allegaVideo(coach.id, file: registra(), durataS: 5, esercizio: 'Panca', serie: 1);
    // Il file cambia dopo l'impronta: il coach non lo riconosce mai.
    final locale = File(chat().cerca(coach.id, m.id)!.fileVideo!);
    locale.writeAsBytesSync(Uint8List.fromList(video)..[0] ^= 1);

    await sincronizza();
    final rifiutato = chat().cerca(coach.id, m.id)!;
    expect(rifiutato.stato, StatoMessaggio.rifiutato);
    expect(rifiutato.rifiuto, RifiutoMessaggio.videoMancante);
    expect(pc.nucleo.messaggi.conversazione(atletaId), isEmpty);

    // Rimesso a posto, si ritenta.
    locale.writeAsBytesSync(video);
    chat().ritenta(coach.id, m.id);
    await sincronizza();
    expect(chat().cerca(coach.id, m.id)!.stato, StatoMessaggio.inviato);
  });

  test('lo stato completo non duplica e rimanda quello che il coach non ha più', () async {
    final scritto = chat().scrivi(coach.id, 'Primo');
    await sincronizza();
    pc.nucleo.messaggi.invia(atletaId, 'Secondo');
    await sincronizza();

    // Come dopo un ripristino del coach da un backup senza il messaggio.
    pc.archivio.db.execute('DELETE FROM messaggi WHERE id = ?', [scritto.id]);
    telefono.archivio.db.execute('UPDATE coach SET epoca = NULL WHERE id = ?', [coach.id]);
    final esito = await sincronizza();
    expect(esito.completa, isTrue);
    expect(esito.messaggiNuovi, isEmpty);
    expect(chat().elenco(coach.id), hasLength(2));
    expect(pc.nucleo.messaggi.conversazione(atletaId), hasLength(2));
  });

  test('dal video si tolgono posizione e altri metadati', () {
    final posizione = scatola('00a9xyz', '+45.4642+009.1900/'.codeUnits);
    final mp4 = Uint8List.fromList([
      ...scatola('ftyp', 'isom'.codeUnits),
      ...scatola('moov', [
        ...scatola('mvhd', List.filled(20, 1)),
        ...scatola('udta', posizione),
        ...scatola('trak', [...scatola('tkhd', List.filled(12, 2)), ...scatola('meta', 'Pixel 8'.codeUnits)]),
      ]),
      ...scatola('mdat', List.filled(30, 3)),
    ]);
    final pulito = Uint8List.fromList(mp4);
    cancellaMetadatiMp4(pulito);
    expect(pulito.length, mp4.length);
    final testo = String.fromCharCodes(pulito);
    expect(testo, isNot(contains('+45.4642')));
    expect(testo, isNot(contains('Pixel 8')));
    expect(testo, isNot(contains('udta')));
    expect(testo, contains('mvhd'));
    expect(testo, contains('tkhd'));
    expect(pulito.sublist(pulito.length - 30), List.filled(30, 3));
  });

  test('le scatole free si tolgono e gli offset dei campioni si spostano', () {
    List<int> intero(int n) => (ByteData(4)..setUint32(0, n)).buffer.asUint8List();
    List<int> mp4(List<int> offset) => [
      ...scatola('ftyp', 'isom'.codeUnits),
      ...scatola('moov', [
        ...scatola('trak', [
          ...scatola('mdia', [
            ...scatola('minf', [
              ...scatola('stbl', [
                ...scatola('stco', [0, 0, 0, 0, ...intero(offset.length), for (final o in offset) ...intero(o)]),
              ]),
            ]),
          ]),
        ]),
      ]),
      ...scatola('free', List.filled(500, 0)),
      ...scatola('mdat', [...'PRIMO'.codeUnits, ...'SECONDO'.codeUnits]),
    ];
    // Le dimensioni non dipendono dagli offset: si calcolano su una prova.
    final campioni = String.fromCharCodes(mp4(const [0, 0])).indexOf('PRIMO');
    final dati = Uint8List.fromList(mp4([campioni, campioni + 5]));
    final compatto = compattaMp4(dati);
    expect(compatto.length, dati.length - 508);
    expect(String.fromCharCodes(compatto), isNot(contains('free')));
    final b = ByteData.sublistView(compatto);
    final i = String.fromCharCodes(compatto).indexOf('stco') + 4;
    final primo = b.getUint32(i + 8);
    final secondo = b.getUint32(i + 12);
    expect(String.fromCharCodes(compatto, primo, primo + 5), 'PRIMO');
    expect(String.fromCharCodes(compatto, secondo, secondo + 7), 'SECONDO');
    // Quello che non è un MP4 resta com'è.
    final altro = Uint8List.fromList(List.filled(50, 7));
    expect(compattaMp4(altro), same(altro));
  });

  test('un messaggio non ancora partito si ritira; i video vanno via con i dati del coach', () async {
    final m = chat().allegaVideo(coach.id, file: registra(), durataS: 8);
    final file = chat().cerca(coach.id, m.id)!.fileVideo!;
    chat().ritira(coach.id, m.id);
    expect(File(file).existsSync(), isFalse);
    expect(chat().elenco(coach.id), isEmpty);

    final altro = chat().allegaVideo(coach.id, file: registra(), durataS: 8);
    await sincronizza();
    expect(() => chat().ritira(coach.id, altro.id), throwsA(isA<OperazioneNonAmmessa>()));

    await telefono.nucleo.collegamenti.scollega(coach.id);
    expect(() => chat().scrivi(coach.id, 'Ciao'), throwsA(isA<OperazioneNonAmmessa>()));
    await telefono.nucleo.collegamenti.cancellaDati(coach.id);
    expect(Directory(p.join(telefono.cartellaVideo, '${coach.id}')).existsSync(), isFalse);
  });
}

/// Una scatola MP4 di tipo [tipo] con [contenuto].
List<int> scatola(String tipo, List<int> contenuto) => [
  ...(ByteData(4)..setUint32(0, contenuto.length + 8)).buffer.asUint8List(),
  ...tipo.codeUnits,
  ...contenuto,
];
