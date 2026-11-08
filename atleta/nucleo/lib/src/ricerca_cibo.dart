import 'dart:async';
import 'dart:io';

import 'package:protocollo/protocollo.dart';
import 'package:trasporto_tor/trasporto_tor.dart';

import 'contesto.dart';
import 'sincronizzazione.dart';

/// Perché una ricerca nel catalogo del coach non è riuscita (§10.3).
enum GuastoCibo {
  /// Niente rete, Tor non parte o nessun coach collegato.
  nonDisponibile,

  /// Il PC del coach è spento o non si raggiunge.
  coachIrraggiungibile,

  /// Il programma del coach non ha il catalogo, o è di una versione che non
  /// lo conosce.
  senzaCatalogo,

  /// Il limite di richieste del coach (§6.2).
  troppeRichieste,

  /// Qualsiasi altro errore.
  altro,
}

class ErroreCibo implements Exception {
  const ErroreCibo(this.guasto);

  final GuastoCibo guasto;

  @override
  String toString() => 'ErroreCibo(${guasto.name})';
}

/// Cerca i cibi nel catalogo che il programma del coach tiene sul PC
/// (§10.3), attraverso Tor come la sync.
class RicercaCibo {
  RicercaCibo(this._c, this._motore);

  final ContestoAtleta _c;
  final MotoreSync _motore;

  /// I prodotti del catalogo con le parole di [testo]. Lancia [ErroreCibo].
  Future<List<ProdottoCibo>> cerca(String testo) =>
      testo.trim().isEmpty ? Future.value(const []) : _chiama((api) => api.cercaCibo(testo.trim()));

  /// Il prodotto con il codice a barre [codice], o null. Lancia [ErroreCibo].
  Future<ProdottoCibo?> perCodice(String codice) =>
      RegExp(r'^\d{8,14}$').hasMatch(codice) ? _chiama((api) => api.ciboPerCodice(codice)) : Future.value();

  Future<T> _chiama<T>(Future<T> Function(ClienteApi api) chiamata) async {
    final coach = _c.coachAttivi().firstOrNull;
    if (coach == null) throw const ErroreCibo(GuastoCibo.nonDisponibile);
    try {
      return await _motore.chiamaCoach(coach.id, chiamata);
    } on ErroreCibo {
      rethrow;
    } on TorNonParte {
      throw const ErroreCibo(GuastoCibo.nonDisponibile);
    } on ErroreApi catch (e) {
      _c.registra('Ricerca dei cibi: $e');
      throw ErroreCibo(switch (e.stato) {
        404 || 405 => GuastoCibo.senzaCatalogo,
        429 || 503 => GuastoCibo.troppeRichieste,
        _ => GuastoCibo.altro,
      });
    } on Object catch (e) {
      _c.registra('Ricerca dei cibi non riuscita: $e');
      throw ErroreCibo(switch (classifica(e)?.tipo) {
        TipoGuasto.irraggiungibile || TipoGuasto.chiaveRifiutata => GuastoCibo.coachIrraggiungibile,
        _ when e is SocketException || e is TimeoutException => GuastoCibo.coachIrraggiungibile,
        _ => GuastoCibo.altro,
      });
    }
  }
}
