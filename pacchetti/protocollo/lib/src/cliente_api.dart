import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'limiti.dart';
import 'messaggi.dart';
import 'socks5.dart';

/// Risposta d'errore dell'API del coach (§6.4).
class ErroreApi implements Exception {
  const ErroreApi(this.stato, this.codice, {this.messaggio = '', this.riprovaTra});

  final int stato;
  final String codice;
  final String messaggio;

  /// Attesa indicata da `Retry-After`, per 429 e 503.
  final Duration? riprovaTra;

  @override
  String toString() => 'ErroreApi($stato $codice${messaggio.isEmpty ? '' : ': $messaggio'})';
}

/// [HttpClient] che raggiunge gli indirizzi `.onion` attraverso il proxy
/// SOCKS5 di Tor in [socksHost]:[socksPorta]; [socksHost] può essere anche un
/// socket Unix (vedi [connettiTramiteSocks5]).
///
/// Se Tor non completa la connessione entro [timeoutConnessione] la richiesta
/// fallisce con una [SocketException], come una connessione diretta.
HttpClient clienteHttpTramiteTor({
  required Object socksHost,
  required int socksPorta,
  Duration timeoutConnessione = const Duration(seconds: 90),
}) {
  return HttpClient()
    // HttpClient accetta un TimeoutException dalla connectionFactory solo con
    // connectionTimeout impostato: allora lo trasforma in SocketException.
    ..connectionTimeout = timeoutConnessione
    ..connectionFactory = (uri, proxyHost, proxyPort) async {
      return ConnectionTask.fromSocket(
        connettiTramiteSocks5(
          host: uri.host,
          porta: uri.port,
          proxyHost: socksHost,
          proxyPorta: socksPorta,
          timeout: timeoutConnessione,
        ),
        () {},
      );
    };
}

/// Chiamate all'API del coach (§6.3).
///
/// Il trasporto lo decide [http]: nell'app passa da Tor
/// ([clienteHttpTramiteTor]), nei test può collegarsi direttamente al server
/// locale.
class ClienteApi {
  ClienteApi({
    required this.indirizzo,
    required HttpClient http,
    this.token,
    this.timeoutRisposta = const Duration(seconds: 60),
  }) : _http = http;

  /// Indirizzo onion del coach, senza ".onion".
  final String indirizzo;
  final HttpClient _http;
  final Duration timeoutRisposta;

  /// Token del dispositivo, necessario dopo l'abbinamento.
  String? token;

  Future<RispostaInfo> info() async =>
      RispostaInfo.fromJson(await _chiama('GET', '/v1/info'));

  Future<RispostaAbbinamento> abbina(RichiestaAbbinamento richiesta) async =>
      RispostaAbbinamento.fromJson(
        await _chiama('POST', '/v1/abbinamento', corpo: richiesta.toJson()),
      );

  Future<void> confermaAbbinamento() =>
      _chiama('POST', '/v1/abbinamento/conferma', autenticata: true);

  Future<RispostaSync> sincronizza(RichiestaSync richiesta) async =>
      RispostaSync.fromJson(
        await _chiama(
          'POST',
          '/v1/sync',
          corpo: richiesta.toJson(),
          autenticata: true,
        ),
      );

  Future<void> scollega() =>
      _chiama('DELETE', '/v1/dispositivo', autenticata: true);

  /// `PUT /v1/foto/<id>`: una foto di un questionario, in JPEG (§8.6).
  /// Idempotente: ricaricare la stessa foto non cambia nulla.
  Future<void> caricaFoto(String id, Uint8List jpeg) => _chiama(
    'PUT',
    '/v1/foto/$id',
    binario: (ContentType('image', 'jpeg'), jpeg),
    autenticata: true,
  );

  /// `PUT /v1/video/<id>/<parte>`: una parte di un video della chat, a
  /// partire da 0 (§8.7). Idempotente.
  Future<void> caricaParteVideo(String id, int parte, Uint8List dati) => _chiama(
    'PUT',
    '/v1/video/$id/$parte',
    binario: (ContentType('application', 'octet-stream'), dati),
    autenticata: true,
  );

  Future<Object?> _chiama(
    String metodo,
    String percorso, {
    Object? corpo,
    (ContentType, Uint8List)? binario,
    bool autenticata = false,
  }) async {
    final uri = Uri(scheme: 'http', host: '$indirizzo.onion', path: percorso);
    final richiesta = await _http.openUrl(metodo, uri);
    if (autenticata) {
      final token = this.token;
      if (token == null) throw StateError('Dispositivo non abbinato');
      richiesta.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (binario case (final tipo, final byte)) {
      richiesta.headers.contentType = tipo;
      richiesta.contentLength = byte.length;
      richiesta.add(byte);
    } else if (corpo != null) {
      final byte = utf8.encode(jsonEncode(corpo));
      richiesta.headers.contentType = ContentType.json;
      richiesta.contentLength = byte.length;
      richiesta.add(byte);
    } else {
      richiesta.contentLength = 0;
    }
    final risposta = await richiesta.close().timeout(timeoutRisposta);
    final testo = await _leggiCorpo(risposta).timeout(timeoutRisposta);
    final Object? json;
    try {
      json = testo.isEmpty ? null : jsonDecode(testo);
    } on FormatException {
      throw ErroreApi(risposta.statusCode, 'risposta_non_valida');
    }
    if (risposta.statusCode >= 200 && risposta.statusCode < 300) return json;

    final secondi = int.tryParse(
      risposta.headers.value(HttpHeaders.retryAfterHeader) ?? '',
    );
    final errore = json is Map<String, Object?> ? json : const <String, Object?>{};
    throw ErroreApi(
      risposta.statusCode,
      errore['errore'] is String ? errore['errore'] as String : 'sconosciuto',
      messaggio: errore['messaggio'] is String ? errore['messaggio'] as String : '',
      riprovaTra: secondi == null ? null : Duration(seconds: secondi),
    );
  }

  Future<String> _leggiCorpo(HttpClientResponse risposta) async {
    final byte = BytesBuilder(copy: false);
    await for (final parte in risposta) {
      byte.add(parte);
      if (byte.length > Limiti.corpoMassimo + 64 * 1024) {
        throw ErroreApi(risposta.statusCode, 'risposta_troppo_grande');
      }
    }
    return utf8.decode(byte.takeBytes());
  }
}
