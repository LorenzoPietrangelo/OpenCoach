import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Errore restituito dal proxy SOCKS5 di Tor. I codici da `0xF0` a `0xF7`
/// sono gli errori estesi degli onion service (proposta 304), che l'app usa
/// per distinguere i guasti (§7.5).
class ErroreSocks implements Exception {
  const ErroreSocks(this.codice);

  final int codice;

  static const descrittoreNonTrovato = 0xF0;
  static const descrittoreNonValido = 0xF1;
  static const introduzioneFallita = 0xF2;
  static const rendezvousFallito = 0xF3;
  static const autorizzazioneMancante = 0xF4;
  static const autorizzazioneErrata = 0xF5;
  static const indirizzoNonValido = 0xF6;
  static const introduzioneScaduta = 0xF7;

  /// Il servizio non risponde: di solito il PC del coach è spento o il
  /// programma è chiuso.
  bool get servizioIrraggiungibile => const {
    descrittoreNonTrovato,
    introduzioneFallita,
    rendezvousFallito,
    introduzioneScaduta,
    0x04, // host irraggiungibile
    0x06, // TTL scaduto
  }.contains(codice);

  /// La chiave di client authorization manca o il servizio non la accetta.
  bool get autorizzazioneRifiutata =>
      codice == autorizzazioneMancante || codice == autorizzazioneErrata;

  @override
  String toString() =>
      'ErroreSocks(0x${codice.toRadixString(16).padLeft(2, '0')})';
}

/// Il proxy ha risposto in modo non conforme a SOCKS5 o ha chiuso la
/// connessione durante la negoziazione.
class ErroreProtocolloSocks implements Exception {
  const ErroreProtocolloSocks(this.messaggio);

  final String messaggio;

  @override
  String toString() => 'ErroreProtocolloSocks: $messaggio';
}

/// Apre una connessione TCP verso [host]:[porta] attraverso il proxy SOCKS5
/// [proxyHost]:[proxyPorta]. Il nome viene risolto dal proxy, come serve per
/// gli indirizzi `.onion`.
///
/// [proxyHost] è un nome o un [InternetAddress]; con un socket Unix
/// (`InternetAddressType.unix`) [proxyPorta] non conta. Così il proxy di Tor
/// può essere un socket accessibile solo all'app.
///
/// La socket restituita si può usare con `HttpClient.connectionFactory`.
Future<Socket> connettiTramiteSocks5({
  required String host,
  required int porta,
  required Object proxyHost,
  required int proxyPorta,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final nome = ascii.encode(host);
  if (nome.isEmpty || nome.length > 255) {
    throw ArgumentError.value(host, 'host', 'nome non valido');
  }
  final socket = await Socket.connect(proxyHost, proxyPorta, timeout: timeout);
  final lettore = _LettoreSocket(socket);
  try {
    return await () async {
      socket.add([5, 1, 0]);
      final saluto = await lettore.leggi(2);
      if (saluto[0] != 5 || saluto[1] != 0) {
        throw const ErroreProtocolloSocks('metodo di autenticazione rifiutato');
      }
      socket.add([
        5, 1, 0, 3, nome.length, ...nome, (porta >> 8) & 0xff, porta & 0xff, //
      ]);
      final testa = await lettore.leggi(4);
      if (testa[0] != 5) {
        throw const ErroreProtocolloSocks('versione della risposta non valida');
      }
      if (testa[1] != 0) throw ErroreSocks(testa[1]);
      final lunghezzaIndirizzo = switch (testa[3]) {
        1 => 4,
        4 => 16,
        3 => (await lettore.leggi(1))[0],
        _ => throw const ErroreProtocolloSocks('tipo di indirizzo non valido'),
      };
      await lettore.leggi(lunghezzaIndirizzo + 2);
      return lettore.consegna();
    }().timeout(timeout);
  } catch (_) {
    socket.destroy();
    rethrow;
  }
}

/// Legge byte esatti dalla socket durante la negoziazione, poi passa il resto
/// del flusso a una [_SocketSocks].
class _LettoreSocket {
  _LettoreSocket(this._socket) {
    _iscrizione = _socket.listen(
      _dati,
      onError: _errore,
      onDone: _fine,
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _iscrizione;
  final _buffer = <int>[];
  Completer<void>? _attesa;
  Object? _erroreLettura;
  var _chiuso = false;
  StreamController<Uint8List>? _uscita;

  void _dati(Uint8List dati) {
    final uscita = _uscita;
    if (uscita != null) {
      uscita.add(dati);
    } else {
      _buffer.addAll(dati);
      _sveglia();
    }
  }

  void _errore(Object errore, StackTrace traccia) {
    final uscita = _uscita;
    if (uscita != null) {
      uscita.addError(errore, traccia);
    } else {
      _erroreLettura = errore;
      _sveglia();
    }
  }

  void _fine() {
    final uscita = _uscita;
    if (uscita != null) {
      uscita.close();
    } else {
      _chiuso = true;
      _sveglia();
    }
  }

  void _sveglia() {
    final attesa = _attesa;
    _attesa = null;
    attesa?.complete();
  }

  Future<Uint8List> leggi(int quanti) async {
    while (_buffer.length < quanti) {
      final errore = _erroreLettura;
      if (errore != null) throw errore;
      if (_chiuso) {
        throw const ErroreProtocolloSocks('connessione chiusa dal proxy');
      }
      final attesa = _attesa = Completer<void>();
      await attesa.future;
    }
    final letti = Uint8List.fromList(_buffer.sublist(0, quanti));
    _buffer.removeRange(0, quanti);
    return letti;
  }

  Socket consegna() {
    final uscita = StreamController<Uint8List>(
      onPause: _iscrizione.pause,
      onResume: _iscrizione.resume,
      onCancel: _iscrizione.cancel,
    );
    _uscita = uscita;
    if (_buffer.isNotEmpty) {
      uscita.add(Uint8List.fromList(_buffer));
      _buffer.clear();
    }
    if (_chiuso) uscita.close();
    return _SocketSocks(_socket, uscita.stream);
  }
}

/// Socket già collegata attraverso il proxy: scrive sulla socket originale e
/// legge dal flusso che segue la negoziazione SOCKS.
class _SocketSocks extends StreamView<Uint8List> implements Socket {
  _SocketSocks(this._socket, super.flusso);

  final Socket _socket;

  @override
  Encoding get encoding => _socket.encoding;

  @override
  set encoding(Encoding valore) => _socket.encoding = valore;

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _socket.addStream(stream);

  @override
  Future<void> close() => _socket.close();

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> flush() => _socket.flush();

  @override
  void write(Object? object) => _socket.write(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _socket.writeln(object);

  @override
  InternetAddress get address => _socket.address;

  @override
  int get port => _socket.port;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;

  @override
  int get remotePort => _socket.remotePort;

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);

  @override
  void destroy() => _socket.destroy();
}
