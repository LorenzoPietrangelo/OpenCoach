import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

import 'supporto.dart';

/// Porta di controllo di Tor simulata, su TCP: registra i comandi e risponde
/// come Tor ai pochi che il trasporto usa.
class ControlloFinto {
  ControlloFinto._(this._server) {
    _server.listen(_accetta);
  }

  static Future<ControlloFinto> avvia() async => ControlloFinto._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
  );

  final ServerSocket _server;
  final comandi = <String>[];
  final _aperte = <Socket>[];
  var connessioni = 0;

  /// Avanzamento del bootstrap a ogni domanda; l'ultimo valore si ripete.
  var avanzamenti = <int>[100];

  /// Valore di `net/listeners/socks`.
  var socks = '127.0.0.1:1';

  /// Rifiuta il proxy SOCKS su socket Unix, come un tor che non lo permette.
  var rifiutaUnix = false;

  int get porta => _server.port;

  void _accetta(Socket socket) {
    connessioni++;
    _aperte.add(socket);
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((riga) {
          comandi.add(riga);
          socket.write(_risposta(riga));
        }, onError: (Object _) {});
  }

  String _risposta(String riga) {
    if (riga == 'GETINFO status/bootstrap-phase') {
      final avanzamento = avanzamenti.length > 1
          ? avanzamenti.removeAt(0)
          : avanzamenti.single;
      return '250-status/bootstrap-phase=NOTICE BOOTSTRAP '
          'PROGRESS=$avanzamento TAG=x SUMMARY="x"\r\n250 OK\r\n';
    }
    if (riga == 'GETINFO net/listeners/socks') {
      return '250-net/listeners/socks="$socks"\r\n250 OK\r\n';
    }
    if (rifiutaUnix && riga.startsWith('SETCONF SocksPort="unix:')) {
      return '553 Unable to set option: Failed to bind one of the listener '
          'ports.\r\n';
    }
    const noti = [
      'AUTHENTICATE',
      'SETCONF ',
      'SIGNAL NEWNYM',
      'ONION_CLIENT_AUTH_ADD ',
      'ONION_CLIENT_AUTH_REMOVE ',
    ];
    if (noti.any(riga.startsWith)) return '250 OK\r\n';
    return '510 Unrecognized command\r\n';
  }

  /// Le connessioni cadono, come se il sistema avesse chiuso Tor.
  void interrompi() {
    for (final socket in _aperte) {
      socket.destroy();
    }
    _aperte.clear();
  }

  Future<void> chiudi() async {
    interrompi();
    await _server.close();
  }
}

class AvviatoreFinto implements AvviatoreTor {
  AvviatoreFinto(this.porta, {this.socketSocks});

  final int porta;
  final String? socketSocks;
  var avvii = 0;

  @override
  Future<AccessoControllo> avvia() async {
    avvii++;
    return AccessoControllo(
      indirizzo: InternetAddress.loopbackIPv4,
      porta: porta,
      socketSocks: socketSocks,
    );
  }
}

/// Proxy SOCKS5 che annota le destinazioni e risponde con [codice].
Future<ServerSocket> socksFinto(List<String> destinazioni, int codice) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    final ricevuti = <int>[];
    var salutato = false;
    socket.listen((dati) {
      ricevuti.addAll(dati);
      if (!salutato && ricevuti.length >= 3) {
        ricevuti.removeRange(0, 3);
        socket.add([5, 0]);
        salutato = true;
      }
      if (salutato && ricevuti.length >= 5) {
        final lunghezza = ricevuti[4];
        if (ricevuti.length < 7 + lunghezza) return;
        final nome = ascii.decode(ricevuti.sublist(5, 5 + lunghezza));
        final porta = (ricevuti[5 + lunghezza] << 8) | ricevuti[6 + lunghezza];
        destinazioni.add('$nome:$porta');
        socket.add([5, codice, 0, 1, 0, 0, 0, 0, 0, 0]);
        socket.close().ignore();
      }
    }, onError: (Object _) {});
  });
  return server;
}

void main() {
  late OrologioFinto orologio;
  late ControlloFinto controllo;
  late AvviatoreFinto avviatore;
  late TrasportoTorControllato tor;

  setUp(() async {
    orologio = OrologioFinto();
    controllo = await ControlloFinto.avvia();
    avviatore = AvviatoreFinto(controllo.porta);
    tor = TrasportoTorControllato(avviatore, orologio: orologio);
  });
  tearDown(() => controllo.chiudi());

  test('si collega, aspetta il bootstrap e poi configura il proxy', () async {
    controllo.avanzamenti = [10, 60, 100];
    await tor.avvia();
    expect(controllo.comandi, [
      'AUTHENTICATE',
      'SETCONF DisableNetwork=0',
      'GETINFO status/bootstrap-phase',
      'GETINFO status/bootstrap-phase',
      'GETINFO status/bootstrap-phase',
      'SETCONF SocksPort="auto ExtendedErrors" HTTPTunnelPort=0',
      'GETINFO net/listeners/socks',
    ]);
    expect(orologio.attese, hasLength(2));

    // Già avviato: stessa connessione, solo il controllo del bootstrap.
    controllo.comandi.clear();
    await tor.avvia();
    expect(controllo.connessioni, 1);
    expect(avviatore.avvii, 1);
    expect(controllo.comandi, [
      'SETCONF DisableNetwork=0',
      'GETINFO status/bootstrap-phase',
    ]);
  });

  test('senza bootstrap entro 60 secondi: Tor non parte', () async {
    controllo.avanzamenti = [45];
    final inizio = orologio.ora;
    await expectLater(tor.avvia(), throwsA(isA<TorNonParte>()));
    expect(
      orologio.ora.difference(inizio),
      greaterThanOrEqualTo(const Duration(seconds: 60)),
    );
  });

  test('porta di controllo che non risponde: Tor non parte', () async {
    final chiusa = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final porta = chiusa.port;
    await chiusa.close();
    final senzaControllo = TrasportoTorControllato(
      AvviatoreFinto(porta),
      orologio: orologio,
      limiteBootstrap: const Duration(seconds: 1),
    );
    await expectLater(senzaControllo.avvia(), throwsA(isA<TorNonParte>()));
  });

  test(
    'chiavi in memoria, ripassate a Tor dopo una nuova connessione',
    () async {
      final primo = 'a' * 56;
      final secondo = 'b' * 56;
      final chiave = Uint8List.fromList(List.generate(32, (i) => i));
      final base64Chiave = base64.encode(chiave);

      await tor.impostaChiave(primo, chiave);
      expect(controllo.connessioni, 0, reason: 'Tor non è ancora avviato');
      await tor.avvia();
      expect(
        controllo.comandi,
        contains('ONION_CLIENT_AUTH_ADD $primo x25519:$base64Chiave'),
      );

      await tor.impostaChiave(secondo, chiave);
      await tor.rimuoviChiave(primo);
      expect(controllo.comandi.sublist(controllo.comandi.length - 2), [
        'ONION_CLIENT_AUTH_ADD $secondo x25519:$base64Chiave',
        'ONION_CLIENT_AUTH_REMOVE $primo',
      ]);

      // Il sistema chiude Tor: alla sync successiva si riapre la connessione e
      // si ripassano le chiavi rimaste.
      controllo
        ..interrompi()
        ..comandi.clear();
      await tor.avvia();
      expect(controllo.connessioni, 2);
      expect(avviatore.avvii, 2);
      expect(
        controllo.comandi.where((c) => c.startsWith('ONION_CLIENT_AUTH_ADD')),
        ['ONION_CLIENT_AUTH_ADD $secondo x25519:$base64Chiave'],
      );
    },
  );

  test('riavvia scarta la cache con NEWNYM, ferma toglie la rete', () async {
    await tor.riavvia();
    await tor.ferma();
    expect(controllo.connessioni, 0, reason: 'senza Tor avviato non fa nulla');

    await tor.avvia();
    controllo.comandi.clear();
    await tor.riavvia();
    await tor.ferma();
    expect(controllo.comandi, ['SIGNAL NEWNYM', 'SETCONF DisableNetwork=1']);
  });

  test('le connessioni passano dal proxy SOCKS che indica Tor', () async {
    final destinazioni = <String>[];
    final socks = await socksFinto(
      destinazioni,
      ErroreSocks.descrittoreNonTrovato,
    );
    addTearDown(socks.close);
    controllo.socks = '127.0.0.1:${socks.port}';
    await tor.avvia();

    final http = tor.creaHttpClient();
    addTearDown(() => http.close(force: true));
    final indirizzo = 'c' * 56;
    await expectLater(
      ClienteApi(indirizzo: indirizzo, http: http).info(),
      throwsA(
        isA<ErroreSocks>().having(
          (e) => e.codice,
          'codice',
          ErroreSocks.descrittoreNonTrovato,
        ),
      ),
    );
    expect(destinazioni, ['$indirizzo.onion:80']);
  });

  test(
    'proxy su socket Unix, oppure sul loopback se tor non lo accetta',
    () async {
      final registro = <String>[];
      final conSocket = TrasportoTorControllato(
        AvviatoreFinto(controllo.porta, socketSocks: '/dati/tor/socks'),
        orologio: orologio,
        registra: registro.add,
      );
      await conSocket.avvia();
      expect(
        controllo.comandi,
        contains(
          'SETCONF SocksPort="unix:/dati/tor/socks ExtendedErrors" '
          'HTTPTunnelPort=0',
        ),
      );

      controllo
        ..interrompi()
        ..comandi.clear()
        ..rifiutaUnix = true;
      await conSocket.avvia();
      expect(controllo.comandi.where((c) => c.startsWith('SETCONF SocksPort')), [
        'SETCONF SocksPort="unix:/dati/tor/socks ExtendedErrors" HTTPTunnelPort=0',
        'SETCONF SocksPort="auto ExtendedErrors" HTTPTunnelPort=0',
      ]);
      expect(registro.single, contains('loopback'));
      expect(conSocket.creaHttpClient, returnsNormally);
    },
  );

  test('legge anche un proxy su socket Unix', () async {
    controllo.socks = 'unix:/data/app/TorService/data/socks';
    await tor.avvia();
    // Su Windows il socket non esiste, ma il trasporto lo deve aver letto.
    expect(tor.creaHttpClient, returnsNormally);
  });
}
