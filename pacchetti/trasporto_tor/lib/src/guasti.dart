import 'dart:async';
import 'dart:io';

import 'package:protocollo/protocollo.dart';

/// Come è fallita una chiamata al coach.
enum TipoGuasto {
  /// Il coach non risponde: errori SOCKS diversi da F4 e F5, timeout,
  /// connessione caduta.
  irraggiungibile,

  /// Tor non ha potuto usare la chiave di client authorization: errori
  /// SOCKS F4 o F5.
  chiaveRifiutata,

  /// Il programma del coach ha risposto con un errore HTTP.
  risposta,

  /// La risposta non rispetta il protocollo.
  protocollo,
}

class Guasto {
  const Guasto(this.tipo, [this.errore]);

  final TipoGuasto tipo;

  /// Per [TipoGuasto.risposta], la risposta d'errore.
  final ErroreApi? errore;
}

/// Classifica un errore di una chiamata al coach (§6.4, §7.5). Null se non è
/// un errore di rete né dell'API, cioè un errore di programmazione.
Guasto? classifica(Object errore) => switch (errore) {
  ErroreSocks(autorizzazioneRifiutata: true) => const Guasto(
    TipoGuasto.chiaveRifiutata,
  ),
  ErroreSocks() ||
  ErroreProtocolloSocks() ||
  SocketException() ||
  HttpException() ||
  TimeoutException() => const Guasto(TipoGuasto.irraggiungibile),
  ErroreApi(codice: 'risposta_non_valida' || 'risposta_troppo_grande') =>
    const Guasto(TipoGuasto.protocollo),
  final ErroreApi e => Guasto(TipoGuasto.risposta, e),
  FormatException() => const Guasto(TipoGuasto.protocollo),
  _ => null,
};
