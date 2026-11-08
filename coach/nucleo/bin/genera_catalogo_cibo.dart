// Genera il catalogo dei prodotti venduti in Italia (§10.3) dall'esportazione
// CSV di Open Food Facts, per il programma del coach:
//
//   dart run bin/genera_catalogo_cibo.dart [file.csv.gz]
//
// Senza file scarica l'esportazione di oggi (circa 1,5 GB compressi) e la
// legge mentre arriva, senza salvarla. Il catalogo finisce in
// coach/app/windows/cibo/catalogo_italia.sqlite: la build lo mette accanto a
// OpenCoach.exe, e l'installer lo porta sul PC del coach. I dati sono sotto
// licenza ODbL: il file va pubblicato insieme all'installer che lo contiene.
import 'dart:convert';
import 'dart:io';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const _esportazione = 'https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz';

Future<void> main(List<String> argomenti) async {
  final destinazione = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '..', '..', 'app', 'windows', 'cibo', 'catalogo_italia.sqlite'),
  );
  final temporaneo = '$destinazione.parziale';
  for (final file in [File(temporaneo), File('$temporaneo-journal')]) {
    if (file.existsSync()) file.deleteSync();
  }
  Directory(p.dirname(destinazione)).createSync(recursive: true);

  final HttpClient? http;
  final Stream<List<int>> compresso;
  if (argomenti.isNotEmpty) {
    http = null;
    compresso = File(argomenti.first).openRead();
  } else {
    http = HttpClient();
    final richiesta = await http.getUrl(Uri.parse(_esportazione));
    richiesta.headers.set(HttpHeaders.userAgentHeader, 'OpenCoach/genera-catalogo (https://github.com/LorenzoPietrangelo/OpenCoach)');
    final risposta = await richiesta.close();
    if (risposta.statusCode != 200) {
      stderr.writeln('Open Food Facts ha risposto ${risposta.statusCode}');
      exit(1);
    }
    compresso = risposta;
  }

  final righe = compresso
      .transform(gzip.decoder)
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());
  final db = sqlite3.open(temporaneo);
  final inizio = DateTime.now();
  try {
    final esito = await generaCatalogo(righe, db, adesso: DateTime.now());
    db.close();
    File(temporaneo).renameSync(destinazione);
    final mb = File(destinazione).lengthSync() / (1024 * 1024);
    stdout.writeln(
      'Righe lette: ${esito.righe}. Prodotti nel catalogo: ${esito.prodotti}. '
      '${mb.toStringAsFixed(1)} MB in ${DateTime.now().difference(inizio).inMinutes} minuti.\n$destinazione',
    );
  } finally {
    http?.close(force: true);
  }
}
