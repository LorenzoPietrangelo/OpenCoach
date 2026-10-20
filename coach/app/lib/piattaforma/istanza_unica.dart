import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:protocollo/protocollo.dart';

/// Un solo programma per cartella dati (§9.1). Il programma avviato apre una
/// porta locale e scrive in `istanza.json` porta e segreto; un secondo avvio
/// la usa per chiedergli di mostrare la finestra, poi termina.
///
/// Il segreto impedisce che un altro processo usi la porta; il peggio che
/// potrebbe fare è comunque far comparire la finestra.
class IstanzaUnica {
  IstanzaUnica._(this._server, this._file);

  final ServerSocket _server;
  final File _file;

  static File _fileIn(String cartellaDati) => File(p.join(cartellaDati, 'istanza.json'));

  /// Chiede al programma già avviato su [cartellaDati] di mostrare la sua
  /// finestra. Falso se nessuno risponde, per esempio perché il file è
  /// rimasto da un programma chiuso male.
  static Future<bool> chiediAllaPrima(
    String cartellaDati, {
    Duration attesa = const Duration(seconds: 2),
  }) async {
    final file = _fileIn(cartellaDati);
    if (!await file.exists()) return false;
    try {
      final dati = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        dati['porta']! as int,
        timeout: attesa,
      );
      try {
        socket.writeln('mostra ${dati['segreto']}');
        await socket.flush();
        final risposta = await utf8.decoder
            .bind(socket)
            .transform(const LineSplitter())
            .first
            .timeout(attesa);
        return risposta == 'ok';
      } finally {
        socket.destroy();
      }
    } on Object {
      return false;
    }
  }

  /// Si mette in ascolto per i secondi avvii, che chiameranno [mostra].
  static Future<IstanzaUnica> ascolta(
    String cartellaDati, {
    required void Function() mostra,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final segreto = codificaBase32(byteCasuali(32));
    final file = _fileIn(cartellaDati);
    await file.writeAsString(jsonEncode({'porta': server.port, 'segreto': segreto}), flush: true);
    server.listen((socket) {
      utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 2))
          .then((riga) {
            if (riga == 'mostra $segreto') {
              mostra();
              socket.writeln('ok');
            }
          })
          .catchError((Object _) {})
          .whenComplete(() async {
            try {
              await socket.flush();
            } on Object {
              // Il secondo avvio può aver già chiuso la connessione.
            }
            socket.destroy();
          });
    });
    return IstanzaUnica._(server, file);
  }

  Future<void> chiudi() async {
    await _server.close();
    if (await _file.exists()) await _file.delete();
  }
}
