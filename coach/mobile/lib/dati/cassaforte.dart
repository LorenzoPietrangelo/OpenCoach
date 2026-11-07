import 'dart:convert';

/// Dove restano le poche cose che sopravvivono al processo (§16.4): su Android
/// cifrate con una chiave del Keystore. I valori sono JSON.
abstract interface class Cassaforte {
  Future<String?> leggi(String nome);

  Future<void> scrivi(String nome, String valore);

  Future<void> elimina(String nome);
}

/// Per i test.
class CassaforteInMemoria implements Cassaforte {
  final voci = <String, String>{};

  @override
  Future<String?> leggi(String nome) async => voci[nome];

  @override
  Future<void> scrivi(String nome, String valore) async => voci[nome] = valore;

  @override
  Future<void> elimina(String nome) async => voci.remove(nome);
}

/// Il JSON di una voce; null se manca o è illeggibile.
Future<Object?> leggiJson(Cassaforte cassaforte, String nome) async {
  final testo = await cassaforte.leggi(nome);
  if (testo == null) return null;
  try {
    return jsonDecode(testo);
  } on FormatException {
    return null;
  }
}
