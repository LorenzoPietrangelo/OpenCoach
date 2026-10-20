import 'dart:convert';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

/// Portachiavi del sistema operativo (§4): su Windows i dati sono protetti
/// da DPAPI, su macOS stanno nel Keychain, su Linux nel Secret Service.
class PortachiaviSistema implements Portachiavi {
  const PortachiaviSistema([this._memoria = const FlutterSecureStorage()]);

  final FlutterSecureStorage _memoria;

  static const _prefisso = 'opencoach_';

  @override
  Future<Uint8List?> leggi(String nome) async {
    final valore = await _memoria.read(key: '$_prefisso$nome');
    return valore == null ? null : base64.decode(valore);
  }

  @override
  Future<void> scrivi(String nome, List<int> valore) =>
      _memoria.write(key: '$_prefisso$nome', value: base64.encode(valore));
}

/// Il portachiavi del sistema se funziona; altrimenti, per esempio su Linux
/// senza Secret Service, il ripiego su file del §4.
Future<Portachiavi> scegliPortachiavi(String cartellaDati) async {
  const sistema = PortachiaviSistema();
  try {
    await sistema.leggi('prova');
    return sistema;
  } on PlatformException {
    return PortachiaviFile(p.join(cartellaDati, 'portachiavi'));
  } on MissingPluginException {
    return PortachiaviFile(p.join(cartellaDati, 'portachiavi'));
  }
}
