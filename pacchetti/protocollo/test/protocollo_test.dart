import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha3.dart';
import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

Uint8List _esadecimale(String testo) => Uint8List.fromList([
  for (var i = 0; i < testo.length; i += 2)
    int.parse(testo.substring(i, i + 2), radix: 16),
]);

String _inEsadecimale(List<int> byte) =>
    byte.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Map<String, Object?> logDiEsempio() => {
  'id': '3f2b8c1e-5d4a-4b7e-9c2d-1a2b3c4d5e6f',
  'rev': 1,
  'eliminato': false,
  'scheda_id': '0b6f9a52-8c41-4c1d-a7e3-58d2f7e0c9b1',
  'scheda_revisione': 3,
  'seduta_id': '7d1e2f3a-4b5c-4d6e-8f70-81a2b3c4d5e6',
  'eseguito_il': '2026-10-21T18:30:00+02:00',
  'durata_min': 65,
  'rpe': 8,
  'note': 'Buone sensazioni',
  'esercizi': [
    {
      'esercizio_id': '9a8b7c6d-5e4f-4a3b-9c2d-1e0f9a8b7c6d',
      'nome': 'Squat',
      'note': '',
      'serie': [
        {
          'ripetizioni': 8,
          'carico_kg': 80,
          'durata_s': null,
          'rpe': 7.5,
          'completata': true,
        },
      ],
    },
  ],
  'modificato_il': '2026-10-21T19:40:00+02:00',
};

Map<String, Object?> contenutoSchedaDiEsempio() => {
  'titolo': 'Forza – blocco 2',
  'note': '',
  'valida_dal': '2026-10-20',
  'valida_al': '2026-11-16',
  'sedute': [
    {
      'id': '7d1e2f3a-4b5c-4d6e-8f70-81a2b3c4d5e6',
      'nome': 'Giorno A',
      'esercizi': [
        {
          'id': '9a8b7c6d-5e4f-4a3b-9c2d-1e0f9a8b7c6d',
          'nome': 'Squat',
          'note': 'Pausa di 1 s in buca',
          'prescrizione': [
            {
              'serie': 4,
              'ripetizioni': '6-8',
              'carico': '75% 1RM',
              'recupero_s': 150,
              'rir': '1-2',
            },
          ],
        },
      ],
    },
  ],
};

void main() {
  group('base32', () {
    const vettori = {
      '': '',
      'f': 'my',
      'fo': 'mzxq',
      'foo': 'mzxw6',
      'foob': 'mzxw6yq',
      'fooba': 'mzxw6ytb',
      'foobar': 'mzxw6ytboi',
    };

    test('codifica i vettori di RFC 4648 in minuscolo senza padding', () {
      vettori.forEach((chiaro, codificato) {
        expect(codificaBase32(ascii.encode(chiaro)), codificato);
      });
    });

    test('decodifica minuscolo e maiuscolo', () {
      vettori.forEach((chiaro, codificato) {
        expect(ascii.decode(decodificaBase32(codificato)!), chiaro);
        expect(ascii.decode(decodificaBase32(codificato.toUpperCase())!), chiaro);
      });
    });

    test('rifiuta caratteri estranei e codifiche non canoniche', () {
      expect(decodificaBase32('my='), isNull);
      expect(decodificaBase32('m1'), isNull);
      expect(decodificaBase32('mz'), isNull);
      expect(decodificaBase32('myy'), isNull);
    });

    test('una chiave di 32 byte occupa 52 caratteri', () {
      final chiave = byteCasuali(32);
      final testo = codificaBase32(chiave);
      expect(testo, hasLength(52));
      expect(decodificaChiave32(testo), chiave);
      expect(decodificaChiave32(testo.substring(1)), isNull);
    });
  });

  group('indirizzi onion', () {
    test('SHA3-256 è quello di FIPS 202', () {
      expect(
        _inEsadecimale(SHA3Digest(256).process(Uint8List(0))),
        'a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a',
      );
    });

    test('accetta indirizzi v3 reali', () {
      expect(
        indirizzoOnionValido(
          '2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid',
        ),
        isTrue,
      );
      expect(
        indirizzoOnionValido(
          'duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion',
        ),
        isTrue,
      );
    });

    test('un indirizzo derivato da una chiave restituisce la stessa chiave', () {
      final chiave = byteCasuali(32);
      final indirizzo = indirizzoOnionDaChiave(chiave);
      expect(indirizzo, hasLength(56));
      expect(chiaveDaIndirizzoOnion(indirizzo), chiave);
      expect(chiaveDaIndirizzoOnion('$indirizzo.onion'), chiave);
    });

    test('rifiuta un indirizzo con un carattere cambiato', () {
      const valido = '2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid';
      final alterato = 'a${valido.substring(1)}';
      expect(indirizzoOnionValido(alterato), isFalse);
      expect(indirizzoOnionValido(valido.substring(1)), isFalse);
    });
  });

  test('X25519 rispetta il vettore di RFC 7748', () async {
    final coppia = await CoppiaX25519.daPrivata(
      _esadecimale(
        '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a',
      ),
    );
    expect(
      _inEsadecimale(coppia.pubblica),
      '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a',
    );
  });

  test('genera UUID v4 validi e diversi', () {
    final a = nuovoUuid();
    final b = nuovoUuid();
    expect(uuidValido(a), isTrue);
    expect(a[14], '4');
    expect(a, isNot(b));
    expect(uuidValido(a.toUpperCase()), isFalse);
  });

  group('date', () {
    test('formatta con il fuso orario e si rilegge uguale', () {
      final ora = DateTime.utc(2026, 10, 21, 16, 30);
      final testo = formattaDataOra(ora);
      expect(
        testo,
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$')),
      );
      expect(analizzaDataOra(testo)!.isAtSameMomentAs(ora), isTrue);
    });

    test('rifiuta date impossibili o senza fuso', () {
      expect(analizzaDataOra('2026-02-30T10:00:00Z'), isNull);
      expect(analizzaDataOra('2026-10-21T18:30:00'), isNull);
      expect(analizzaDataOra('2026-10-21T24:00:00Z'), isNull);
      expect(analizzaDataOra('2026-10-21T18:30:00+25:00'), isNull);
      expect(analizzaData('2026-02-29'), isNull);
      expect(analizzaData('2028-02-29'), DateTime.utc(2028, 2, 29));
    });
  });

  test('confronta le versioni per numero, non per testo', () {
    expect(confrontaVersioni('1.10.0', '1.9.3'), greaterThan(0));
    expect(confrontaVersioni('1.0.0', '1.0.0+42'), 0);
    expect(confrontaVersioni('0.9.9', '1.0.0'), lessThan(0));
    expect(versioneValida('1.0'), isFalse);
  });

  group('invito', () {
    Future<UriInvito> nuovoInvito() async {
      final coppia = await CoppiaX25519.genera();
      return UriInvito(
        indirizzo: indirizzoOnionDaChiave(byteCasuali(32)),
        id: codificaBase32(byteCasuali(16)),
        segreto: codificaBase32(byteCasuali(32)),
        chiave: coppia.privataBase32,
      );
    }

    test('si rilegge dal proprio testo', () async {
      final invito = await nuovoInvito();
      final testo = invito.toString();
      expect(testo, startsWith('opencoach://invito?v=1&o='));
      final letto = UriInvito.analizza(' $testo\n');
      expect(letto.indirizzo, invito.indirizzo);
      expect(letto.id, invito.id);
      expect(letto.segreto, invito.segreto);
      expect(letto.chiave, invito.chiave);
    });

    test('distingue una versione futura da un testo non valido', () async {
      final testo = (await nuovoInvito()).toString();
      expect(
        () => UriInvito.analizza(testo.replaceFirst('v=1', 'v=2')),
        throwsA(isA<VersioneInvitoSconosciuta>()),
      );
      for (final sbagliato in [
        'https://example.com',
        testo.replaceFirst('opencoach:', 'altro:'),
        testo.replaceFirst('v=1', 'v=x'),
        testo.replaceFirst('&s=', '&s=a'),
        testo.replaceFirst('&o=', '&o=b'),
      ]) {
        expect(
          () => UriInvito.analizza(sbagliato),
          throwsA(isA<InvitoNonValido>()),
          reason: sbagliato,
        );
      }
    });
  });

  group('validazione dei log', () {
    test('accetta il log di esempio delle specifiche', () {
      expect(validaLog(logDiEsempio()), isEmpty);
    });

    test('accetta un log eliminato con i soli campi obbligatori', () {
      expect(
        validaLog({'id': nuovoUuid(), 'rev': 2, 'eliminato': true}),
        isEmpty,
      );
    });

    test('segnala i campi sbagliati con il loro percorso', () {
      final log = logDiEsempio()
        ..remove('eseguito_il')
        ..['rev'] = 0;
      final serie =
          ((log['esercizi'] as List<Object?>).first as Map<String, Object?>)['serie']
              as List<Object?>;
      (serie.first as Map<String, Object?>)['rpe'] = 7.3;
      expect(
        validaLog(log),
        containsAll([
          'rev: deve essere tra 1 e 2147483647',
          'eseguito_il: obbligatorio',
          'esercizi[0].serie[0].rpe: deve essere un multiplo di 0.5',
        ]),
      );
    });
  });

  group('validazione delle schede', () {
    test('accetta il contenuto di esempio delle specifiche', () {
      expect(validaContenutoScheda(contenutoSchedaDiEsempio()), isEmpty);
    });

    test('accetta una scheda completa come la invia il coach', () {
      final scheda = {
        'id': nuovoUuid(),
        'revisione': 1,
        'stato': 'pubblicata',
        'pubblicata_il': '2026-10-18T21:00:00+02:00',
        ...contenutoSchedaDiEsempio(),
      };
      expect(validaScheda(scheda), isEmpty);
    });

    test('segnala titolo vuoto, date invertite e id ripetuti', () {
      final contenuto = contenutoSchedaDiEsempio()
        ..['titolo'] = '  '
        ..['valida_al'] = '2026-10-01';
      final seduta =
          (contenuto['sedute'] as List<Object?>).first as Map<String, Object?>;
      final esercizio =
          (seduta['esercizi'] as List<Object?>).first as Map<String, Object?>;
      esercizio['id'] = seduta['id'];
      expect(
        validaContenutoScheda(contenuto),
        containsAll([
          'titolo: non può essere vuoto',
          'valida_al: non può precedere valida_dal',
          'sedute[0].esercizi[0].id: id ripetuto',
        ]),
      );
    });

    test('il RIR della prescrizione è un testo breve', () {
      final contenuto = contenutoSchedaDiEsempio();
      final seduta =
          (contenuto['sedute'] as List<Object?>).first as Map<String, Object?>;
      final esercizio =
          (seduta['esercizi'] as List<Object?>).first as Map<String, Object?>;
      final riga =
          (esercizio['prescrizione'] as List<Object?>).first as Map<String, Object?>;
      riga['rir'] = 2;
      expect(validaContenutoScheda(contenuto), [
        'sedute[0].esercizi[0].prescrizione[0].rir: deve essere un testo',
      ]);
      riga['rir'] = 'x' * 21;
      expect(validaContenutoScheda(contenuto), [
        'sedute[0].esercizi[0].prescrizione[0].rir: al massimo 20 caratteri',
      ]);
    });

    test('una scheda senza sedute non si può pubblicare', () {
      expect(
        validaContenutoScheda({'titolo': 'Vuota', 'sedute': <Object?>[]}),
        ['sedute: servono almeno 1 elementi'],
      );
    });
  });

  group('messaggi', () {
    test('la richiesta di abbinamento si rilegge dal proprio JSON', () async {
      final coppia = await CoppiaX25519.genera();
      final richiesta = RichiestaAbbinamento(
        invitoId: codificaBase32(byteCasuali(16)),
        segreto: codificaBase32(byteCasuali(32)),
        chiaveDispositivo: coppia.pubblicaBase32,
        dispositivo: const DatiDispositivo(
          nome: 'Pixel 8',
          piattaforma: 'android',
          versioneApp: '1.0.0',
        ),
      );
      final letta = RichiestaAbbinamento.fromJson(
        jsonDecode(jsonEncode(richiesta.toJson())),
      );
      expect(letta.toJson(), richiesta.toJson());
    });

    test('rifiuta una piattaforma sconosciuta', () {
      expect(
        () => DatiDispositivo.fromJson({
          'nome': 'Telefono',
          'piattaforma': 'symbian',
          'versione_app': '1.0.0',
        }),
        throwsFormatException,
      );
    });

    test('la risposta di sync si rilegge dal proprio JSON', () {
      final risposta = RispostaSync(
        epoca: nuovoUuid(),
        completo: true,
        logAccettati: const [LogConfermato('a', 2)],
        logRifiutati: const [LogRifiutato('b', RifiutoLog.nonValido)],
        schede: [
          {'id': nuovoUuid()},
        ],
        schedeEliminate: [nuovoUuid()],
        log: [logDiEsempio()],
        cursore: '1:i:x:3',
        altro: false,
      );
      final letta = RispostaSync.fromJson(jsonDecode(jsonEncode(risposta.toJson())));
      expect(letta.toJson(), risposta.toJson());
    });
  });

  group('SOCKS5', () {
    late HttpServer destinazione;

    setUp(() async {
      destinazione = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      destinazione.listen((richiesta) {
        richiesta.response
          ..write('ciao da ${richiesta.headers.host}')
          ..close();
      });
    });

    tearDown(() => destinazione.close(force: true));

    test('HttpClient raggiunge un indirizzo .onion attraverso il proxy', () async {
      final host = <String>[];
      final proxy = await _proxySocksFinto(
        portaDestinazione: destinazione.port,
        hostRichiesti: host,
      );
      final http = clienteHttpTramiteTor(socksHost: '127.0.0.1', socksPorta: proxy.port);
      final indirizzo = indirizzoOnionDaChiave(byteCasuali(32));
      final richiesta = await http.getUrl(Uri.parse('http://$indirizzo.onion/prova'));
      final risposta = await richiesta.close();
      expect(await utf8.decodeStream(risposta), 'ciao da $indirizzo.onion');
      expect(host, ['$indirizzo.onion']);
      http.close(force: true);
      await proxy.close();
    });

    test('riporta gli errori estesi degli onion service', () async {
      final proxy = await _proxySocksFinto(
        portaDestinazione: destinazione.port,
        esito: ErroreSocks.descrittoreNonTrovato,
      );
      await expectLater(
        connettiTramiteSocks5(
          host: 'esempio.onion',
          porta: 80,
          proxyHost: '127.0.0.1',
          proxyPorta: proxy.port,
        ),
        throwsA(
          isA<ErroreSocks>()
              .having((e) => e.servizioIrraggiungibile, 'irraggiungibile', isTrue)
              .having((e) => e.autorizzazioneRifiutata, 'autorizzazione', isFalse),
        ),
      );
      await proxy.close();
    });

    test('un proxy che non risponde dà SocketException, come una connessione diretta', () async {
      // Accetta la connessione e poi tace, come Tor quando il rendezvous non
      // si completa.
      final muto = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final aperte = <Socket>[];
      muto.listen(aperte.add);
      final http = clienteHttpTramiteTor(
        socksHost: '127.0.0.1',
        socksPorta: muto.port,
        timeoutConnessione: const Duration(milliseconds: 200),
      );
      await expectLater(
        http.getUrl(Uri.parse('http://esempio.onion/prova')),
        throwsA(isA<SocketException>()),
      );
      http.close(force: true);
      for (final socket in aperte) {
        socket.destroy();
      }
      await muto.close();
    });
  });
}

/// Proxy SOCKS5 minimo per i test: accetta qualsiasi destinazione e la
/// collega a 127.0.0.1:[portaDestinazione], oppure risponde con [esito].
Future<ServerSocket> _proxySocksFinto({
  required int portaDestinazione,
  int esito = 0,
  List<String>? hostRichiesti,
}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((cliente) {
    final buffer = <int>[];
    var fase = 0;
    Socket? uscita;
    cliente.listen(
      (dati) async {
        final collegata = uscita;
        if (collegata != null) {
          collegata.add(dati);
          return;
        }
        buffer.addAll(dati);
        if (fase == 0 && buffer.length >= 3) {
          buffer.removeRange(0, 3);
          cliente.add([5, 0]);
          fase = 1;
        }
        if (fase == 1 && buffer.length >= 5 && buffer.length >= 7 + buffer[4]) {
          final lunghezza = buffer[4];
          hostRichiesti?.add(ascii.decode(buffer.sublist(5, 5 + lunghezza)));
          buffer.removeRange(0, 7 + lunghezza);
          fase = 2;
          if (esito != 0) {
            cliente.add([5, esito, 0, 1, 0, 0, 0, 0, 0, 0]);
            await cliente.close();
            return;
          }
          final nuova = await Socket.connect('127.0.0.1', portaDestinazione);
          uscita = nuova;
          nuova.listen(cliente.add, onDone: cliente.close);
          cliente.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 80]);
        }
      },
      onDone: () => uscita?.close(),
    );
  });
  return server;
}
