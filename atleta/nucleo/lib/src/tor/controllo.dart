import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// Risposta a un comando della porta di controllo di Tor (control-spec).
class RispostaControllo {
  const RispostaControllo(this.codice, this.righe);

  /// Codice dell'ultima riga: 250 se il comando è riuscito.
  final int codice;

  /// Testo di ogni riga, senza codice; i blocchi di dati sono uniti con
  /// `\n`.
  final List<String> righe;
}

/// Tor ha rifiutato un comando sulla porta di controllo.
class ErroreControlloTor implements Exception {
  const ErroreControlloTor(this.codice, this.messaggio);

  final int codice;
  final String messaggio;

  @override
  String toString() => 'ErroreControlloTor($codice $messaggio)';
}

/// Connessione alla porta di controllo di Tor, su socket Unix o TCP: i
/// comandi partono uno per volta e ciascuno riceve la propria risposta.
class ConnessioneControllo {
  ConnessioneControllo._(this._socket) {
    _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_riga, onError: (Object _) => _chiudi(), onDone: _chiudi);
    // Anche un errore di scrittura chiude la connessione.
    unawaited(
      _socket.done.then((_) => _chiudi(), onError: (Object _) => _chiudi()),
    );
  }

  static Future<ConnessioneControllo> apri(
    InternetAddress indirizzo, {
    int porta = 0,
    Duration timeout = const Duration(seconds: 10),
  }) async => ConnessioneControllo._(
    await Socket.connect(indirizzo, porta, timeout: timeout),
  );

  final Socket _socket;
  final _inAttesa = Queue<Completer<RispostaControllo>>();
  final _righe = <String>[];
  var _codice = 0;
  StringBuffer? _dati;
  var _chiusa = false;
  Future<void> _coda = Future<void>.value();

  bool get chiusa => _chiusa;

  /// Invia [comando] e ne restituisce la risposta. Lancia
  /// [ErroreControlloTor] se Tor lo rifiuta e [SocketException] se la
  /// connessione cade.
  Future<RispostaControllo> invia(String comando) {
    final risposta = _coda.then((_) {
      if (_chiusa) {
        throw const SocketException('Porta di controllo di Tor chiusa');
      }
      final attesa = Completer<RispostaControllo>();
      _inAttesa.add(attesa);
      _socket.write('$comando\r\n');
      return attesa.future;
    });
    _coda = risposta.then<void>((_) {}, onError: (Object _) {});
    return risposta.then((r) {
      if (r.codice >= 400) {
        throw ErroreControlloTor(r.codice, r.righe.join(' '));
      }
      return r;
    });
  }

  /// `GETINFO`: i valori delle [chiavi].
  Future<Map<String, String>> getInfo(Iterable<String> chiavi) async {
    final risposta = await invia('GETINFO ${chiavi.join(' ')}');
    return {
      for (final riga in risposta.righe)
        if (riga.indexOf('=') case final uguale when uguale > 0)
          riga.substring(0, uguale): riga.substring(uguale + 1),
    };
  }

  Future<void> chiudi() async {
    _socket.destroy();
    _chiudi();
  }

  void _riga(String riga) {
    final dati = _dati;
    if (dati != null) {
      // Blocco di dati: finisce con una riga di solo punto.
      if (riga == '.') {
        _righe.add(dati.toString());
        _dati = null;
      } else {
        if (dati.isNotEmpty) dati.write('\n');
        dati.write(riga.startsWith('..') ? riga.substring(1) : riga);
      }
      return;
    }
    if (riga.length < 4) return;
    final codice = int.tryParse(riga.substring(0, 3));
    if (codice == null) return;
    final separatore = riga[3];
    final testo = riga.substring(4);
    // Gli eventi asincroni (6xx) non rispondono ad alcun comando.
    if (codice >= 600) return;
    _codice = codice;
    switch (separatore) {
      case '+':
        _dati = StringBuffer(testo);
      case '-':
        _righe.add(testo);
      default:
        _righe.add(testo);
        final risposta = RispostaControllo(_codice, List.of(_righe));
        _righe.clear();
        if (_inAttesa.isNotEmpty) _inAttesa.removeFirst().complete(risposta);
    }
  }

  void _chiudi() {
    if (_chiusa) return;
    _chiusa = true;
    while (_inAttesa.isNotEmpty) {
      _inAttesa.removeFirst().completeError(
        const SocketException('Porta di controllo di Tor chiusa'),
      );
    }
  }
}

/// Valore tra virgolette per `SETCONF`, come vuole la control-spec.
String traVirgolette(String valore) =>
    '"${valore.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

/// I valori di un elenco come `net/listeners/socks`: stringhe tra
/// virgolette separate da spazi.
List<String> valoriTraVirgolette(String elenco) => [
  for (final m in RegExp(r'"((?:[^"\\]|\\.)*)"').allMatches(elenco))
    m[1]!.replaceAllMapped(RegExp(r'\\(.)'), (e) => e[1]!),
];
