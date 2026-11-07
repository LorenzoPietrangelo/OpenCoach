import 'dart:io';

import 'package:flutter/services.dart';
import 'package:trasporto_tor/trasporto_tor.dart';

/// Avvia TorService di tor-android dal codice Kotlin dell'app (MotoreFlutter) e
/// ne raggiunge la porta di controllo, un socket Unix nella sua cartella dati.
class AvviatoreTorAndroid implements AvviatoreTor {
  const AvviatoreTorAndroid();

  static const _canale = MethodChannel('org.opencoach.coach/tor');

  @override
  Future<AccessoControllo> avvia() async {
    final percorso = await _canale.invokeMethod<String>('avvia');
    if (percorso == null) {
      throw StateError('TorService non ha indicato la porta di controllo');
    }
    return AccessoControllo(
      indirizzo: InternetAddress(percorso, type: InternetAddressType.unix),
      // Il proxy SOCKS va accanto alla porta di controllo, in una cartella che
      // solo l'app può aprire: così Tor lo usa solo l'app (§10.1).
      socketSocks: '${File(percorso).parent.path}/socks',
    );
  }
}
