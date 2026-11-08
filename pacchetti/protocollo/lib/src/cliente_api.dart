import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cibo.dart';
import 'limiti.dart';
import 'messaggi.dart';
import 'socks5.dart';
import 'telefono_coach.dart';
import 'validazione.dart';

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

  /// `POST /v1/attendi`: vero se il coach ha qualcosa di nuovo. Un programma
  /// precedente alla 1.3.1 risponde 404.
  Future<bool> attendiNovita(RichiestaAttesa richiesta) async =>
      RispostaAttesa.fromJson(
        await _chiama(
          'POST',
          '/v1/attendi',
          corpo: richiesta.toJson(),
          autenticata: true,
        ),
      ).novita;

  Future<void> scollega() =>
      _chiama('DELETE', '/v1/dispositivo', autenticata: true);

  /// `PUT /v1/foto/<id>`: una foto di un questionario, in JPEG (§8.6).
  /// Idempotente: ricaricare la stessa foto non cambia nulla.
  /// `GET /v1/cibo`: i prodotti del catalogo del coach che contengono le
  /// parole di [testo] (§10.3). Quelli non conformi si saltano.
  Future<List<ProdottoCibo>> cercaCibo(String testo) async {
    final m = _oggetto(await _chiama('GET', '/v1/cibo', parametri: {'q': testo}, autenticata: true));
    return [
      if (m['prodotti'] case final List<Object?> prodotti)
        for (final p in prodotti)
          if (validaProdottoCibo(p).isEmpty) ProdottoCibo.fromJson(p! as Map<String, Object?>),
    ];
  }

  /// `GET /v1/cibo/<codice>`: il prodotto con quel codice a barre, o null.
  Future<ProdottoCibo?> ciboPerCodice(String codice) async {
    final p = _oggetto(await _chiama('GET', '/v1/cibo/$codice', autenticata: true))['prodotto'];
    return p != null && validaProdottoCibo(p).isEmpty ? ProdottoCibo.fromJson(p as Map<String, Object?>) : null;
  }

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

  // Il telefono del coach (§16.3).

  Future<RispostaAbbinamentoTelefono> abbinaTelefonoCoach(RichiestaAbbinamento richiesta) async =>
      RispostaAbbinamentoTelefono.fromJson(
        await _chiama('POST', '/v1/coach/abbinamento', corpo: richiesta.toJson()),
      );

  Future<void> confermaTelefonoCoach() =>
      _chiama('POST', '/v1/coach/abbinamento/conferma', autenticata: true);

  Future<void> scollegaTelefonoCoach() =>
      _chiama('DELETE', '/v1/coach/telefono', autenticata: true);

  /// `GET /v1/coach/atleti`: l'elenco e l'impronta dello stato.
  Future<({List<Map<String, Object?>> atleti, String impronta})> atletiCoach() async {
    final m = _oggetto(await _chiama('GET', '/v1/coach/atleti', autenticata: true));
    final impronta = m['impronta'];
    if (impronta is! String) throw const FormatException('Campo "impronta" mancante');
    return (atleti: _elementi(m, 'atleti'), impronta: impronta);
  }

  Future<Map<String, Object?>> atletaCoach(String id) async =>
      _oggetto(await _chiama('GET', '/v1/coach/atleti/$id', autenticata: true));

  Future<PaginaDatiCoach> messaggiCoach(String atletaId, {String? prima}) =>
      _paginaCoach('/v1/coach/atleti/$atletaId/messaggi', 'messaggi', prima);

  Future<PaginaDatiCoach> allenamentiCoach(String atletaId, {String? prima}) =>
      _paginaCoach('/v1/coach/atleti/$atletaId/allenamenti', 'allenamenti', prima);

  Future<PaginaDatiCoach> questionariCoach(String atletaId) =>
      _paginaCoach('/v1/coach/atleti/$atletaId/questionari', 'questionari', null);

  /// Manda un messaggio all'atleta. Idempotente: rimandare lo stesso [id] non
  /// lo duplica.
  Future<Map<String, Object?>> inviaMessaggioCoach(String atletaId, String id, String testo) async => _oggetto(
    await _chiama(
      'POST',
      '/v1/coach/atleti/$atletaId/messaggi',
      corpo: {'id': id, 'testo': testo},
      autenticata: true,
    ),
  );

  Future<void> segnaLettiCoach(String atletaId) =>
      _chiama('POST', '/v1/coach/atleti/$atletaId/messaggi/letti', autenticata: true);

  Future<List<Map<String, Object?>>> pesiCoach(String atletaId) async => _elementi(
    _oggetto(await _chiama('GET', '/v1/coach/atleti/$atletaId/pesi', autenticata: true)),
    'pesi',
  );

  /// `GET /v1/coach/atleti/<id>/cibo`: l'obiettivo e le giornate prima del
  /// giorno [prima], dalla più recente.
  Future<Map<String, Object?>> ciboCoach(String atletaId, {String? prima}) async => _oggetto(
    await _chiama(
      'GET',
      '/v1/coach/atleti/$atletaId/cibo',
      parametri: prima == null ? null : {'prima': prima},
      autenticata: true,
    ),
  );

  Future<void> segnaQuestionarioLettoCoach(String id) =>
      _chiama('POST', '/v1/coach/questionari/$id/letto', autenticata: true);

  /// `GET /v1/coach/foto/<id>`: i byte del JPEG.
  Future<Uint8List> fotoCoach(String id) async {
    final token = this.token;
    if (token == null) throw StateError('Telefono non abbinato');
    final richiesta = await _http.openUrl(
      'GET',
      Uri(scheme: 'http', host: '$indirizzo.onion', path: '/v1/coach/foto/$id'),
    );
    richiesta.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    richiesta.contentLength = 0;
    final risposta = await richiesta.close().timeout(timeoutRisposta);
    final byte = await _leggiByte(risposta).timeout(timeoutRisposta);
    if (risposta.statusCode >= 200 && risposta.statusCode < 300) return byte;
    Object? json;
    try {
      json = jsonDecode(utf8.decode(byte));
    } on FormatException {
      json = null;
    }
    throw _errore(risposta, json);
  }

  /// `POST /v1/coach/attendi`: vero appena l'impronta è diversa da [impronta],
  /// falso dopo [attesaS] secondi.
  Future<bool> attendiCoach(String impronta, {int attesaS = Limiti.attesaNovitaS}) async {
    final m = _oggetto(
      await _chiama(
        'POST',
        '/v1/coach/attendi',
        corpo: {'impronta': impronta, 'attesa_s': attesaS},
        autenticata: true,
      ),
    );
    if (m['novita'] case final bool novita) return novita;
    throw const FormatException('Campo "novita" mancante');
  }

  Future<PaginaDatiCoach> _paginaCoach(String percorso, String chiave, String? prima) async {
    final m = _oggetto(
      await _chiama(
        'GET',
        percorso,
        parametri: prima == null ? null : {'prima': prima},
        autenticata: true,
      ),
    );
    return PaginaDatiCoach(_elementi(m, chiave), altri: m['altri'] == true);
  }

  Map<String, Object?> _oggetto(Object? json) {
    if (json is Map<String, Object?>) return json;
    throw const FormatException('Atteso un oggetto JSON');
  }

  List<Map<String, Object?>> _elementi(Map<String, Object?> m, String chiave) {
    final lista = m[chiave];
    if (lista is List<Object?>) return lista.whereType<Map<String, Object?>>().toList();
    throw FormatException('Campo "$chiave" mancante o non valido');
  }

  Future<Object?> _chiama(
    String metodo,
    String percorso, {
    Object? corpo,
    (ContentType, Uint8List)? binario,
    bool autenticata = false,
    Map<String, String>? parametri,
  }) async {
    final uri = Uri(scheme: 'http', host: '$indirizzo.onion', path: percorso, queryParameters: parametri);
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
    throw _errore(risposta, json);
  }

  ErroreApi _errore(HttpClientResponse risposta, Object? json) {
    final secondi = int.tryParse(
      risposta.headers.value(HttpHeaders.retryAfterHeader) ?? '',
    );
    final errore = json is Map<String, Object?> ? json : const <String, Object?>{};
    return ErroreApi(
      risposta.statusCode,
      errore['errore'] is String ? errore['errore'] as String : 'sconosciuto',
      messaggio: errore['messaggio'] is String ? errore['messaggio'] as String : '',
      riprovaTra: secondi == null ? null : Duration(seconds: secondi),
    );
  }

  Future<String> _leggiCorpo(HttpClientResponse risposta) async =>
      utf8.decode(await _leggiByte(risposta));

  Future<Uint8List> _leggiByte(HttpClientResponse risposta) async {
    final byte = BytesBuilder(copy: false);
    await for (final parte in risposta) {
      byte.add(parte);
      if (byte.length > Limiti.corpoMassimo + 64 * 1024) {
        throw ErroreApi(risposta.statusCode, 'risposta_troppo_grande');
      }
    }
    return byte.takeBytes();
  }
}
