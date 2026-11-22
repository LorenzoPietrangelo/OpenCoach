import 'dart:io';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/services.dart';

/// Avvia tor con Tor.framework dal codice Swift dell'app (`AppDelegate`) e ne
/// raggiunge la porta di controllo.
///
/// Su iOS la porta di controllo è sul loopback con l'autenticazione a cookie,
/// non su un socket Unix come su Android: Dart non li garantisce su iOS. Per
/// lo stesso motivo il proxy SOCKS va su una porta di loopback, aperta solo
/// mentre l'app la usa: iOS sospende l'app, e tor con lei, appena va in
/// background.
class AvviatoreTorIos implements AvviatoreTor {
  const AvviatoreTorIos();

  static const _canale = MethodChannel('org.opencoach.atleta/tor');

  @override
  Future<AccessoControllo> avvia() async {
    final esito = await _canale.invokeMapMethod<String, Object?>('avvia');
    final porta = esito?['porta'];
    final cookie = esito?['cookie'];
    if (porta is! int || cookie is! Uint8List) {
      throw StateError('Tor.framework non ha indicato la porta di controllo');
    }
    return AccessoControllo(indirizzo: InternetAddress.loopbackIPv4, porta: porta, cookie: cookie);
  }
}
