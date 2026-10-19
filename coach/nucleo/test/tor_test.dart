import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:test/test.dart';

/// Porta di controllo di Tor simulata: registra i comandi e risponde con
/// [rispondi], che di base imita un Tor avviato e funzionante.
class PortaControlloFinta {
  PortaControlloFinta._(this._server) {
    _server.listen((cliente) {
      _cliente = cliente;
      cliente
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((comando) {
            comandi.add(comando);
            cliente.write(rispondi(comando));
          });
    });
  }

  static Future<PortaControlloFinta> avvia() async => PortaControlloFinta._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
  );

  final ServerSocket _server;
  Socket? _cliente;
  final comandi = <String>[];
  String indirizzoServizio = '';
  var avanzamento = 100;
  String? Function(String comando)? sostituisci;

  int get porta => _server.port;

  String rispondi(String comando) {
    final sostituta = sostituisci?.call(comando);
    if (sostituta != null) return sostituta;
    if (comando == 'GETINFO status/bootstrap-phase') {
      return '250-status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=$avanzamento '
          'TAG=done SUMMARY="Done"\r\n250 OK\r\n';
    }
    if (comando == 'GETINFO status/version/current') {
      return '250-status/version/current=recommended\r\n250 OK\r\n';
    }
    if (comando.startsWith('ADD_ONION')) {
      return '250-ServiceID=$indirizzoServizio\r\n250 OK\r\n';
    }
    return '250 OK\r\n';
  }

  void evento(String testo) => _cliente!.write('650 $testo\r\n');

  List<String> comandiCheIniziano(String prefisso) =>
      comandi.where((c) => c.startsWith(prefisso)).toList();

  Future<void> chiudi() async {
    _cliente?.destroy();
    await _server.close();
  }
}

/// Aspetta che [condizione] diventi vera, al massimo per due secondi.
Future<void> attendi(bool Function() condizione) async {
  final fine = DateTime.now().add(const Duration(seconds: 2));
  while (!condizione()) {
    if (DateTime.now().isAfter(fine)) fail('Condizione non raggiunta in tempo');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late PortaControlloFinta finta;
  late ControlloTor controllo;

  setUp(() async {
    finta = await PortaControlloFinta.avvia();
    controllo = await ControlloTor.connetti('127.0.0.1', finta.porta);
  });

  tearDown(() async {
    await controllo.chiudi();
    await finta.chiudi();
  });

  group('porta di controllo', () {
    test('legge risposte su più righe e blocchi di dati', () async {
      finta.sostituisci = (comando) => comando == 'GETINFO prova'
          ? '250+prova=\r\nriga\r\n..con punto\r\n.\r\n250 OK\r\n'
          : null;
      final risposta = await controllo.comando('GETINFO prova');
      expect(risposta.righe, ['prova=', 'riga', '.con punto', 'OK']);
    });

    test('separa gli eventi dalle risposte', () async {
      finta.sostituisci = (comando) => comando == 'SIGNAL NEWNYM'
          ? '650 NETWORK_LIVENESS UP\r\n250 OK\r\n'
          : null;
      final evento = controllo.eventi.first;
      final risposta = await controllo.comando('SIGNAL NEWNYM');
      expect(risposta.codice, 250);
      expect((await evento).parole, ['NETWORK_LIVENESS', 'UP']);
    });

    test('un errore di Tor diventa ErroreTor', () async {
      finta.sostituisci = (_) => '552 Unrecognized key\r\n';
      await expectLater(
        controllo.comando('GETINFO inesistente'),
        throwsA(isA<ErroreTor>().having((e) => e.risposta.codice, 'codice', 552)),
      );
    });

    test('il cookie viaggia in esadecimale', () async {
      await controllo.autenticaConCookie([0, 15, 255]);
      expect(finta.comandi.single, 'AUTHENTICATE 000fff');
    });
  });

  group('servizio onion', () {
    late Identita identita;
    late List<String> chiavi;
    late int attese;
    late ServizioOnion servizio;
    late List<StatoTor> stati;

    setUp(() async {
      identita = await Identita.genera();
      finta.indirizzoServizio = identita.indirizzo;
      chiavi = ['aaaa', 'bbbb'];
      attese = 0;
      stati = [];
      servizio = ServizioOnion(
        controllo: controllo,
        identita: identita,
        portaLocale: 4321,
        chiaviAutorizzate: () => chiavi,
        attendiRichiesteInCorso: (_) async => attese++,
        raggruppamento: const Duration(milliseconds: 30),
        attesaDopoErrore: const Duration(milliseconds: 50),
      );
      servizio.cambiamenti.listen(stati.add);
    });

    tearDown(() => servizio.chiudi());

    test('pubblica con la client authorization e diventa raggiungibile', () async {
      await servizio.avvia();
      expect(finta.comandi.first, startsWith('SETEVENTS HS_DESC'));
      expect(
        finta.comandiCheIniziano('ADD_ONION').single,
        'ADD_ONION ${identita.chiaveTor} Flags=V3Auth Port=80,127.0.0.1:4321 '
        'ClientAuthV3=AAAA ClientAuthV3=BBBB',
      );
      expect(servizio.stato.fase, FaseTor.pubblicazione);

      finta.evento('HS_DESC UPLOADED ${identita.indirizzo} UNKNOWN \$ABCD~relay');
      await attendi(() => servizio.stato.fase == FaseTor.raggiungibile);
    });

    test('raggruppa i cambiamenti vicini in una sola ricreazione', () async {
      await servizio.avvia();
      chiavi = ['aaaa', 'cccc'];
      servizio
        ..chiaviCambiate()
        ..chiaviCambiate()
        ..chiaviCambiate();
      await attendi(() => finta.comandiCheIniziano('ADD_ONION').length == 2);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(finta.comandiCheIniziano('DEL_ONION'), ['DEL_ONION ${identita.indirizzo}']);
      expect(finta.comandiCheIniziano('ADD_ONION'), hasLength(2));
      expect(finta.comandiCheIniziano('ADD_ONION').last, contains('ClientAuthV3=CCCC'));
      expect(attese, 1, reason: 'prima aspetta le richieste in corso');
    });

    test('non ricrea il servizio se le chiavi non cambiano', () async {
      await servizio.avvia();
      chiavi = ['bbbb', 'aaaa'];
      servizio.chiaviCambiate();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(finta.comandiCheIniziano('DEL_ONION'), isEmpty);
    });

    test('senza chiavi il servizio non è pubblicato', () async {
      chiavi = [];
      await servizio.avvia();
      expect(finta.comandiCheIniziano('ADD_ONION'), isEmpty);
      expect(servizio.stato.fase, FaseTor.nessunaChiave);

      chiavi = ['dddd'];
      servizio.chiaviCambiate();
      await attendi(() => finta.comandiCheIniziano('ADD_ONION').length == 1);
      chiavi = [];
      servizio.chiaviCambiate();
      await attendi(() => finta.comandiCheIniziano('DEL_ONION').length == 1);
      await attendi(() => servizio.stato.fase == FaseTor.nessunaChiave);
    });

    test('segue avvio, rete assente e versione obsoleta', () async {
      finta.avanzamento = 45;
      await servizio.avvia();
      expect(servizio.stato.fase, FaseTor.avvio);
      expect(servizio.stato.avanzamento, 45);

      finta.evento('STATUS_CLIENT NOTICE BOOTSTRAP PROGRESS=100 TAG=done SUMMARY="Done"');
      await attendi(() => servizio.stato.fase == FaseTor.pubblicazione);

      finta.evento('NETWORK_LIVENESS DOWN');
      await attendi(() => servizio.stato.fase == FaseTor.nonRaggiungibile);
      expect(servizio.stato.motivo, 'Nessuna connessione a Internet');

      finta.evento(
        'STATUS_GENERAL WARN DANGEROUS_VERSION CURRENT=0.4.8.1 REASON=OBSOLETE '
        'RECOMMENDED="0.4.9.3"',
      );
      await attendi(() => servizio.stato.versioneObsoleta);
      finta.evento('NETWORK_LIVENESS UP');
      await attendi(() => servizio.stato.fase == FaseTor.pubblicazione);
      expect(stati.map((s) => s.fase), contains(FaseTor.nonRaggiungibile));
    });

    test('se Tor rifiuta il servizio riprova da solo', () async {
      var tentativi = 0;
      finta.sostituisci = (comando) {
        if (!comando.startsWith('ADD_ONION')) return null;
        tentativi++;
        return tentativi == 1 ? '512 Bad arguments\r\n' : null;
      };
      await servizio.avvia();
      expect(servizio.stato.fase, FaseTor.nonRaggiungibile);
      await attendi(() => tentativi == 2);
      await attendi(() => servizio.stato.fase == FaseTor.pubblicazione);
    });
  });
}
