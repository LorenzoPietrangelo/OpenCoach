import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'trasporto_controllato.dart';

/// Avvia `tor` come processo figlio, con una propria cartella dati e la
/// porta di controllo protetta da cookie. Serve a provare l'app su un PC
/// (`atleta_dev`) e sulla rete Tor vera; sui telefoni Tor lo avvia la
/// piattaforma.
class AvviatoreTorProcesso implements AvviatoreTor {
  AvviatoreTorProcesso({
    required this.eseguibile,
    required this.cartellaDati,
    this.log = 'notice',
    void Function(String)? registra,
  }) : _registra = registra ?? ((_) {});

  final String eseguibile;
  final String cartellaDati;

  /// Livelli del registro di tor, nella sintassi dell'opzione `Log` senza la
  /// destinazione: per esempio `[rend]info notice` per seguire anche i
  /// servizi onion. Le righe arrivano a `registra`.
  final String log;
  final void Function(String) _registra;

  Process? _processo;
  AccessoControllo? _accesso;
  var _terminato = true;

  /// Tempo concesso a tor per aprire la porta di controllo.
  static const _attesaPorta = Duration(seconds: 60);

  @override
  Future<AccessoControllo> avvia() async {
    final accesso = _accesso;
    if (accesso != null && !_terminato) return accesso;
    await Directory(cartellaDati).create(recursive: true);
    final torrc = File(_percorso('torrc'));
    if (!await torrc.exists()) await torrc.writeAsString('');
    final filePorta = File(_percorso('porta_controllo'));
    if (await filePorta.exists()) await filePorta.delete();
    final fileCookie = File(_percorso('cookie_controllo'));

    final processo = await Process.start(eseguibile, [
      '-f', torrc.path, '--ignore-missing-torrc', //
      '--DataDirectory', cartellaDati,
      '--ControlPort', 'auto',
      '--ControlPortWriteToFile', filePorta.path,
      '--CookieAuthentication', '1',
      '--CookieAuthFile', fileCookie.path,
      '--SocksPort', 'auto ExtendedErrors',
      // Se il programma si chiude, tor lo segue.
      '--__OwningControllerProcess', '$pid',
      '--Log', '$log stdout',
    ]);
    _processo = processo;
    _terminato = false;
    unawaited(processo.exitCode.then((_) => _terminato = true));
    for (final flusso in [processo.stdout, processo.stderr]) {
      flusso
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((riga) => _registra('tor: $riga'));
    }

    final scadenza = DateTime.now().add(_attesaPorta);
    while (true) {
      if (_terminato) throw StateError("tor si è chiuso durante l'avvio");
      if (await filePorta.exists()) {
        final porta = RegExp(
          r'PORT=([\d.]+):(\d+)',
        ).firstMatch(await filePorta.readAsString());
        if (porta != null && await fileCookie.exists()) {
          return _accesso = AccessoControllo(
            indirizzo: InternetAddress(porta[1]!),
            porta: int.parse(porta[2]!),
            cookie: await fileCookie.readAsBytes(),
          );
        }
      }
      if (DateTime.now().isAfter(scadenza)) {
        processo.kill();
        throw StateError('tor non ha aperto la porta di controllo');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Chiude il processo tor, se è attivo, e aspetta che sia uscito: il
  /// prossimo [avvia] può riusare la stessa cartella dati.
  Future<void> ferma() async {
    final processo = _processo;
    if (processo == null || _terminato) return;
    processo.kill();
    await processo.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
  }

  String _percorso(String nome) =>
      '$cartellaDati${Platform.pathSeparator}$nome';
}
