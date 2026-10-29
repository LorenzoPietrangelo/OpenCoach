import 'dart:convert';
import 'dart:io';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

import 'supporto.dart';

TypeMatcher<ErroreApi> erroreApi(int stato, String codice) => isA<ErroreApi>()
    .having((e) => e.stato, 'stato', stato)
    .having((e) => e.codice, 'codice', codice);

void main() {
  late Ambiente a;

  setUp(() async => a = await Ambiente.avvia());
  tearDown(() => a.chiudi());

  group('identità', () {
    test('al secondo avvio ritrova lo stesso indirizzo', () async {
      final archivio = Archivio.inMemoria();
      final portachiavi = PortachiaviMemoria();
      final prima = await caricaOCreaIdentita(archivio, portachiavi);
      final seconda = await caricaOCreaIdentita(archivio, portachiavi);
      expect(seconda.indirizzo, prima.indirizzo);
      expect(indirizzoOnionValido(prima.indirizzo), isTrue);
      archivio.chiudi();
    });

    test('senza la chiave del portachiavi non si può leggere', () async {
      final archivio = Archivio.inMemoria();
      await caricaOCreaIdentita(archivio, PortachiaviMemoria());
      await expectLater(
        caricaOCreaIdentita(archivio, PortachiaviMemoria()),
        throwsA(isA<IdentitaIllegibile>()),
      );
      archivio.chiudi();
    });

    test('la chiave per Tor è la chiave espansa di 64 byte', () async {
      final identita = await Identita.genera();
      final chiave = identita.chiaveTor;
      expect(chiave, startsWith('ED25519-V3:'));
      expect(chiave, isNot(contains('=')));
      final byte = base64.decode(base64.normalize(chiave.substring(11)));
      expect(byte, hasLength(64));
      expect(byte[0] & 7, 0);
      expect(byte[31] & 0xc0, 0x40);
    });
  });

  group('server HTTP', () {
    Future<HttpClientResponse> richiesta(
      String metodo,
      String percorso, {
      String? host,
      Map<String, String> intestazioni = const {},
      String? corpo,
    }) async {
      final r = await a.http.openUrl(
        metodo,
        Uri.parse('http://${a.nucleo.indirizzo}.onion$percorso'),
      );
      if (host != null) r.headers.host = host;
      intestazioni.forEach(r.headers.set);
      if (corpo != null) r.write(corpo);
      final risposta = await r.close();
      await risposta.drain<void>();
      return risposta;
    }

    test('/v1/info presenta il coach', () async {
      final info = await a.cliente().info();
      expect(info.nomeCoach, 'Marco Bianchi');
      expect(info.protocollo, [1]);
      expect(info.versioneAppMinima, '1.0.0');
    });

    test('rifiuta un Host diverso dall\'indirizzo onion', () async {
      expect((await richiesta('GET', '/v1/info', host: 'localhost')).statusCode, 421);
    });

    test('rifiuta le richieste dei browser, che mandano Origin', () async {
      final risposta = await richiesta(
        'GET',
        '/v1/info',
        intestazioni: {'origin': 'http://pagina.esempio'},
      );
      expect(risposta.statusCode, 403);
    });

    test('percorsi, metodi, token e JSON sbagliati', () async {
      expect((await richiesta('GET', '/altro')).statusCode, 404);
      expect((await richiesta('GET', '/v1/sync')).statusCode, 405);
      expect((await richiesta('POST', '/v1/sync', corpo: '{}')).statusCode, 401);
      expect(
        (await richiesta('POST', '/v1/abbinamento', corpo: '{non json')).statusCode,
        400,
      );
      expect(
        (await richiesta('POST', '/v1/abbinamento', corpo: '{"invito_id": 3}'))
            .statusCode,
        400,
      );
    });
  });

  group('abbinamento', () {
    test('flusso completo: invito, abbinamento, conferma', () async {
      final atleta = a.nucleo.atleti.crea('Giulia Rossi');
      final telefono = await a.abbinaTelefono(atleta.id);

      expect(telefono.abbinamento.atletaId, atleta.id);
      expect(telefono.abbinamento.nomeAtleta, 'Giulia Rossi');
      expect(telefono.abbinamento.nomeCoach, 'Marco Bianchi');
      expect(
        a.nucleo.chiaviAutorizzate(),
        [telefono.chiave.pubblicaBase32],
        reason: 'dopo la conferma resta solo la chiave del dispositivo',
      );
      expect(a.eventi.whereType<DispositivoAbbinato>().single.atletaId, atleta.id);
      expect(a.eventi.whereType<AbbinamentoConfermato>(), hasLength(1));
      expect(a.nucleo.inviti.inCorso(atleta.id), isNull);
      final riepilogo = a.nucleo.atleti.elenco().single;
      expect(riepilogo.dispositivo?.nome, 'Pixel 8');
    });

    test('prima della conferma restano autorizzate entrambe le chiavi', () async {
      final atleta = a.nucleo.atleti.crea('Luca');
      final invito = await a.nucleo.inviti.crea(atleta.id);
      final chiave = await CoppiaX25519.genera();
      await a.cliente().abbina(_richiesta(invito.uri!, chiave));
      expect(a.nucleo.chiaviAutorizzate(), hasLength(2));
    });

    test('ripetere la richiesta con la stessa chiave dà un token nuovo', () async {
      final atleta = a.nucleo.atleti.crea('Luca');
      final invito = await a.nucleo.inviti.crea(atleta.id);
      final chiave = await CoppiaX25519.genera();
      final prima = await a.cliente().abbina(_richiesta(invito.uri!, chiave));
      final seconda = await a.cliente().abbina(_richiesta(invito.uri!, chiave));
      expect(seconda.dispositivoId, prima.dispositivoId);
      expect(seconda.token, isNot(prima.token));
      await expectLater(
        a.cliente(token: prima.token).confermaAbbinamento(),
        throwsA(erroreApi(401, CodiceErrore.tokenRevocato)),
      );
      await a.cliente(token: seconda.token).confermaAbbinamento();
    });

    test('un secondo telefono con lo stesso invito riceve 409', () async {
      final atleta = a.nucleo.atleti.crea('Luca');
      final invito = await a.nucleo.inviti.crea(atleta.id);
      await a.cliente().abbina(_richiesta(invito.uri!, await CoppiaX25519.genera()));
      await expectLater(
        a.cliente().abbina(_richiesta(invito.uri!, await CoppiaX25519.genera())),
        throwsA(erroreApi(409, CodiceErrore.invitoInUso)),
      );
      expect(a.eventi.whereType<InvitoContestato>(), hasLength(1));
    });

    test('inviti usati, scaduti, annullati o con segreto errato danno 410', () async {
      final atleta = a.nucleo.atleti.crea('Luca');
      final usato = await a.nucleo.inviti.crea(atleta.id);
      final telefono = await a.abbinaTelefono(a.nucleo.atleti.crea('Altro').id);
      expect(telefono, isNotNull);

      final chiave = await CoppiaX25519.genera();
      final sbagliato = UriInvito(
        indirizzo: usato.uri!.indirizzo,
        id: usato.uri!.id,
        segreto: codificaBase32(byteCasuali(32)),
        chiave: usato.uri!.chiave,
      );
      await expectLater(
        a.cliente().abbina(_richiesta(sbagliato, chiave)),
        throwsA(erroreApi(410, CodiceErrore.invitoNonValido)),
      );

      a.nucleo.inviti.annulla(usato.id);
      await expectLater(
        a.cliente().abbina(_richiesta(usato.uri!, chiave)),
        throwsA(erroreApi(410, CodiceErrore.invitoNonValido)),
      );

      final scaduto = await a.nucleo.inviti.crea(atleta.id);
      a.avanza(const Duration(days: 8));
      await expectLater(
        a.cliente().abbina(_richiesta(scaduto.uri!, chiave)),
        throwsA(erroreApi(410, CodiceErrore.invitoNonValido)),
      );
      expect(a.nucleo.inviti.chiudiScaduti(), 1);
      expect(a.nucleo.chiaviAutorizzate(), [telefono.chiave.pubblicaBase32]);
    });

    test('un nuovo invito annulla il precedente', () async {
      final atleta = a.nucleo.atleti.crea('Luca');
      final primo = await a.nucleo.inviti.crea(atleta.id);
      final secondo = await a.nucleo.inviti.crea(atleta.id);
      expect(a.nucleo.inviti.inCorso(atleta.id)?.id, secondo.id);
      expect(a.nucleo.chiaviAutorizzate(), hasLength(1));
      await expectLater(
        a.cliente().abbina(_richiesta(primo.uri!, await CoppiaX25519.genera())),
        throwsA(erroreApi(410, CodiceErrore.invitoNonValido)),
      );
    });

    test('il nuovo telefono sostituisce il vecchio', () async {
      final atleta = a.nucleo.atleti.crea('Luca');
      final vecchio = await a.abbinaTelefono(atleta.id, nome: 'Vecchio');
      final nuovo = await a.abbinaTelefono(atleta.id, nome: 'Nuovo');
      await expectLater(
        vecchio.sincronizza(),
        throwsA(erroreApi(401, CodiceErrore.tokenRevocato)),
      );
      await nuovo.sincronizza();
      expect(a.nucleo.chiaviAutorizzate(), [nuovo.chiave.pubblicaBase32]);
      expect(a.nucleo.dispositivi.attivo(atleta.id)?.nome, 'Nuovo');
    });

    test('app troppo vecchia: 426', () async {
      final atleta = a.nucleo.atleti.crea('Luca');
      final invito = await a.nucleo.inviti.crea(atleta.id);
      final richiesta = _richiesta(
        invito.uri!,
        await CoppiaX25519.genera(),
        versioneApp: '0.9.0',
      );
      await expectLater(
        a.cliente().abbina(richiesta),
        throwsA(erroreApi(426, CodiceErrore.aggiornaApp)),
      );
    });

    test('revoca dal coach, scollegamento dall\'app, atleta eliminato', () async {
      final primo = await a.abbinaTelefono(a.nucleo.atleti.crea('Uno').id);
      final secondo = await a.abbinaTelefono(a.nucleo.atleti.crea('Due').id);
      final terzoAtleta = a.nucleo.atleti.crea('Tre');
      final terzo = await a.abbinaTelefono(terzoAtleta.id);

      a.nucleo.dispositivi.revoca(primo.abbinamento.dispositivoId);
      await secondo.cliente.scollega();
      a.nucleo.atleti.elimina(terzoAtleta.id);

      for (final telefono in [primo, secondo, terzo]) {
        await expectLater(
          telefono.sincronizza(),
          throwsA(erroreApi(401, CodiceErrore.tokenRevocato)),
        );
      }
      expect(a.nucleo.chiaviAutorizzate(), isEmpty);
      expect(a.nucleo.atleti.cerca(terzoAtleta.id), isNull);
    });

    test('limite di 10 abbinamenti al minuto', () async {
      final atleta = a.nucleo.atleti.crea('Luca');
      final invito = await a.nucleo.inviti.crea(atleta.id);
      final finto = UriInvito(
        indirizzo: invito.uri!.indirizzo,
        id: invito.uri!.id,
        segreto: codificaBase32(byteCasuali(32)),
        chiave: invito.uri!.chiave,
      );
      final chiave = await CoppiaX25519.genera();
      for (var i = 0; i < 10; i++) {
        await expectLater(
          a.cliente().abbina(_richiesta(finto, chiave)),
          throwsA(erroreApi(410, CodiceErrore.invitoNonValido)),
        );
      }
      await expectLater(
        a.cliente().abbina(_richiesta(invito.uri!, chiave)),
        throwsA(
          erroreApi(429, CodiceErrore.troppeRichieste).having(
            (e) => e.riprovaTra,
            'riprovaTra',
            const Duration(seconds: 60),
          ),
        ),
      );
      a.avanza(const Duration(minutes: 1));
      await a.cliente().abbina(_richiesta(invito.uri!, chiave));
    });
  });

  group('schede', () {
    late String atletaId;

    setUp(() => atletaId = a.nucleo.atleti.crea('Giulia').id);

    test('una bozza incompleta non si pubblica', () {
      final id = a.nucleo.schede.crea(atletaId);
      expect(
        () => a.nucleo.schede.pubblica(id),
        throwsA(isA<SchedaNonValida>()),
      );
    });

    test('la bozza ricorda se ci sono modifiche non pubblicate', () {
      final id = a.nucleo.schede.crea(atletaId, contenuto: contenutoScheda('A'));
      expect(a.nucleo.schede.pubblica(id), 1);
      expect(a.nucleo.schede.cerca(id)!.modificheNonPubblicate, isFalse);
      a.nucleo.schede.salvaBozza(id, contenutoScheda('B'));
      expect(a.nucleo.schede.cerca(id)!.modificheNonPubblicate, isTrue);
      expect(a.nucleo.schede.pubblica(id), 2);
      final scheda = a.nucleo.schede.cerca(id)!;
      expect(scheda.titolo, 'B');
      expect(scheda.revisioni.map((r) => r.numero), [2, 1]);
    });

    test('la copia ha id nuovi per sedute ed esercizi', () {
      final id = a.nucleo.schede.crea(atletaId, contenuto: contenutoScheda('A'));
      final altro = a.nucleo.atleti.crea('Luca').id;
      final copia = a.nucleo.schede.cerca(
        a.nucleo.schede.duplica(id, atletaId: altro),
      )!;
      final originale = a.nucleo.schede.cerca(id)!;
      expect(copia.atletaId, altro);
      expect(copia.titolo, 'A');
      expect(_idSedute(copia.bozza), isNot(_idSedute(originale.bozza)));
      expect(a.nucleo.schede.cerca(a.nucleo.schede.duplica(id))!.titolo, 'A (copia)');
    });
  });

  group('libreria', () {
    late String atletaId;
    const video1 = 'https://www.youtube.com/watch?v=uno';
    const video2 = 'https://www.youtube.com/watch?v=due';

    setUp(() => atletaId = a.nucleo.atleti.crea('Giulia').id);

    Object? videoPubblicato(String schedaId) {
      final scheda = a.nucleo.schede.cerca(schedaId)!;
      final contenuto = a.nucleo.schede.contenutoRevisione(schedaId, scheda.revisione)!;
      final seduta = (contenuto['sedute'] as List<Object?>).first as Map<String, Object?>;
      final esercizio = (seduta['esercizi'] as List<Object?>).first as Map<String, Object?>;
      return esercizio['video'];
    }

    test('la scheda pubblicata prende il video dall\'esercizio con lo stesso nome', () {
      a.nucleo.libreria.salva(nome: ' squat ', note: 'Petto alto', video: video1);
      expect(a.nucleo.libreria.perNome('SQUAT')!.nome, 'squat');
      final id = a.nucleo.schede.crea(atletaId, contenuto: contenutoScheda('A'));
      a.nucleo.schede.pubblica(id);
      expect(videoPubblicato(id), video1);
      expect(a.nucleo.schede.cerca(id)!.bozza.toString(), isNot(contains(video1)));
      expect(a.nucleo.schede.cerca(id)!.modificheNonPubblicate, isFalse);
    });

    test('nome doppio, link non https e nome vuoto si rifiutano', () {
      a.nucleo.libreria.salva(nome: 'Squat');
      for (final salva in [
        () => a.nucleo.libreria.salva(nome: 'SQUAT'),
        () => a.nucleo.libreria.salva(nome: 'Panca', video: 'http://esempio.it/v'),
        () => a.nucleo.libreria.salva(nome: '  '),
      ]) {
        expect(salva, throwsA(isA<OperazioneNonValida>()));
      }
      expect(a.nucleo.libreria.elenco(), hasLength(1));
    });

    test('un video cambiato si ripubblica senza le modifiche della bozza', () {
      final esercizio = a.nucleo.libreria.salva(nome: 'Squat', video: video1);
      final id = a.nucleo.schede.crea(atletaId, contenuto: contenutoScheda('A'));
      a.nucleo.schede.pubblica(id);
      a.nucleo.schede.salvaBozza(id, contenutoScheda('B'));
      final altra = a.nucleo.schede.crea(atletaId, contenuto: contenutoScheda('C'));
      a.nucleo.schede.pubblica(altra);
      expect(a.nucleo.schede.conVideoDaAggiornare(), isEmpty);

      a.nucleo.libreria.salva(id: esercizio, nome: 'Squat', video: video2);
      expect(a.nucleo.schede.cerca(altra)!.modificheNonPubblicate, isTrue);
      expect(
        a.nucleo.schede.conVideoDaAggiornare().map((s) => s.id),
        unorderedEquals([id, altra]),
      );

      expect(a.nucleo.schede.aggiornaVideo(id), 2);
      expect(videoPubblicato(id), video2);
      final scheda = a.nucleo.schede.cerca(id)!;
      expect(
        a.nucleo.schede.contenutoRevisione(id, 2)!['titolo'],
        'A',
        reason: 'la bozza B non si pubblica',
      );
      expect(scheda.modificheNonPubblicate, isTrue);
      expect(a.nucleo.schede.aggiornaVideo(id), isNull);

      a.nucleo.schede.aggiornaVideo(altra);
      expect(a.nucleo.schede.cerca(altra)!.modificheNonPubblicate, isFalse);
      expect(a.nucleo.schede.conVideoDaAggiornare(), isEmpty);

      a.nucleo.libreria.elimina(esercizio);
      a.nucleo.schede.aggiornaVideo(altra);
      expect(videoPubblicato(altra), isNull);
    });
  });

  group('sincronizzazione', () {
    late String atletaId;
    late TelefonoFinto telefono;

    setUp(() async {
      atletaId = a.nucleo.atleti.crea('Giulia').id;
      telefono = await a.abbinaTelefono(atletaId);
    });

    test('pesi: salvati, corretti, eliminati e cancellati se l\'atleta smette di condividerli', () async {
      Map<String, Object?> peso(String id, int rev, String giorno, num kg) => {
        'id': id,
        'rev': rev,
        'eliminato': false,
        'giorno': giorno,
        'kg': kg,
      };
      final lunedi = nuovoUuid();
      final martedi = nuovoUuid();
      var risposta = (await telefono.sincronizza(
        pesi: [
          peso(lunedi, 1, '2026-10-26', 72.4),
          peso(martedi, 1, '2026-10-27', 72),
          {'id': 'non-valido', 'rev': 1, 'eliminato': false},
        ],
        pesiCondivisi: true,
      )).first;
      expect([for (final p in risposta.pesiAccettati!) p.id], [lunedi, martedi]);
      expect(
        [for (final p in a.nucleo.pesi.elenco(atletaId)) (p.giorno.day, p.kg)],
        [(26, 72.4), (27, 72.0)],
      );

      // Una rev più vecchia si conferma senza cambiare il valore.
      await telefono.sincronizza(pesi: [peso(lunedi, 2, '2026-10-26', 71.9)]);
      risposta = (await telefono.sincronizza(pesi: [peso(lunedi, 1, '2026-10-26', 99)])).single;
      expect(risposta.pesiAccettati!.single.rev, 1);
      expect(a.nucleo.pesi.elenco(atletaId).first.kg, 71.9);
      await telefono.sincronizza(
        pesi: [
          {'id': martedi, 'rev': 2, 'eliminato': true},
        ],
      );
      expect(a.nucleo.pesi.elenco(atletaId), hasLength(1));

      // Lo stato completo elenca id e rev, anche delle lapidi.
      telefono.cursore = null;
      risposta = (await telefono.sincronizza()).single;
      expect(
        {for (final p in risposta.pesi) p.id: p.rev},
        {lunedi: 2, martedi: 2},
      );

      // Un'app vecchia non dice nulla e non tocca i pesi.
      await telefono.sincronizza();
      expect(a.nucleo.pesi.elenco(atletaId), hasLength(1));
      await telefono.sincronizza(pesiCondivisi: false);
      expect(a.nucleo.pesi.elenco(atletaId), isEmpty);
      telefono.cursore = null;
      expect((await telefono.sincronizza()).single.pesi, isEmpty);
    });

    test('la prima sync è completa e non contiene le bozze', () async {
      final pubblicata = a.nucleo.schede.crea(atletaId, contenuto: contenutoScheda('A'));
      a.nucleo.schede.pubblica(pubblicata);
      a.nucleo.schede.crea(atletaId, contenuto: contenutoScheda('Bozza'));
      final altroAtleta = a.nucleo.atleti.crea('Luca').id;
      a.nucleo.schede.pubblica(
        a.nucleo.schede.crea(altroAtleta, contenuto: contenutoScheda('Altrui')),
      );

      final risposte = await telefono.sincronizza();
      expect(risposte.single.completo, isTrue);
      expect(telefono.schede.keys, [pubblicata]);
      final scheda = telefono.schede[pubblicata]!;
      expect(validaScheda(scheda), isEmpty);
      expect(scheda['revisione'], 1);
      expect(scheda['stato'], 'pubblicata');
      expect(telefono.cursore, startsWith('1:i:'));
    });

    test('le sync successive portano solo le modifiche', () async {
      final id = a.nucleo.schede.crea(atletaId, contenuto: contenutoScheda('A'));
      a.nucleo.schede.pubblica(id);
      await telefono.sincronizza();

      var risposta = (await telefono.sincronizza()).single;
      expect(risposta.completo, isFalse);
      expect(risposta.schede, isEmpty);

      a.nucleo.schede.salvaBozza(id, contenutoScheda('A2'));
      risposta = (await telefono.sincronizza()).single;
      expect(risposta.schede, isEmpty, reason: 'la bozza non è pubblicata');

      a.nucleo.schede.pubblica(id);
      risposta = (await telefono.sincronizza()).single;
      expect(risposta.schede.single['titolo'], 'A2');
      expect(telefono.schede[id]!['revisione'], 2);

      a.nucleo.schede.archivia(id);
      await telefono.sincronizza();
      expect(telefono.schede[id]!['stato'], 'archiviata');

      a.nucleo.schede.elimina(id);
      risposta = (await telefono.sincronizza()).single;
      expect(risposta.schedeEliminate, [id]);
      expect(telefono.schede, isEmpty);
    });

    test('registra quando l\'atleta riceve una revisione', () async {
      final id = a.nucleo.schede.crea(atletaId, contenuto: contenutoScheda('A'));
      a.nucleo.schede.pubblica(id);
      await telefono.sincronizza();
      expect(a.nucleo.schede.cerca(id)!.revisioni.single.ricevutaIl, isNull);

      // La sync successiva conferma il cursore, quindi la ricezione.
      await telefono.sincronizza();
      expect(a.nucleo.schede.cerca(id)!.revisioni.single.ricevutaIl, isNotNull);
      expect(
        a.eventi.whereType<RevisioneRicevuta>().single.revisione,
        1,
      );

      // Due revisioni pubblicate tra una sync e l'altra: arriva solo l'ultima.
      a.nucleo.schede.pubblica(id);
      a.nucleo.schede.pubblica(id);
      await telefono.sincronizza();
      await telefono.sincronizza();
      final revisioni = a.nucleo.schede.cerca(id)!.revisioni;
      expect(revisioni.map((r) => r.numero), [3, 2, 1]);
      expect(revisioni[0].ricevutaIl, isNotNull);
      expect(revisioni[1].ricevutaIl, isNull);
    });

    test('salva i log una volta sola e tiene la revisione più alta', () async {
      final log = nuovoLog(note: 'prima');
      var risposta = (await telefono.sincronizza(daInviare: [log])).single;
      expect(risposta.logAccettati.single.rev, 1);
      expect(a.eventi.whereType<LogRicevuto>(), hasLength(1));

      // La stessa revisione ripetuta (risposta persa) non duplica nulla.
      risposta = (await telefono.sincronizza(daInviare: [log])).single;
      expect(risposta.logAccettati.single.rev, 1);
      expect(a.eventi.whereType<LogRicevuto>(), hasLength(1));

      final modificato = {...log, 'rev': 2, 'note': 'dopo'};
      await telefono.sincronizza(daInviare: [modificato]);
      // Una revisione vecchia arrivata in ritardo viene confermata ma ignorata.
      await telefono.sincronizza(daInviare: [log]);
      final salvato = a.nucleo.allenamenti.elenco(atletaId).single;
      expect(salvato.rev, 2);
      expect(salvato.contenuto['note'], 'dopo');

      await telefono.sincronizza(
        daInviare: [
          {'id': log['id'], 'rev': 3, 'eliminato': true},
        ],
      );
      expect(a.nucleo.allenamenti.elenco(atletaId), isEmpty);
    });

    test('rifiuta i log non validi senza bloccare gli altri', () async {
      final altro = await a.abbinaTelefono(a.nucleo.atleti.crea('Luca').id);
      final suo = nuovoLog();
      await altro.sincronizza(daInviare: [suo]);

      final buono = nuovoLog();
      final senzaData = nuovoLog()..remove('eseguito_il');
      // Oltre i 64 KiB il log è scartato prima ancora di validarlo.
      final enorme = nuovoLog(note: 'x' * 70000);
      final risposta = (await telefono.sincronizza(
        daInviare: [buono, senzaData, enorme, {...suo, 'rev': 2}, 'testo'],
      )).single;
      expect(risposta.logAccettati.map((l) => l.id), [buono['id']]);
      expect({for (final r in risposta.logRifiutati) r.id: r.errore}, {
        senzaData['id']: RifiutoLog.nonValido,
        enorme['id']: RifiutoLog.troppoGrande,
        suo['id']: RifiutoLog.altroAtleta,
        '': RifiutoLog.nonValido,
      });
    });

    test('più di 100 log in una richiesta: 413', () async {
      await expectLater(
        telefono.sincronizza(daInviare: List.generate(101, (_) => nuovoLog())),
        throwsA(erroreApi(413, CodiceErrore.troppoGrande)),
      );
    });

    test('app troppo vecchia: 426', () async {
      await expectLater(
        telefono.sincronizza(versioneApp: '0.1.0'),
        throwsA(erroreApi(426, CodiceErrore.aggiornaApp)),
      );
    });

    test('limite di 30 richieste al minuto per dispositivo', () async {
      final richiesta = RichiestaSync(
        epoca: null,
        cursore: null,
        log: const [],
        versioneApp: '1.0.0',
      );
      // Una richiesta l'ha già fatta la conferma dell'abbinamento.
      for (var i = 0; i < 29; i++) {
        await telefono.cliente.sincronizza(richiesta);
      }
      await expectLater(
        telefono.cliente.sincronizza(richiesta),
        throwsA(erroreApi(429, CodiceErrore.troppeRichieste)),
      );
    });

    test('il log ricorda la revisione e la seduta prescritta', () async {
      final sedutaId = nuovoUuid();
      final id = a.nucleo.schede.crea(
        atletaId,
        contenuto: contenutoScheda('A', sedutaId: sedutaId),
      );
      a.nucleo.schede.pubblica(id);
      await telefono.sincronizza(
        daInviare: [nuovoLog(schedaId: id, revisione: 1, sedutaId: sedutaId)],
      );
      var allenamento = a.nucleo.allenamenti.elenco(atletaId).single;
      expect(allenamento.revisioneNonAttuale, isFalse);
      expect(a.nucleo.allenamenti.sedutaPrescritta(allenamento)?['nome'], 'Giorno A');

      a.nucleo.schede.salvaBozza(id, contenutoScheda('A2', sedutaId: sedutaId));
      a.nucleo.schede.pubblica(id);
      allenamento = a.nucleo.allenamenti.elenco(atletaId).single;
      expect(allenamento.revisioneNonAttuale, isTrue);
      expect(a.nucleo.allenamenti.sedutaPrescritta(allenamento), isNotNull);
    });

    test('dopo un ripristino lo stato completo permette di riallinearsi', () async {
      final perso = nuovoLog();
      final salvato = nuovoLog();
      await telefono.sincronizza(daInviare: [salvato, perso]);
      // Simula un backup precedente all'arrivo di `perso`.
      a.archivio.db.execute('DELETE FROM log WHERE id = ?', [perso['id']]);
      a.archivio.rigeneraEpoca();

      final risposta = (await telefono.sincronizza()).single;
      expect(risposta.completo, isTrue);
      expect(telefono.log.keys, [salvato['id']]);
      // L'app rimanda i log assenti dalla risposta.
      await telefono.sincronizza(daInviare: [perso]);
      expect(a.nucleo.allenamenti.elenco(atletaId), hasLength(2));
    });

    test('un telefono nuovo riceve lo storico, eliminati compresi', () async {
      final eliminato = nuovoLog();
      await telefono.sincronizza(daInviare: [nuovoLog(), eliminato]);
      await telefono.sincronizza(
        daInviare: [
          {'id': eliminato['id'], 'rev': 2, 'eliminato': true},
        ],
      );
      final nuovo = await a.abbinaTelefono(atletaId, nome: 'Nuovo');
      await nuovo.sincronizza();
      expect(nuovo.log, hasLength(2));
      expect(nuovo.log[eliminato['id']], {
        'id': eliminato['id'],
        'rev': 2,
        'eliminato': true,
      });
    });
  });

  group('paginazione', () {
    test('stato completo e modifiche arrivano su più pagine', () async {
      await a.chiudi();
      a = await Ambiente.avvia(budgetPagina: 3000);
      final atletaId = a.nucleo.atleti.crea('Giulia').id;
      final telefono = await a.abbinaTelefono(atletaId);
      final schede = <String>[];
      for (var i = 0; i < 6; i++) {
        final id = a.nucleo.schede.crea(
          atletaId,
          contenuto: contenutoScheda('Scheda $i', note: 'n' * 1000),
        );
        a.nucleo.schede.pubblica(id);
        schede.add(id);
      }
      final log = [for (var i = 0; i < 20; i++) nuovoLog(note: 'l' * 300)];
      await telefono.sincronizza(daInviare: log);

      // Un telefono nuovo riceve tutto lo stato in più pagine.
      final nuovo = await a.abbinaTelefono(atletaId, nome: 'Nuovo');
      final risposte = await nuovo.sincronizza();
      expect(risposte.length, greaterThan(2));
      expect(risposte.every((r) => r.completo), isTrue);
      expect(nuovo.schede.keys.toSet(), schede.toSet());
      expect(nuovo.log.keys.toSet(), {for (final l in log) l['id']});

      // Le modifiche incrementali si dividono allo stesso modo.
      for (final id in schede) {
        a.nucleo.schede.pubblica(id);
      }
      final incrementali = await nuovo.sincronizza();
      expect(incrementali.length, greaterThan(1));
      expect(incrementali.any((r) => r.completo), isFalse);
      expect(nuovo.schede.values.map((s) => s['revisione']).toSet(), {2});
      expect((await nuovo.sincronizza()).single.schede, isEmpty);
    });
  });
}

RichiestaAbbinamento _richiesta(
  UriInvito invito,
  CoppiaX25519 chiave, {
  String versioneApp = '1.0.0',
}) => RichiestaAbbinamento(
  invitoId: invito.id,
  segreto: invito.segreto,
  chiaveDispositivo: chiave.pubblicaBase32,
  dispositivo: DatiDispositivo(
    nome: 'Telefono',
    piattaforma: 'ios',
    versioneApp: versioneApp,
  ),
);

List<Object?> _idSedute(Map<String, Object?> bozza) => [
  for (final s in bozza['sedute'] as List<Object?>) (s as Map<String, Object?>)['id'],
];
