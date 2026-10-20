import 'dart:convert';
import 'dart:io';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:path/path.dart' as p;
import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

import 'supporto.dart';

/// Argon2id veloce per i test: i parametri veri chiedono qualche secondo.
const _rapidi = ParametriArgon2(memoria: 256, iterazioni: 1);

void main() {
  late Directory cartella;

  setUp(() async => cartella = await Directory.systemTemp.createTemp('opencoach_backup_test_'));
  tearDown(() => cartella.delete(recursive: true));

  Future<ProgrammaCoach> avvia(String nome, Portachiavi portachiavi) =>
      ProgrammaCoach.avvia(
        cartellaDati: p.join(cartella.path, nome),
        portachiavi: portachiavi,
        parametriBackup: _rapidi,
      );

  /// Client diretto verso il server locale del programma, al posto di Tor.
  ClienteApi cliente(ProgrammaCoach programma, {String? token}) => ClienteApi(
    indirizzo: programma.indirizzo,
    http: HttpClient()
      ..connectionFactory = (uri, proxyHost, proxyPort) =>
          Socket.startConnect('127.0.0.1', programma.portaLocale),
    token: token,
  );

  Future<RispostaAbbinamento> abbina(ProgrammaCoach programma, String atletaId) async {
    final invito = (await programma.nucleo.inviti.crea(atletaId)).uri!;
    final api = cliente(programma);
    final risposta = await api.abbina(
      RichiestaAbbinamento(
        invitoId: invito.id,
        segreto: invito.segreto,
        chiaveDispositivo: (await CoppiaX25519.genera()).pubblicaBase32,
        dispositivo: const DatiDispositivo(
          nome: 'Pixel 8',
          piattaforma: 'android',
          versioneApp: '1.0.0',
        ),
      ),
    );
    api.token = risposta.token;
    await api.confermaAbbinamento();
    return risposta;
  }

  Future<RispostaSync> sincronizza(
    ClienteApi api, {
    String? epoca,
    String? cursore,
    List<Object?> log = const [],
  }) => api.sincronizza(
    RichiestaSync(epoca: epoca, cursore: cursore, log: log, versioneApp: '1.0.0'),
  );

  group('backup e ripristino', () {
    test('un altro PC riparte con lo stesso indirizzo e i telefoni si riallineano', () async {
      final primo = await avvia('primo', PortachiaviMemoria());
      primo.nucleo.nomeCoach = 'Marco';
      final atleta = primo.nucleo.atleti.crea('Giulia');
      final telefono = await abbina(primo, atleta.id);
      final api = cliente(primo, token: telefono.token);
      final salvato = nuovoLog();
      final iniziale = await sincronizza(api, log: [salvato]);

      await primo.backup.configura(
        passphrase: 'una passphrase lunga',
        cartella: p.join(cartella.path, 'backup'),
      );
      final file = await primo.backup.esegui();
      // Questo log arriva dopo il backup: sul PC nuovo mancherà.
      final perso = nuovoLog();
      await sincronizza(api, epoca: iniziale.epoca, cursore: iniziale.cursore, log: [perso]);
      final indirizzo = primo.indirizzo;
      await primo.chiudi();

      final portachiavi = PortachiaviMemoria();
      final esito = await ProgrammaCoach.ripristina(
        file: file.path,
        passphrase: 'una passphrase lunga',
        cartellaDati: p.join(cartella.path, 'secondo'),
        portachiavi: portachiavi,
      );
      expect(esito.indirizzo, indirizzo);

      final secondo = await avvia('secondo', portachiavi);
      addTearDown(secondo.chiudi);
      expect(secondo.indirizzo, indirizzo);
      expect(secondo.nucleo.nomeCoach, 'Marco');
      expect(await secondo.backup.configurato(), isTrue);
      expect(secondo.nucleo.allenamenti.elenco(atleta.id).map((a) => a.id), [salvato['id']]);

      // Il telefono usa ancora il suo token: riceve lo stato completo
      // perché l'epoca è cambiata, poi rimanda il log che mancava.
      final dopo = cliente(secondo, token: telefono.token);
      final riallineamento = await sincronizza(dopo, epoca: iniziale.epoca, cursore: iniziale.cursore);
      expect(riallineamento.completo, isTrue);
      expect(riallineamento.epoca, isNot(iniziale.epoca));
      expect(riallineamento.log.map((l) => l['id']), [salvato['id']]);
      await sincronizza(dopo, epoca: riallineamento.epoca, cursore: riallineamento.cursore, log: [perso]);
      expect(secondo.nucleo.allenamenti.elenco(atleta.id), hasLength(2));
    });

    test('passphrase sbagliata, file estraneo, programma avviato', () async {
      final programma = await avvia('coach', PortachiaviMemoria());
      final file = p.join(cartella.path, 'manuale.ocbackup');
      await programma.backup.salvaIn(file, passphrase: 'passphrase giusta');
      final destinazione = p.join(cartella.path, 'altro');

      await expectLater(
        ProgrammaCoach.ripristina(
          file: file,
          passphrase: 'passphrase sbagliata',
          cartellaDati: destinazione,
          portachiavi: PortachiaviMemoria(),
        ),
        throwsA(isA<PassphraseErrata>()),
      );

      final estraneo = File(p.join(cartella.path, 'estraneo.ocbackup'))
        ..writeAsBytesSync(utf8.encode('non sono un backup'));
      await expectLater(
        ProgrammaCoach.ripristina(
          file: estraneo.path,
          passphrase: 'passphrase giusta',
          cartellaDati: destinazione,
          portachiavi: PortachiaviMemoria(),
        ),
        throwsA(isA<BackupNonValido>()),
      );

      // Un byte cambiato nel contenuto cifrato invalida il MAC.
      final alterato = File(file).readAsBytesSync();
      alterato[alterato.length - 20] ^= 1;
      final fileAlterato = File(p.join(cartella.path, 'alterato.ocbackup'))
        ..writeAsBytesSync(alterato);
      await expectLater(
        ProgrammaCoach.ripristina(
          file: fileAlterato.path,
          passphrase: 'passphrase giusta',
          cartellaDati: destinazione,
          portachiavi: PortachiaviMemoria(),
        ),
        throwsA(isA<PassphraseErrata>()),
      );

      await expectLater(
        ProgrammaCoach.ripristina(
          file: file,
          passphrase: 'passphrase giusta',
          cartellaDati: programma.cartellaDati,
          portachiavi: PortachiaviMemoria(),
        ),
        throwsA(isA<ProgrammaGiaAvviato>()),
      );
      await programma.chiudi();
    });

    test('i backup automatici rispettano l\'intervallo e restano gli ultimi 5', () async {
      final archivio = Archivio.inMemoria();
      addTearDown(archivio.chiudi);
      final identita = await Identita.genera();
      var ora = DateTime.utc(2026, 10, 1, 9);
      final backup = GestioneBackup(
        archivio: archivio,
        identita: () => identita,
        portachiavi: PortachiaviMemoria(),
        versioneProgramma: '1.0.0',
        adesso: () => ora,
        parametri: _rapidi,
      );
      final destinazione = p.join(cartella.path, 'automatici');

      expect(await backup.eseguiSeDovuto(), isNull, reason: 'non ancora configurato');
      expect(backup.serveUnBackup, isTrue);
      await expectLater(
        backup.configura(passphrase: 'corta', cartella: destinazione),
        throwsA(isA<OperazioneNonValida>()),
      );
      await backup.configura(
        passphrase: 'abbastanza lunga',
        cartella: destinazione,
        intervallo: const Duration(days: 1),
      );

      for (var giorno = 0; giorno < 7; giorno++) {
        expect(await backup.eseguiSeDovuto(), isNotNull);
        ora = ora.add(const Duration(hours: 12));
        expect(await backup.eseguiSeDovuto(), isNull, reason: 'intervallo non passato');
        ora = ora.add(const Duration(hours: 12));
      }
      final file = Directory(destinazione).listSync().map((e) => p.basename(e.path)).toList()..sort();
      expect(file, hasLength(backupDaConservare));
      expect(file.first, startsWith('opencoach-20261003-'));
      expect(backup.serveUnBackup, isFalse);
      ora = ora.add(const Duration(days: 31));
      expect(backup.serveUnBackup, isTrue);
    });
  });

  test('reimpostare l\'identità cambia indirizzo e scollega tutti', () async {
    final portachiavi = PortachiaviMemoria();
    final programma = await avvia('coach', portachiavi);
    final atleta = programma.nucleo.atleti.crea('Giulia');
    final telefono = await abbina(programma, atleta.id);
    await programma.nucleo.inviti.crea(programma.nucleo.atleti.crea('Luca').id);
    final vecchio = programma.indirizzo;
    final epoca = programma.nucleo.contesto.archivio.epoca;

    await programma.reimpostaIdentita();
    expect(programma.indirizzo, isNot(vecchio));
    expect(programma.nucleo.indirizzo, programma.indirizzo);
    expect(programma.nucleo.chiaviAutorizzate(), isEmpty);
    expect(programma.nucleo.contesto.archivio.epoca, isNot(epoca));
    expect(
      (await programma.nucleo.inviti.crea(atleta.id)).uri!.indirizzo,
      programma.indirizzo,
    );
    await expectLater(
      sincronizza(cliente(programma, token: telefono.token)),
      throwsA(isA<ErroreApi>().having((e) => e.stato, 'stato', 401)),
    );

    // Al riavvio l'identità nuova si rilegge dal portachiavi.
    final cartellaDati = programma.cartellaDati;
    final indirizzo = programma.indirizzo;
    await programma.chiudi();
    final riaperto = await ProgrammaCoach.avvia(
      cartellaDati: cartellaDati,
      portachiavi: portachiavi,
    );
    expect(riaperto.indirizzo, indirizzo);
    await riaperto.chiudi();
  });

  test('con l\'identità illeggibile si riparte con una nuova, tenendo i dati', () async {
    final programma = await avvia('coach', PortachiaviMemoria());
    final atleta = programma.nucleo.atleti.crea('Giulia');
    await abbina(programma, atleta.id);
    final vecchio = programma.indirizzo;
    final cartellaDati = programma.cartellaDati;
    await programma.chiudi();

    // Il portachiavi del sistema è stato azzerato.
    final azzerato = PortachiaviMemoria();
    await expectLater(
      ProgrammaCoach.avvia(cartellaDati: cartellaDati, portachiavi: azzerato),
      throwsA(isA<IdentitaIllegibile>()),
    );
    await ProgrammaCoach.sostituisciIdentitaIllegibile(
      cartellaDati: cartellaDati,
      portachiavi: azzerato,
    );
    final nuovo = await ProgrammaCoach.avvia(cartellaDati: cartellaDati, portachiavi: azzerato);
    addTearDown(nuovo.chiudi);
    expect(nuovo.indirizzo, isNot(vecchio));
    expect(nuovo.nucleo.atleti.cerca(atleta.id)?.nome, 'Giulia');
    expect(nuovo.nucleo.dispositivi.attivo(atleta.id), isNull);
  });

  group('esportazioni', () {
    late Ambiente a;
    late String atletaId;

    setUp(() async {
      a = await Ambiente.avvia();
      atletaId = a.nucleo.atleti.crea('Giulia', note: 'Ginocchio destro delicato').id;
    });
    tearDown(() => a.chiudi());

    test('il JSON contiene schede, revisioni e allenamenti', () async {
      final sedutaId = nuovoUuid();
      final schedaId = a.nucleo.schede.crea(
        atletaId,
        contenuto: contenutoScheda('Forza', sedutaId: sedutaId),
      );
      a.nucleo.schede.pubblica(schedaId);
      a.nucleo.schede.pubblica(schedaId);
      final telefono = await a.abbinaTelefono(atletaId);
      await telefono.sincronizza(
        daInviare: [nuovoLog(schedaId: schedaId, revisione: 2, sedutaId: sedutaId)],
      );

      final dati = a.nucleo.esportazioni.json(atletaId);
      expect(dati['formato'], 'opencoach-atleta');
      final atleta = dati['atleta'] as Map<String, Object?>;
      expect(atleta['nome'], 'Giulia');
      expect(atleta.containsKey('note_private'), isFalse);
      final scheda = (dati['schede'] as List<Object?>).single as Map<String, Object?>;
      expect((scheda['revisioni'] as List<Object?>).map((r) => (r as Map)['revisione']), [1, 2]);
      expect(dati['allenamenti'], hasLength(1));
      expect(jsonDecode(jsonEncode(dati)), isA<Map<String, Object?>>());

      final conNote = a.nucleo.esportazioni.json(atletaId, notePrivate: true);
      expect((conNote['atleta'] as Map)['note_private'], 'Ginocchio destro delicato');
    });

    test('il CSV ha una riga per serie, pronta per Excel in italiano', () async {
      final sedutaId = nuovoUuid();
      final schedaId = a.nucleo.schede.crea(
        atletaId,
        contenuto: contenutoScheda('Forza; blocco 1', sedutaId: sedutaId),
      );
      a.nucleo.schede.pubblica(schedaId);
      final telefono = await a.abbinaTelefono(atletaId);
      final log = nuovoLog(schedaId: schedaId, revisione: 1, sedutaId: sedutaId, note: 'Ottima "giornata"')
        ..['rpe'] = 8
        ..['esercizi'] = [
          {
            'nome': 'Squat',
            'serie': [
              {'ripetizioni': 8, 'carico_kg': 82.5, 'rpe': 7.5, 'completata': true},
              {'ripetizioni': 6, 'carico_kg': 82.5, 'completata': false},
            ],
          },
          {'nome': 'Plank', 'serie': <Object?>[]},
        ];
      await telefono.sincronizza(daInviare: [log]);

      final csv = a.nucleo.esportazioni.csv(atletaId);
      expect(csv, startsWith('﻿data;scheda;revisione;seduta;esercizio;serie;'));
      final righe = csv.substring(1).trimRight().split('\r\n');
      expect(righe, hasLength(4));
      expect(
        righe[1],
        '2026-10-21 18:30;"Forza; blocco 1";1;Giorno A;Squat;1;8;82,5;;7,5;sì;;;8;'
        '"Ottima ""giornata"""',
      );
      expect(righe[2], contains(';Squat;2;6;82,5;;;no;'));
      expect(righe[3], contains(';Plank;;;;;;;'));

      final conVirgole = a.nucleo.esportazioni.csv(atletaId, separatore: ',');
      expect(conVirgole, startsWith('data,'));
      expect(conVirgole, contains(',82.5,'));
    });
  });

  test('il registro passa a un secondo file oltre la dimensione massima', () {
    final registro = RegistroFile(p.join(cartella.path, 'registro'), dimensioneMassima: 200);
    for (var i = 0; i < 10; i++) {
      registro.scrivi('riga numero $i del registro di prova');
    }
    final file = File(registro.percorso);
    final precedente = File('${registro.percorso}.1');
    expect(precedente.existsSync(), isTrue);
    expect(file.lengthSync(), lessThanOrEqualTo(200));
    expect(file.readAsStringSync(), contains('riga numero 9'));
  });
}
