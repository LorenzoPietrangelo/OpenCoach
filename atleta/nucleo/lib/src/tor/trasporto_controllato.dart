import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:protocollo/protocollo.dart';

import '../orologio.dart';
import '../trasporto.dart';
import 'controllo.dart';

/// Avvia Tor su una piattaforma e dice dove trovare la sua porta di
/// controllo: su Android il servizio di tor-android, su un PC un processo.
abstract interface class AvviatoreTor {
  /// Avvia Tor, se non è già in esecuzione. La porta di controllo può non
  /// essere ancora pronta: il trasporto ritenta finché non risponde.
  Future<AccessoControllo> avvia();
}

/// Come raggiungere la porta di controllo di Tor.
class AccessoControllo {
  const AccessoControllo({
    required this.indirizzo,
    this.porta = 0,
    this.cookie,
    this.socketSocks,
  });

  /// Socket Unix (`InternetAddressType.unix`) o indirizzo di loopback.
  final InternetAddress indirizzo;
  final int porta;

  /// Cookie di autenticazione, se Tor ne chiede uno.
  final List<int>? cookie;

  /// Percorso del socket Unix su cui far ascoltare il proxy SOCKS, in una
  /// cartella accessibile solo all'app; null per una porta TCP su loopback.
  final String? socketSocks;
}

/// [TrasportoTor] che comanda Tor dalla sua porta di controllo.
///
/// - Il proxy SOCKS ha gli errori estesi (§6.1) e, dove si può, ascolta su un
///   socket Unix: così Tor lo usa solo l'app (§10.1). La porta HTTP di
///   tunnel resta chiusa.
/// - Le chiavi di client authorization passano con `ONION_CLIENT_AUTH_ADD`
///   senza `Permanent`: restano in memoria, mai nei file di Tor. Tor però le
///   scarta tutte a ogni `SETCONF`, perché ricarica la client authorization
///   da `ClientOnionAuthDir`, e con `SIGNAL NEWNYM`: per questo [avvia] le
///   ripassa dopo i suoi `SETCONF`, e il trasporto non manda mai NEWNYM.
/// - [ferma] toglie la rete a Tor (`DisableNetwork`) invece di chiuderlo:
///   l'API di tor sconsiglia di riavviarlo nello stesso processo. Anche questo
///   `SETCONF` scarta le chiavi, che tornano al prossimo [avvia].
class TrasportoTorControllato implements TrasportoTor {
  TrasportoTorControllato(
    this._avviatore, {
    this.limiteBootstrap = const Duration(seconds: 60),
    this.intervallo = const Duration(milliseconds: 500),
    Orologio orologio = const OrologioDiSistema(),
    void Function(String)? registra,
  }) : _orologio = orologio,
       _registra = registra ?? ((_) {});

  final AvviatoreTor _avviatore;

  /// Tempo per collegarsi e completare il bootstrap (§7.5).
  final Duration limiteBootstrap;

  /// Pausa tra due controlli dello stato di Tor.
  final Duration intervallo;
  final Orologio _orologio;
  final void Function(String) _registra;

  final _chiavi = <String, Uint8List>{};
  ConnessioneControllo? _controllo;
  AccessoControllo? _accesso;

  /// Connessione su cui il proxy è già configurato.
  ConnessioneControllo? _configurato;
  Object? _proxy;
  var _portaProxy = 0;
  Future<void>? _avvio;

  /// Chi aspetta l'avvio in corso e ne vuole l'avanzamento.
  final _osservatori = <void Function(int)>{};

  @override
  Future<void> avvia({void Function(int percento)? avanzamento}) async {
    if (avanzamento != null) _osservatori.add(avanzamento);
    try {
      await (_avvio ??= _avvia().whenComplete(() => _avvio = null));
      avanzamento?.call(100);
    } finally {
      if (avanzamento != null) _osservatori.remove(avanzamento);
    }
  }

  Future<void> _avvia() async {
    final scadenza = _orologio.adesso().add(limiteBootstrap);
    try {
      var controllo = await _collega(scadenza);
      try {
        await controllo.invia('SETCONF DisableNetwork=0');
      } on SocketException {
        // La connessione era caduta, per esempio perché il sistema ha chiuso
        // il servizio di Tor: se ne apre un'altra.
        await controllo.chiudi();
        controllo = await _collega(scadenza);
        await controllo.invia('SETCONF DisableNetwork=0');
      }
      await _attendiBootstrap(controllo, scadenza);
      if (!identical(_configurato, controllo)) {
        await _configuraProxy(controllo);
        _configurato = controllo;
      }
      for (final indirizzo in List.of(_chiavi.keys)) {
        await _aggiungiChiave(controllo, indirizzo);
      }
    } on TorNonParte {
      rethrow;
    } on Object catch (e) {
      _registra('Tor non disponibile: $e');
      throw const TorNonParte();
    }
  }

  @override
  Future<void> ferma() async {
    final controllo = _attivo;
    if (controllo == null) return;
    try {
      await controllo.invia('SETCONF DisableNetwork=1');
    } on Object catch (e) {
      _registra('Tor non si è fermato: $e');
    }
  }

  // Le chiavi restano comunque nella mappa: se Tor non le riceve ora, le
  // riceve al prossimo avvio.

  @override
  Future<void> impostaChiave(String indirizzo, Uint8List chiavePrivata) async {
    _chiavi[indirizzo] = Uint8List.fromList(chiavePrivata);
    final controllo = _attivo;
    if (controllo == null) return;
    try {
      await _aggiungiChiave(controllo, indirizzo);
    } on Object catch (e) {
      _registra('Chiave non passata a Tor: $e');
    }
  }

  @override
  Future<void> rimuoviChiave(String indirizzo) async {
    _chiavi.remove(indirizzo);
    try {
      await _attivo?.invia('ONION_CLIENT_AUTH_REMOVE $indirizzo');
    } on Object catch (e) {
      _registra('Chiave non tolta da Tor: $e');
    }
  }

  @override
  HttpClient creaHttpClient() {
    final proxy = _proxy;
    if (proxy == null) throw StateError('Tor non è avviato');
    return clienteHttpTramiteTor(socksHost: proxy, socksPorta: _portaProxy);
  }

  ConnessioneControllo? get _attivo {
    final controllo = _controllo;
    return controllo == null || controllo.chiusa ? null : controllo;
  }

  /// La connessione alla porta di controllo, aperta e autenticata se serve.
  Future<ConnessioneControllo> _collega(DateTime scadenza) async {
    final esistente = _attivo;
    if (esistente != null) return esistente;
    final accesso = await _avviatore.avvia();
    final controllo = await _apri(accesso, scadenza);
    try {
      final cookie = accesso.cookie;
      await controllo.invia(
        cookie == null
            ? 'AUTHENTICATE'
            : 'AUTHENTICATE ${_esadecimale(cookie)}',
      );
      _controllo = controllo;
      _accesso = accesso;
      return controllo;
    } on Object {
      await controllo.chiudi();
      rethrow;
    }
  }

  /// Proxy SOCKS con gli errori estesi, su un socket Unix se l'avviatore ne
  /// indica uno, e niente porta HTTP di tunnel. Si configura dopo il
  /// bootstrap: tor-android legge le porte appena si collega e si aspetta un
  /// numero di porta. Se tor rifiuta il socket Unix, il proxy va su una porta
  /// di loopback.
  Future<void> _configuraProxy(ConnessioneControllo controllo) async {
    Future<void> imposta(String porta) => controllo.invia(
      'SETCONF SocksPort=${traVirgolette('$porta ExtendedErrors')} '
      'HTTPTunnelPort=0',
    );
    final socks = _accesso?.socketSocks;
    if (socks == null) {
      await imposta('auto');
    } else {
      try {
        await imposta('unix:$socks');
      } on ErroreControlloTor catch (e) {
        _registra('Proxy SOCKS su socket Unix rifiutato, uso il loopback: $e');
        await imposta('auto');
      }
    }
    final ascolto = await controllo.getInfo(['net/listeners/socks']);
    _impostaProxy(ascolto['net/listeners/socks'] ?? '');
  }

  /// Ritenta finché la porta di controllo non risponde: Tor può impiegare
  /// qualche secondo a crearla.
  Future<ConnessioneControllo> _apri(
    AccessoControllo accesso,
    DateTime scadenza,
  ) async {
    while (true) {
      try {
        return await ConnessioneControllo.apri(
          accesso.indirizzo,
          porta: accesso.porta,
        );
      } on SocketException {
        if (!_orologio.adesso().isBefore(scadenza)) throw const TorNonParte();
        await _orologio.attendi(intervallo);
      }
    }
  }

  Future<void> _attendiBootstrap(
    ConnessioneControllo controllo,
    DateTime scadenza,
  ) async {
    var ultimo = -1;
    while (true) {
      final fase = await controllo.getInfo(['status/bootstrap-phase']);
      final percento = int.tryParse(
        RegExp(r'\bPROGRESS=(\d+)\b')
                .firstMatch(fase['status/bootstrap-phase'] ?? '')
                ?.group(1) ??
            '',
      );
      if (percento == 100) return;
      if (percento != null && percento != ultimo) {
        ultimo = percento;
        for (final osservatore in List.of(_osservatori)) {
          osservatore(percento);
        }
      }
      if (!_orologio.adesso().isBefore(scadenza)) throw const TorNonParte();
      await _orologio.attendi(intervallo);
    }
  }

  Future<void> _aggiungiChiave(
    ConnessioneControllo controllo,
    String indirizzo,
  ) async {
    final chiave = _chiavi[indirizzo];
    if (chiave == null) return;
    await controllo.invia(
      'ONION_CLIENT_AUTH_ADD $indirizzo x25519:${base64.encode(chiave)}',
    );
  }

  void _impostaProxy(String elenco) {
    final valori = valoriTraVirgolette(elenco);
    if (valori.isEmpty) {
      throw const FormatException('Tor non ha un proxy SOCKS');
    }
    final valore = valori.first;
    if (valore.startsWith('unix:')) {
      _proxy = InternetAddress(
        valore.substring(5),
        type: InternetAddressType.unix,
      );
      _portaProxy = 0;
      return;
    }
    final duePunti = valore.lastIndexOf(':');
    final porta = int.tryParse(valore.substring(duePunti + 1));
    if (duePunti <= 0 || porta == null) {
      throw FormatException('Proxy SOCKS non valido', valore);
    }
    _proxy = valore.substring(0, duePunti).replaceAll(RegExp(r'[\[\]]'), '');
    _portaProxy = porta;
  }

  static String _esadecimale(List<int> byte) =>
      byte.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
