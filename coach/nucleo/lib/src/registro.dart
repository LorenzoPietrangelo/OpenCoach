import 'dart:io';

import 'package:path/path.dart' as p;

import 'tempo.dart';

/// Registro tecnico su file, solo locale (§11.2). Quando supera
/// [dimensioneMassima] il file passa a `.1` e ne inizia uno nuovo, così
/// restano al massimo due file.
///
/// Chi scrive nel registro non deve passargli token, chiavi né il contenuto
/// di schede e log.
class RegistroFile {
  RegistroFile(String cartella, {this.dimensioneMassima = 10 * 1024 * 1024})
    : _file = File(p.join(cartella, 'opencoach.log')) {
    Directory(cartella).createSync(recursive: true);
    _dimensione = _file.existsSync() ? _file.lengthSync() : 0;
  }

  final File _file;
  final int dimensioneMassima;
  late int _dimensione;

  String get percorso => _file.path;

  void scrivi(String messaggio) {
    final riga = '${istante(DateTime.now())} $messaggio\n';
    try {
      if (_dimensione + riga.length > dimensioneMassima && _dimensione > 0) {
        final precedente = File('${_file.path}.1');
        if (precedente.existsSync()) precedente.deleteSync();
        _file.renameSync(precedente.path);
        _dimensione = 0;
      }
      _file.writeAsStringSync(riga, mode: FileMode.append, flush: true);
      _dimensione += riga.length;
    } on FileSystemException {
      // Un registro che non si scrive non deve fermare il programma.
    }
  }
}
