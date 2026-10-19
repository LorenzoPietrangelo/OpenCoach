import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Portachiavi del sistema operativo (§4). L'interfaccia desktop lo
/// implementa con DPAPI, Keychain o Secret Service.
abstract interface class Portachiavi {
  Future<Uint8List?> leggi(String nome);

  Future<void> scrivi(String nome, List<int> valore);
}

/// Portachiavi in memoria, per i test.
class PortachiaviMemoria implements Portachiavi {
  final _voci = <String, Uint8List>{};

  @override
  Future<Uint8List?> leggi(String nome) async => _voci[nome];

  @override
  Future<void> scrivi(String nome, List<int> valore) async =>
      _voci[nome] = Uint8List.fromList(valore);
}

/// Ripiego quando il portachiavi del sistema operativo non c'è: un file per
/// voce in [cartella], leggibile solo dall'utente (§4).
class PortachiaviFile implements Portachiavi {
  PortachiaviFile(this.cartella);

  final String cartella;

  File _file(String nome) => File(p.join(cartella, '$nome.chiave'));

  @override
  Future<Uint8List?> leggi(String nome) async {
    final file = _file(nome);
    if (!await file.exists()) return null;
    return base64.decode((await file.readAsString()).trim());
  }

  @override
  Future<void> scrivi(String nome, List<int> valore) async {
    await Directory(cartella).create(recursive: true);
    final file = _file(nome);
    await file.writeAsString(base64.encode(valore), flush: true);
    // Su Windows la cartella dati dell'utente è già protetta dai permessi del
    // profilo.
    if (!Platform.isWindows) await Process.run('chmod', ['600', file.path]);
  }
}
