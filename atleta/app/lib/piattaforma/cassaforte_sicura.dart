import 'dart:convert';
import 'dart:typed_data';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cassaforte del telefono per chiavi e token (§4): su Android cifrati con
/// una chiave del Keystore, su iOS nel Keychain con
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, così la sync in
/// background può leggerli e non passano a un nuovo telefono. I backup di
/// Android sono disattivati nel manifest.
class CassaforteSicura implements Cassaforte {
  CassaforteSicura([FlutterSecureStorage? archivio])
    : _archivio =
          archivio ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _archivio;

  @override
  Future<Uint8List?> leggi(String nome) async {
    final valore = await _archivio.read(key: nome);
    return valore == null ? null : base64.decode(valore);
  }

  @override
  Future<void> scrivi(String nome, List<int> valore) =>
      _archivio.write(key: nome, value: base64.encode(valore));

  @override
  Future<void> elimina(String nome) => _archivio.delete(key: nome);
}
