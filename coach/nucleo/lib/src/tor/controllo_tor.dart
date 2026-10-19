import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// Risposta della porta di controllo di Tor (control-spec, §2.3).
class RispostaTor {
  const RispostaTor(this.codice, this.righe);

  final int codice;

  /// Testo delle righe senza codice e separatore, righe di dati comprese.
  final List<String> righe;

  bool get riuscita => codice >= 200 && codice < 300;

  /// Coppie `chiave=valore` delle righe.
  Map<String, String> get valori => {
    for (final riga in righe)
      if (riga.indexOf('=') case final i when i > 0)
        riga.substring(0, i): riga.substring(i + 1),
  };
}

/// Evento asincrono (codice 650), per esempio `HS_DESC UPLOADED ...`.
class EventoTor {
  const EventoTor(this.righe);

  final List<String> righe;

  /// Parole della prima riga; la prima è il tipo di evento.
  List<String> get parole => righe.first.split(' ');
}

class ErroreTor implements Exception {
  const ErroreTor(this.comando, this.risposta);

  final String comando;
  final RispostaTor risposta;

  @override
  String toString() =>
      'ErroreTor($comando: ${risposta.codice} ${risposta.righe.join(' ')})';
}

/// Connessione alla porta di controllo di Tor.
class ControlloTor {
  ControlloTor._(this._socket) {
    _socket
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_riga, onError: (Object _) => _chiudi(), onDone: _chiudi);
  }

  static Future<ControlloTor> connetti(String host, int porta) async =>
      ControlloTor._(
        await Socket.connect(host, porta, timeout: const Duration(seconds: 10)),
      );

  final Socket _socket;
  final _inAttesa = Queue<Completer<RispostaTor>>();
  final _eventi = StreamController<EventoTor>.broadcast();
  final _chiusura = Completer<void>();
  var _righe = <String>[];
  var _dati = false;

  Stream<EventoTor> get eventi => _eventi.stream;

  /// Si completa quando Tor chiude la connessione.
  Future<void> get chiuso => _chiusura.future;

  void _riga(String riga) {
    if (_dati) {
      // Una riga "." chiude i dati; le righe che iniziano con "." hanno un
      // punto in più davanti.
      if (riga == '.') {
        _dati = false;
      } else {
        _righe.add(riga.startsWith('.') ? riga.substring(1) : riga);
      }
      return;
    }
    final codice = riga.length >= 4 ? int.tryParse(riga.substring(0, 3)) : null;
    if (codice == null) return;
    final separatore = riga[3];
    _righe.add(riga.substring(4));
    if (separatore == '+') _dati = true;
    if (separatore != ' ') return;

    final righe = _righe;
    _righe = [];
    if (codice == 650) {
      _eventi.add(EventoTor(righe));
    } else if (_inAttesa.isNotEmpty) {
      _inAttesa.removeFirst().complete(RispostaTor(codice, righe));
    }
  }

  void _chiudi() {
    if (_chiusura.isCompleted) return;
    _chiusura.complete();
    while (_inAttesa.isNotEmpty) {
      _inAttesa.removeFirst().completeError(
        StateError('Porta di controllo di Tor chiusa'),
      );
    }
    _eventi.close();
  }

  /// Invia [comando] e restituisce la risposta, anche se è un errore.
  Future<RispostaTor> invia(String comando) {
    if (_chiusura.isCompleted) {
      return Future.error(StateError('Porta di controllo di Tor chiusa'));
    }
    final attesa = Completer<RispostaTor>();
    _inAttesa.add(attesa);
    _socket.write('$comando\r\n');
    return attesa.future;
  }

  /// Come [invia], ma lancia [ErroreTor] se Tor risponde con un errore.
  Future<RispostaTor> comando(String comando) async {
    final risposta = await invia(comando);
    if (!risposta.riuscita) throw ErroreTor(comando.split(' ').first, risposta);
    return risposta;
  }

  Future<void> autenticaConCookie(List<int> cookie) => comando(
    'AUTHENTICATE ${cookie.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
  );

  /// Tor termina quando questa connessione si chiude, così non sopravvive
  /// al programma.
  Future<void> prendiPossesso() async {
    await comando('TAKEOWNERSHIP');
    await comando('RESETCONF __OwningControllerProcess');
  }

  Future<void> iscrivi(List<String> eventi) =>
      comando('SETEVENTS ${eventi.join(' ')}');

  Future<String> leggiInfo(String chiave) async {
    final valore = (await comando('GETINFO $chiave')).valori[chiave];
    if (valore == null) {
      throw ErroreTor('GETINFO', RispostaTor(551, ['$chiave mancante']));
    }
    return valore;
  }

  /// Crea un onion service legato a questa connessione (`ADD_ONION`) e ne
  /// restituisce l'indirizzo. Con [chiaviClient] non vuota vale la client
  /// authorization v3: solo quelle chiavi possono raggiungerlo.
  Future<String> aggiungiOnion({
    required String chiave,
    required int portaVirtuale,
    required String destinazione,
    required List<String> chiaviClient,
  }) async {
    final risposta = await comando(
      [
        'ADD_ONION',
        chiave,
        if (chiaviClient.isNotEmpty) 'Flags=V3Auth',
        'Port=$portaVirtuale,$destinazione',
        for (final k in chiaviClient) 'ClientAuthV3=${k.toUpperCase()}',
      ].join(' '),
    );
    final indirizzo = risposta.valori['ServiceID'];
    if (indirizzo == null) throw ErroreTor('ADD_ONION', risposta);
    return indirizzo.toLowerCase();
  }

  Future<void> rimuoviOnion(String indirizzo) =>
      comando('DEL_ONION $indirizzo');

  /// Lato client: chiave privata X25519 con cui raggiungere [indirizzo]
  /// (`ONION_CLIENT_AUTH_ADD`).
  Future<void> aggiungiAutorizzazioneClient(
    String indirizzo,
    List<int> chiavePrivata,
  ) => comando(
    'ONION_CLIENT_AUTH_ADD $indirizzo x25519:${base64.encode(chiavePrivata)}',
  );

  Future<void> rimuoviAutorizzazioneClient(String indirizzo) =>
      comando('ONION_CLIENT_AUTH_REMOVE $indirizzo');

  Future<void> chiudi() async {
    _socket.destroy();
    _chiudi();
  }
}
