import 'dart:io';

import 'package:path/path.dart' as p;

/// Cartella dati del coach (§8.3): `%APPDATA%\OpenCoach`,
/// `~/Library/Application Support/OpenCoach` o `~/.local/share/opencoach`.
String cartellaDatiPredefinita() {
  final ambiente = Platform.environment;
  if (Platform.isWindows) return p.join(ambiente['APPDATA']!, 'OpenCoach');
  final casa = ambiente['HOME']!;
  if (Platform.isMacOS) {
    return p.join(casa, 'Library', 'Application Support', 'OpenCoach');
  }
  return p.join(ambiente['XDG_DATA_HOME'] ?? p.join(casa, '.local', 'share'), 'opencoach');
}

/// File in cui il coach può indicare un `tor` esterno (§9.2,
/// impostazione avanzata). Vale dal riavvio successivo.
File fileTorEsterno(String cartellaDati) =>
    File(p.join(cartellaDati, 'eseguibile_tor.txt'));

String? leggiTorEsterno(String cartellaDati) {
  final file = fileTorEsterno(cartellaDati);
  if (!file.existsSync()) return null;
  final percorso = file.readAsStringSync().trim();
  return percorso.isEmpty ? null : percorso;
}

void scriviTorEsterno(String cartellaDati, String? percorso) {
  final file = fileTorEsterno(cartellaDati);
  if (percorso == null || percorso.trim().isEmpty) {
    if (file.existsSync()) file.deleteSync();
  } else {
    file.writeAsStringSync(percorso.trim());
  }
}

/// L'eseguibile tor da usare, nell'ordine: quello esterno scelto dal coach,
/// la variabile OPENCOACH_TOR (per lo sviluppo), quello incluso accanto al
/// programma. Null se non c'è.
String? trovaTor(String cartellaDati) {
  final candidati = [
    leggiTorEsterno(cartellaDati),
    Platform.environment['OPENCOACH_TOR'],
    p.join(
      p.dirname(Platform.resolvedExecutable),
      'tor',
      Platform.isWindows ? 'tor.exe' : 'tor',
    ),
  ];
  for (final candidato in candidati) {
    if (candidato != null && File(candidato).existsSync()) return candidato;
  }
  return null;
}

/// Il catalogo dei cibi (§10.3), nell'ordine: la variabile
/// OPENCOACH_CATALOGO_CIBO (per lo sviluppo), quello incluso accanto al
/// programma. Null se non c'è.
String? trovaCatalogoCibo() {
  final candidati = [
    Platform.environment['OPENCOACH_CATALOGO_CIBO'],
    p.join(p.dirname(Platform.resolvedExecutable), 'cibo', 'catalogo_italia.sqlite'),
  ];
  for (final candidato in candidati) {
    if (candidato != null && File(candidato).existsSync()) return candidato;
  }
  return null;
}
