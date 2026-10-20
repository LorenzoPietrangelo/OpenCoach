import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Consegna all'atleta il file con i suoi dati (§10.2, §11.3) con la
/// condivisione del sistema, che lo salva in File o su un'altra app, oppure
/// lo manda. Nessuna rete: decide l'atleta dove va il file.
///
/// Il file si scrive nella cache privata dell'app, esclusa dai backup, e si
/// cancella appena la condivisione finisce. Su Android share_plus ne passa
/// all'altra app una sua copia, che resta nella sua cartella della cache fino
/// alla condivisione successiva.
Future<void> esportaFile(String nome, String contenuto) async {
  final cartella = Directory(
    '${(await getTemporaryDirectory()).path}'
    '${Platform.pathSeparator}esportazioni',
  );
  if (await cartella.exists()) await cartella.delete(recursive: true);
  await cartella.create(recursive: true);
  try {
    final file = File('${cartella.path}${Platform.pathSeparator}$nome');
    await file.writeAsString(contenuto, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: nome,
      ),
    );
  } finally {
    await cartella.delete(recursive: true);
  }
}
