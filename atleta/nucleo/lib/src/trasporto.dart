import 'dart:io';
import 'dart:typed_data';

/// Client Tor incorporato nell'app (§10.1): un'unica istanza per tutti i
/// coach, con una chiave di client authorization per ciascun indirizzo.
/// Ascolta solo su loopback e lo usa solo l'app.
///
/// L'implementazione per Android e iOS sta nell'app Flutter (tor-android,
/// Tor.framework o Arti); i test usano un trasporto che si collega
/// direttamente ai server locali dei coach.
abstract interface class TrasportoTor {
  /// Avvia Tor, se non è già attivo, e aspetta il bootstrap. Lancia
  /// [TorNonParte] se non si completa entro 60 s (§7.5).
  Future<void> avvia();

  /// Ferma Tor: con l'app in background resta spento, salvo durante le sync
  /// (§7.4). Il suo stato (consenso, guardie) resta salvato.
  Future<void> ferma();

  /// Riavvia il client, che così scarta i descrittori in cache (§5.3,
  /// punto 6).
  Future<void> riavvia();

  /// Imposta la chiave privata X25519 di client authorization per
  /// [indirizzo] (senza ".onion"), al posto di quella eventualmente presente.
  ///
  /// Le chiavi restano valide dopo [riavvia] e [ferma] ma solo in memoria,
  /// mai nei file di Tor: l'app le imposta di nuovo a ogni esecuzione.
  Future<void> impostaChiave(String indirizzo, Uint8List chiavePrivata);

  Future<void> rimuoviChiave(String indirizzo);

  /// [HttpClient] che raggiunge gli indirizzi `.onion` attraverso il proxy
  /// SOCKS5 di Tor, con gli errori estesi attivi: di solito
  /// `clienteHttpTramiteTor` del protocollo. Lo chiude chi lo usa.
  HttpClient creaHttpClient();
}

/// Il bootstrap di Tor non si è completato in tempo: di solito la rete
/// blocca Tor (§7.5, §13).
class TorNonParte implements Exception {
  const TorNonParte();

  @override
  String toString() => 'TorNonParte';
}

/// Disponibilità della rete secondo il sistema operativo (§7.5, «Nessuna
/// rete»).
abstract interface class Connettivita {
  Future<bool> disponibile();
}

/// Per chi non sa leggere lo stato della rete: la sync lo scoprirà da sé.
class ReteSempreDisponibile implements Connettivita {
  const ReteSempreDisponibile();

  @override
  Future<bool> disponibile() async => true;
}
