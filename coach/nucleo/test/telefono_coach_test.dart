import 'dart:typed_data';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

import 'supporto.dart';

const _datiTelefono = DatiDispositivo(nome: 'Galaxy', piattaforma: 'android', versioneApp: '1.5.0');

void main() {
  late Ambiente a;
  late String atletaId;

  setUp(() async {
    a = await Ambiente.avvia();
    atletaId = a.nucleo.atleti.crea('Giulia').id;
  });
  tearDown(() => a.chiudi());

  GestioneTelefonoCoach t() => a.nucleo.telefonoCoach;

  RichiestaAbbinamento richiesta(UriTelefonoCoach uri, CoppiaX25519 chiave) => RichiestaAbbinamento(
    invitoId: uri.id,
    segreto: uri.segreto,
    chiaveDispositivo: chiave.pubblicaBase32,
    dispositivo: _datiTelefono,
  );

  /// Collega un telefono seguendo il flusso del §16.2.
  Future<ClienteApi> collega() async {
    final invito = await t().creaInvito();
    final cliente = a.cliente();
    final risposta = await cliente.abbinaTelefonoCoach(richiesta(invito.uri!, await CoppiaX25519.genera()));
    cliente.token = risposta.token;
    await cliente.confermaTelefonoCoach();
    return cliente;
  }

  group('collegamento', () {
    test('il QR è valido un\'ora e un telefono si collega', () async {
      final invito = await t().creaInvito();
      expect(invito.scadeIl, a.ora.add(const Duration(hours: 1)));
      expect(UriTelefonoCoach.analizza(invito.uri.toString()).segreto, invito.uri!.segreto);

      final chiave = await CoppiaX25519.genera();
      final cliente = a.cliente();
      final risposta = await cliente.abbinaTelefonoCoach(richiesta(invito.uri!, chiave));
      expect(risposta.nomeCoach, 'Marco Bianchi');
      expect(t().attivo()?.nome, 'Galaxy');
      expect(a.nucleo.chiaviAutorizzate(), contains(chiave.pubblicaBase32));
      expect(a.nucleo.chiaviAutorizzate(), hasLength(2));
      await Future<void>.delayed(Duration.zero);
      expect(a.eventi.whereType<TelefonoCoachCollegato>().single.nomeTelefono, 'Galaxy');

      cliente.token = risposta.token;
      await cliente.confermaTelefonoCoach();
      expect(a.nucleo.chiaviAutorizzate(), [chiave.pubblicaBase32]);
      expect(t().invitoInCorso(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(a.eventi.whereType<TelefonoCoachConfermato>(), hasLength(1));
    });

    test('un QR scaduto, annullato o con il segreto sbagliato non vale', () async {
      final scaduto = await t().creaInvito();
      a.avanza(const Duration(hours: 1, seconds: 1));
      await expectLater(
        a.cliente().abbinaTelefonoCoach(richiesta(scaduto.uri!, await CoppiaX25519.genera())),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 410)),
      );
      expect(t().chiudiScaduti(), 1);

      final annullato = await t().creaInvito();
      t().annullaInvito();
      await expectLater(
        a.cliente().abbinaTelefonoCoach(richiesta(annullato.uri!, await CoppiaX25519.genera())),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 410)),
      );

      final uri = (await t().creaInvito()).uri!;
      final sbagliato = UriTelefonoCoach(
        indirizzo: uri.indirizzo,
        id: uri.id,
        segreto: codificaBase32(byteCasuali(32)),
        chiave: uri.chiave,
      );
      await expectLater(
        a.cliente().abbinaTelefonoCoach(richiesta(sbagliato, await CoppiaX25519.genera())),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 410)),
      );
      expect(t().attivo(), isNull);
    });

    test('la stessa chiave ottiene un token nuovo, un\'altra è un secondo telefono', () async {
      final uri = (await t().creaInvito()).uri!;
      final chiave = await CoppiaX25519.genera();
      final primo = await a.cliente().abbinaTelefonoCoach(richiesta(uri, chiave));
      final secondo = await a.cliente().abbinaTelefonoCoach(richiesta(uri, chiave));
      expect(secondo.telefonoId, primo.telefonoId);
      expect(secondo.token, isNot(primo.token));

      await expectLater(a.cliente(token: primo.token).atletiCoach(), throwsA(isA<ErroreApi>()));
      await a.cliente(token: secondo.token).atletiCoach();

      await expectLater(
        a.cliente().abbinaTelefonoCoach(richiesta(uri, await CoppiaX25519.genera())),
        throwsA(isA<ErroreApi>().having((e) => e.codice, 'codice', CodiceErrore.invitoInUso)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(a.eventi.whereType<TelefonoCoachContestato>(), hasLength(1));
    });

    test('un telefono nuovo sostituisce il precedente, e la revoca vale subito', () async {
      final vecchio = await collega();
      final nuovo = await collega();
      await expectLater(
        vecchio.atletiCoach(),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 401)),
      );
      await nuovo.atletiCoach();
      expect(a.nucleo.chiaviAutorizzate(), hasLength(1));

      t().revoca();
      await expectLater(
        nuovo.atletiCoach(),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 401)),
      );
      expect(a.nucleo.chiaviAutorizzate(), isEmpty);
    });

    test('il telefono si può scollegare da solo', () async {
      final cliente = await collega();
      await cliente.scollegaTelefonoCoach();
      expect(t().attivo(), isNull);
    });

    test('reimposta identità revoca anche questo telefono', () async {
      await collega();
      await t().creaInvito();
      a.nucleo.reimpostaIdentita(indirizzoOnionDaChiave(List.filled(32, 9)), [1, 2, 3]);
      expect(t().attivo(), isNull);
      expect(t().invitoInCorso(), isNull);
      expect(a.nucleo.chiaviAutorizzate(), isEmpty);
    });
  });

  group('permessi', () {
    test('con un token sconosciuto, o con quello di un atleta, non si legge niente', () async {
      final atleta = await a.abbinaTelefono(atletaId);
      await expectLater(
        a.cliente(token: codificaBase32(byteCasuali(32))).atletiCoach(),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 401)),
      );
      await expectLater(
        a.cliente(token: atleta.abbinamento.token).atletiCoach(),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 401)),
      );
    });

    test('il token del coach non vale sugli endpoint degli atleti', () async {
      final cliente = await collega();
      await expectLater(
        cliente.sincronizza(
          const RichiestaSync(epoca: null, cursore: null, log: [], versioneApp: '1.5.0'),
        ),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 401)),
      );
    });

    test('l\'invito di un atleta non collega il telefono del coach', () async {
      final invito = await a.nucleo.inviti.crea(atletaId);
      final uri = invito.uri!;
      await expectLater(
        a.cliente().abbinaTelefonoCoach(
          RichiestaAbbinamento(
            invitoId: uri.id,
            segreto: uri.segreto,
            chiaveDispositivo: (await CoppiaX25519.genera()).pubblicaBase32,
            dispositivo: _datiTelefono,
          ),
        ),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 410)),
      );
    });

    test('ci sono 120 richieste al minuto', () async {
      final cliente = await collega();
      // La conferma del collegamento è già una richiesta.
      for (var i = 0; i < 119; i++) {
        await cliente.pesiCoach(atletaId);
      }
      await expectLater(
        cliente.pesiCoach(atletaId),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 429)),
      );
    });
  });

  group('dati', () {
    late ClienteApi cliente;
    late TelefonoFinto telefono;

    setUp(() async {
      cliente = await collega();
      telefono = await a.abbinaTelefono(atletaId);
      await telefono.sincronizza();
    });

    Map<String, Object?> dalAtleta(String testo, {String? id}) => {
      'id': id ?? nuovoUuid(),
      'autore': 'atleta',
      'testo': testo,
      'inviato_il': '2026-10-18T20:00:00+02:00',
    };

    test('l\'elenco riassume ogni atleta e non mostra gli archiviati', () async {
      final archiviato = a.nucleo.atleti.crea('Zeno').id;
      a.nucleo.atleti.archivia(archiviato);
      await telefono.sincronizza(daInviare: [nuovoLog()], messaggi: [dalAtleta('Ciao coach')]);

      final elenco = await cliente.atletiCoach();
      final giulia = elenco.atleti.single;
      expect(giulia['nome'], 'Giulia');
      expect(giulia['telefono_collegato'], isTrue);
      expect(giulia['non_letti'], 1);
      expect(giulia['risposte_nuove'], 0);
      expect((giulia['ultimo_messaggio']! as Map)['testo'], 'Ciao coach');
      expect(giulia['ultimo_allenamento'], '2026-10-21T18:30:00+02:00');
    });

    test('il dettaglio ha note e schede, e un id sconosciuto dà 404', () async {
      a.nucleo.atleti.modifica(atletaId, note: 'Ginocchio');
      final scheda = a.nucleo.schede.crea(atletaId, contenuto: contenutoScheda('Forza'));
      a.nucleo.schede.pubblica(scheda);
      final dettaglio = await cliente.atletaCoach(atletaId);
      expect(dettaglio['note'], 'Ginocchio');
      expect(dettaglio['allenamenti_totali'], 0);
      final schede = dettaglio['schede']! as List<Object?>;
      expect((schede.single! as Map)['titolo'], 'Forza');
      expect((schede.single! as Map)['stato'], 'pubblicata');
      await expectLater(
        cliente.atletaCoach(nuovoUuid()),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 404)),
      );
    });

    test('un messaggio dal telefono arriva all\'atleta una volta sola', () async {
      final id = nuovoUuid();
      final primo = await cliente.inviaMessaggioCoach(atletaId, id, ' Bravissima ');
      expect(primo['testo'], 'Bravissima');
      expect(primo['autore'], 'coach');
      final ripetuto = await cliente.inviaMessaggioCoach(atletaId, id, ' Bravissima ');
      expect(ripetuto['id'], id);
      expect(a.nucleo.messaggi.conversazione(atletaId), hasLength(1));

      final risposta = (await telefono.sincronizza()).single;
      expect(risposta.messaggi.map((m) => (m as Map)['id']), [id]);
      await Future<void>.delayed(Duration.zero);
      expect(a.eventi.whereType<ModificaDalTelefonoCoach>(), hasLength(1));
    });

    test('un messaggio vuoto o con l\'id di un altro si rifiuta', () async {
      await expectLater(
        cliente.inviaMessaggioCoach(atletaId, nuovoUuid(), '   '),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 400)),
      );
      await expectLater(
        cliente.inviaMessaggioCoach(atletaId, 'non-uuid', 'Ciao'),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 400)),
      );
      final altro = nuovoUuid();
      await telefono.sincronizza(messaggi: [dalAtleta('Mio', id: altro)]);
      await expectLater(
        cliente.inviaMessaggioCoach(atletaId, altro, 'Ciao'),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 409)),
      );
    });

    test('i messaggi si leggono a pagine e si segnano letti', () async {
      for (var i = 0; i < 205; i++) {
        a.nucleo.messaggi.invia(atletaId, 'm$i');
        a.avanza(const Duration(seconds: 1));
      }
      final prima = await cliente.messaggiCoach(atletaId);
      expect(prima.elementi, hasLength(200));
      expect(prima.altri, isTrue);
      expect(prima.elementi.first['testo'], 'm5');
      expect(prima.elementi.last['testo'], 'm204');

      final seconda = await cliente.messaggiCoach(atletaId, prima: prima.elementi.first['id']! as String);
      expect(seconda.elementi.map((m) => m['testo']), ['m0', 'm1', 'm2', 'm3', 'm4']);
      expect(seconda.altri, isFalse);

      await telefono.sincronizza(messaggi: [dalAtleta('Letto?')]);
      expect(a.nucleo.messaggi.nonLetti(atletaId), 1);
      await cliente.segnaLettiCoach(atletaId);
      expect(a.nucleo.messaggi.nonLetti(atletaId), 0);
    });

    test('una pagina non supera il limite della risposta', () async {
      // 200 messaggi da 4000 caratteri di 3 byte sarebbero 2,4 MB.
      for (var i = 0; i < 200; i++) {
        a.nucleo.messaggi.invia(atletaId, '€' * LimitiChat.testo);
        a.avanza(const Duration(seconds: 1));
      }
      final pagina = await cliente.messaggiCoach(atletaId);
      expect(pagina.altri, isTrue);
      expect(pagina.elementi.length, lessThan(200));
    });

    test('allenamenti a pagine, dal più recente', () async {
      for (var i = 0; i < 55; i++) {
        final log = nuovoLog(note: 'n$i');
        log['eseguito_il'] = '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}T0${i % 10}:00:00+02:00';
        await telefono.sincronizza(daInviare: [log]);
      }
      a.avanza(const Duration(minutes: 2));
      final prima = await cliente.allenamentiCoach(atletaId);
      expect(prima.elementi, hasLength(50));
      expect(prima.altri, isTrue);
      expect(prima.elementi.first['ricevuto_il'], isA<String>());
      final seconda = await cliente.allenamentiCoach(atletaId, prima: prima.elementi.last['id']! as String);
      expect(seconda.elementi, hasLength(5));
      expect(seconda.altri, isFalse);
    });

    test('pesi, questionari e foto', () async {
      await telefono.sincronizza(
        pesi: [
          {'id': nuovoUuid(), 'rev': 1, 'eliminato': false, 'giorno': '2026-10-17', 'kg': 70.5},
        ],
        pesiCondivisi: true,
      );
      expect(await cliente.pesiCoach(atletaId), [
        {'giorno': '2026-10-17', 'kg': 70.5},
      ]);

      final modello = a.nucleo.questionari.creaModello({
        'titolo': 'Check',
        'domande': [
          {'id': nuovoUuid(), 'tipo': 'testo_breve', 'testo': 'Come va?', 'obbligatoria': false},
        ],
      });
      final inviato = a.nucleo.questionari.invia(modello, atletaId);
      final pagina = await cliente.questionariCoach(atletaId);
      expect(pagina.elementi.single['titolo'], 'Check');
      expect(pagina.elementi.single['stato'], 'inviato');

      await cliente.segnaQuestionarioLettoCoach(inviato);
      expect(a.nucleo.questionari.inviato(inviato)!.letto, isTrue);

      await expectLater(
        cliente.fotoCoach(nuovoUuid()),
        throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 404)),
      );
      final idFoto = nuovoUuid();
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9]);
      a.nucleo.questionari.salvaFoto(atletaId, idFoto, jpeg);
      expect(await cliente.fotoCoach(idFoto), jpeg);
    });

    test('attendi: subito se l\'impronta è diversa, altrimenti appena cambia', () async {
      final elenco = await cliente.atletiCoach();
      expect(await cliente.attendiCoach('altra'), isTrue);
      expect(await cliente.attendiCoach(elenco.impronta, attesaS: 0), isFalse);

      final attesa = cliente.attendiCoach(elenco.impronta, attesaS: 10);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      a.nucleo.messaggi.invia(atletaId, 'Dal PC');
      expect(await attesa, isTrue);
      expect((await cliente.atletiCoach()).impronta, isNot(elenco.impronta));
    });
  });
}
