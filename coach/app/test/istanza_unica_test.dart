import 'dart:convert';
import 'dart:io';

import 'package:coach_app/piattaforma/istanza_unica.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory cartella;

  setUp(() async => cartella = await Directory.systemTemp.createTemp('opencoach_istanza_'));
  tearDown(() => cartella.delete(recursive: true));

  test('un secondo avvio fa mostrare la finestra al primo', () async {
    var mostrata = 0;
    final prima = await IstanzaUnica.ascolta(cartella.path, mostra: () => mostrata++);
    expect(await IstanzaUnica.chiediAllaPrima(cartella.path), isTrue);
    expect(mostrata, 1);
    await prima.chiudi();
    expect(await IstanzaUnica.chiediAllaPrima(cartella.path), isFalse);
  });

  test('senza il segreto giusto la finestra non compare', () async {
    var mostrata = 0;
    final prima = await IstanzaUnica.ascolta(cartella.path, mostra: () => mostrata++);
    final file = File(p.join(cartella.path, 'istanza.json'));
    final dati = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    file.writeAsStringSync(jsonEncode({...dati, 'segreto': 'sbagliato'}));
    expect(await IstanzaUnica.chiediAllaPrima(cartella.path), isFalse);
    expect(mostrata, 0);
    await prima.chiudi();
  });

  test('un file rimasto da un programma chiuso male non blocca l\'avvio', () async {
    File(p.join(cartella.path, 'istanza.json')).writeAsStringSync(jsonEncode({'porta': 1, 'segreto': 'x'}));
    expect(await IstanzaUnica.chiediAllaPrima(cartella.path), isFalse);
    File(p.join(cartella.path, 'istanza.json')).writeAsStringSync('non json');
    expect(await IstanzaUnica.chiediAllaPrima(cartella.path), isFalse);
  });
}
