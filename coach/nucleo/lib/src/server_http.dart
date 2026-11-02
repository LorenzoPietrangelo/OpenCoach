import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:protocollo/protocollo.dart';

import 'errori.dart';
import 'limitatore.dart';
import 'modelli.dart';
import 'nucleo.dart';

const _percorsi = {
  '/v1/info',
  '/v1/abbinamento',
  '/v1/abbinamento/conferma',
  '/v1/sync',
  '/v1/dispositivo',
};

/// `PUT /v1/foto/<id>` (§8.6).
const _prefissoFoto = '/v1/foto/';

/// `PUT /v1/video/<id>/<parte>` (§8.7).
final _percorsoVideo = RegExp(r'^/v1/video/([0-9a-f-]{36})/(\d{1,2})$');

/// Server dell'API (§6). Ascolta solo su 127.0.0.1 e accetta solo richieste
/// per `<indirizzo>.onion`: arrivano soltanto attraverso l'onion service.
class ServerCoach {
  ServerCoach(
    this._nucleo, {
    DateTime Function()? adesso,
    void Function(String)? registra,
  }) : _registra = registra ?? ((_) {}),
       _limitePerDispositivo = LimitatoreFrequenza(
         massimo: Limiti.richiesteAlMinutoPerDispositivo,
         adesso: adesso,
       ),
       _limiteAbbinamenti = LimitatoreFrequenza(
         massimo: Limiti.abbinamentiAlMinuto,
         adesso: adesso,
       );

  final NucleoCoach _nucleo;
  final void Function(String) _registra;
  final LimitatoreFrequenza _limitePerDispositivo;
  final LimitatoreFrequenza _limiteAbbinamenti;
  HttpServer? _server;
  var _inCorso = 0;
  var _syncInCorso = 0;
  final _attese = <Completer<void>>[];

  /// Porta locale a cui l'onion service inoltra le connessioni.
  int get porta => _server!.port;

  Future<void> avvia() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.idleTimeout = const Duration(seconds: 120);
    server.listen(_gestisci);
    _server = server;
  }

  Future<void> chiudi() async => _server?.close(force: true);

  /// Aspetta che finiscano le richieste in corso, al massimo per [limite]:
  /// ricreare il servizio onion chiude i circuiti aperti (§9.2).
  Future<void> attendiRichiesteInCorso(Duration limite) async {
    if (_inCorso == 0) return;
    final attesa = Completer<void>();
    _attese.add(attesa);
    await attesa.future.timeout(limite, onTimeout: () {});
  }

  Future<void> _gestisci(HttpRequest richiesta) async {
    _inCorso++;
    try {
      await _instrada(richiesta);
    } on ErroreHttp catch (e) {
      await _rispondi(
        richiesta,
        e.stato,
        {'errore': e.codice, 'messaggio': e.messaggio},
        riprovaTra: e.riprovaTra,
      );
    } catch (e, traccia) {
      _registra('Errore su ${richiesta.method} ${richiesta.uri.path}: $e\n$traccia');
      await _rispondi(richiesta, 500, {
        'errore': CodiceErrore.erroreInterno,
        'messaggio': '',
      });
    } finally {
      _inCorso--;
      if (_inCorso == 0) {
        for (final attesa in _attese) {
          attesa.complete();
        }
        _attese.clear();
      }
    }
  }

  Future<void> _instrada(HttpRequest richiesta) async {
    final host = richiesta.headers.value(HttpHeaders.hostHeader)?.toLowerCase();
    final atteso = '${_nucleo.indirizzo}.onion';
    if (host != atteso && host != '$atteso:80') {
      throw const ErroreHttp(421, CodiceErrore.hostErrato);
    }
    // Una pagina web aperta sul PC del coach potrebbe chiamare la porta
    // locale: i browser mandano sempre Origin, l'app mai (§6.1).
    if (richiesta.headers.value('origin') != null) {
      throw const ErroreHttp(403, CodiceErrore.origineVietata);
    }

    switch ((richiesta.method, richiesta.uri.path)) {
      case ('GET', '/v1/info'):
        await _leggiCorpo(richiesta);
        await _rispondi(richiesta, 200, _nucleo.info().toJson());

      case ('POST', '/v1/abbinamento'):
        final attesa = _limiteAbbinamenti.registra('abbinamento');
        if (attesa != null) {
          throw ErroreHttp(429, CodiceErrore.troppeRichieste, riprovaTra: attesa);
        }
        final corpo = await _leggiJson(richiesta);
        final risposta = _nucleo.abbinamento.abbina(
          _analizza(() => RichiestaAbbinamento.fromJson(corpo)),
        );
        await _rispondi(richiesta, 200, risposta.toJson());

      case ('POST', '/v1/abbinamento/conferma'):
        final dispositivo = _autentica(richiesta);
        await _leggiCorpo(richiesta);
        _nucleo.abbinamento.conferma(dispositivo);
        await _rispondi(richiesta, 204, null);

      case ('POST', '/v1/sync'):
        final dispositivo = _autentica(richiesta);
        if (_syncInCorso >= Limiti.syncContemporanee) {
          throw const ErroreHttp(
            503,
            CodiceErrore.occupato,
            riprovaTra: Duration(seconds: 5),
          );
        }
        _syncInCorso++;
        try {
          final corpo = await _leggiJson(richiesta);
          final risposta = _nucleo.sincronizzazione.sincronizza(
            dispositivo,
            _analizza(() => RichiestaSync.fromJson(corpo)),
          );
          await _rispondi(richiesta, 200, risposta.toJson());
        } finally {
          _syncInCorso--;
        }

      case ('PUT', final percorso) when percorso.startsWith(_prefissoFoto):
        final dispositivo = _autentica(richiesta);
        final jpeg = await _leggiCorpo(richiesta, massimo: Limiti.fotoMassima);
        _nucleo.questionari.salvaFoto(
          dispositivo.atletaId,
          percorso.substring(_prefissoFoto.length),
          jpeg,
        );
        await _rispondi(richiesta, 204, null);

      case ('PUT', final percorso) when _percorsoVideo.hasMatch(percorso):
        final dispositivo = _autentica(richiesta);
        final trovato = _percorsoVideo.firstMatch(percorso)!;
        final dati = await _leggiCorpo(richiesta, massimo: LimitiChat.parteVideo);
        _nucleo.messaggi.salvaParteVideo(dispositivo.atletaId, trovato[1]!, int.parse(trovato[2]!), dati);
        await _rispondi(richiesta, 204, null);

      case ('DELETE', '/v1/dispositivo'):
        final dispositivo = _autentica(richiesta);
        await _leggiCorpo(richiesta);
        _nucleo.dispositivi.revoca(dispositivo.id);
        await _rispondi(richiesta, 204, null);

      case (_, final percorso) when _percorsi.contains(percorso):
        throw const ErroreHttp(405, CodiceErrore.metodoNonAmmesso);

      default:
        throw const ErroreHttp(404, CodiceErrore.nonTrovato);
    }
  }

  Dispositivo _autentica(HttpRequest richiesta) {
    final dispositivo = _nucleo.dispositivi.autentica(
      richiesta.headers.value(HttpHeaders.authorizationHeader),
    );
    if (dispositivo == null) {
      throw const ErroreHttp(401, CodiceErrore.tokenRevocato);
    }
    final attesa = _limitePerDispositivo.registra(dispositivo.id);
    if (attesa != null) {
      throw ErroreHttp(429, CodiceErrore.troppeRichieste, riprovaTra: attesa);
    }
    return dispositivo;
  }

  Future<Uint8List> _leggiCorpo(
    HttpRequest richiesta, {
    int massimo = Limiti.corpoMassimo,
  }) async {
    if (richiesta.contentLength > massimo) {
      throw const ErroreHttp(413, CodiceErrore.troppoGrande);
    }
    final byte = BytesBuilder(copy: false);
    await for (final parte in richiesta) {
      byte.add(parte);
      if (byte.length > massimo) {
        throw const ErroreHttp(413, CodiceErrore.troppoGrande);
      }
    }
    return byte.takeBytes();
  }

  Future<Object?> _leggiJson(HttpRequest richiesta) async {
    final byte = await _leggiCorpo(richiesta);
    try {
      return jsonDecode(utf8.decode(byte));
    } on FormatException {
      throw const ErroreHttp(
        400,
        CodiceErrore.richiestaNonValida,
        messaggio: 'JSON non valido',
      );
    }
  }

  T _analizza<T>(T Function() analisi) {
    try {
      return analisi();
    } on FormatException catch (e) {
      throw ErroreHttp(400, CodiceErrore.richiestaNonValida, messaggio: e.message);
    }
  }

  Future<void> _rispondi(
    HttpRequest richiesta,
    int stato,
    Object? corpo, {
    Duration? riprovaTra,
  }) async {
    final risposta = richiesta.response;
    try {
      risposta.statusCode = stato;
      risposta.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (riprovaTra != null) {
        final secondi = max(1, (riprovaTra.inMilliseconds / 1000).ceil());
        risposta.headers.set(HttpHeaders.retryAfterHeader, '$secondi');
      }
      // Dopo un errore il corpo della richiesta può essere rimasto da leggere:
      // chiudere la connessione è più semplice che svuotarlo.
      if (stato >= 400) risposta.persistentConnection = false;
      if (corpo == null) {
        risposta.contentLength = 0;
      } else {
        final byte = utf8.encode(jsonEncode(corpo));
        risposta.headers.contentType = ContentType.json;
        risposta.contentLength = byte.length;
        risposta.add(byte);
      }
      await risposta.close();
    } catch (e) {
      _registra('Risposta non inviata: $e');
    }
  }
}
