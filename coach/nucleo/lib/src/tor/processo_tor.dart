import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'controllo_tor.dart';

class ErroreAvvioTor implements Exception {
  const ErroreAvvioTor(this.messaggio);

  final String messaggio;

  @override
  String toString() => 'ErroreAvvioTor: $messaggio';
}

/// Processo `tor` figlio del programma, con una propria cartella dati e la
/// porta di controllo protetta da cookie (§9.2).
class ProcessoTor {
  ProcessoTor._(this._processo, this.controllo);

  final Process _processo;
  final ControlloTor controllo;

  /// Si completa quando il processo termina.
  Future<int> get uscita => _processo.exitCode;

  /// Avvia [eseguibile]. Con [socks] apre anche una porta SOCKS con gli errori
  /// estesi, come serve a un client (§6.1); il programma del coach non la usa.
  static Future<ProcessoTor> avvia({
    required String eseguibile,
    required String cartellaDati,
    bool socks = false,
    void Function(String)? registra,
  }) async {
    await Directory(cartellaDati).create(recursive: true);
    final torrc = File(p.join(cartellaDati, 'torrc'));
    if (!await torrc.exists()) await torrc.writeAsString('');
    final filePorta = File(p.join(cartellaDati, 'porta_controllo'));
    if (await filePorta.exists()) await filePorta.delete();
    final fileCookie = p.join(cartellaDati, 'cookie_controllo');

    final processo = await Process.start(eseguibile, [
      '-f', torrc.path, '--ignore-missing-torrc', //
      '--DataDirectory', cartellaDati,
      '--ControlPort', 'auto',
      '--ControlPortWriteToFile', filePorta.path,
      '--CookieAuthentication', '1',
      '--CookieAuthFile', fileCookie,
      '--SocksPort', socks ? 'auto ExtendedErrors' : '0',
      '--__OwningControllerProcess', '$pid',
      '--Log', 'notice stdout',
    ]);
    for (final flusso in [processo.stdout, processo.stderr]) {
      flusso
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((riga) => registra?.call('tor: $riga'));
    }

    var terminato = false;
    unawaited(processo.exitCode.then((_) => terminato = true));
    final scadenza = DateTime.now().add(const Duration(seconds: 60));
    RegExpMatch? porta;
    while (porta == null) {
      if (terminato) throw const ErroreAvvioTor("Tor si è chiuso durante l'avvio");
      if (DateTime.now().isAfter(scadenza)) {
        processo.kill();
        throw const ErroreAvvioTor('Tor non ha aperto la porta di controllo');
      }
      if (await filePorta.exists()) {
        porta = RegExp(r'PORT=([\d.]+):(\d+)').firstMatch(await filePorta.readAsString());
      }
      if (porta == null) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    try {
      final controllo = await ControlloTor.connetti(porta[1]!, int.parse(porta[2]!));
      await controllo.autenticaConCookie(await File(fileCookie).readAsBytes());
      await controllo.prendiPossesso();
      return ProcessoTor._(processo, controllo);
    } catch (_) {
      processo.kill();
      rethrow;
    }
  }

  /// Porta SOCKS locale, se il processo è stato avviato con `socks: true`.
  Future<int> portaSocks() async {
    final valore = await controllo.leggiInfo('net/listeners/socks');
    final porta = RegExp(r':(\d+)').firstMatch(valore);
    if (porta == null) throw const ErroreAvvioTor('Porta SOCKS assente');
    return int.parse(porta[1]!);
  }

  Future<void> ferma() async {
    try {
      await controllo.comando('SIGNAL HALT').timeout(const Duration(seconds: 5));
    } catch (_) {
      // Tor può chiudere la connessione prima di rispondere.
    }
    await controllo.chiudi();
    await uscita.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _processo.kill();
        return -1;
      },
    );
  }
}
