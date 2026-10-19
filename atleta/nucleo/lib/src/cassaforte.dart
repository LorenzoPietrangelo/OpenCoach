import 'dart:typed_data';

/// Dove il telefono conserva chiavi e token dei dispositivi (§4): cifrati
/// con una chiave del Keystore su Android, nel Keychain su iOS con
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Le voci sono escluse
/// dai backup e dal trasferimento su un nuovo telefono, che va riabbinato.
///
/// L'implementazione per Android e iOS sta nell'app Flutter.
abstract interface class Cassaforte {
  Future<Uint8List?> leggi(String nome);

  Future<void> scrivi(String nome, List<int> valore);

  Future<void> elimina(String nome);
}

/// Cassaforte in memoria, per i test.
class CassaforteMemoria implements Cassaforte {
  final _voci = <String, Uint8List>{};

  /// Nomi delle voci presenti.
  Iterable<String> get nomi => _voci.keys;

  @override
  Future<Uint8List?> leggi(String nome) async => _voci[nome];

  @override
  Future<void> scrivi(String nome, List<int> valore) async =>
      _voci[nome] = Uint8List.fromList(valore);

  @override
  Future<void> elimina(String nome) async => _voci.remove(nome);
}
