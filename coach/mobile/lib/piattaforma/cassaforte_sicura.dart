import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dati/cassaforte.dart';

/// Cifrata con una chiave del Keystore (§4): i controlli in background la
/// leggono anche con il telefono bloccato, dopo il primo sblocco. I backup di
/// Android sono disattivati nel manifest.
class CassaforteSicura implements Cassaforte {
  const CassaforteSicura();

  static const _archivio = FlutterSecureStorage();

  @override
  Future<String?> leggi(String nome) => _archivio.read(key: nome);

  @override
  Future<void> scrivi(String nome, String valore) => _archivio.write(key: nome, value: valore);

  @override
  Future<void> elimina(String nome) => _archivio.delete(key: nome);
}
