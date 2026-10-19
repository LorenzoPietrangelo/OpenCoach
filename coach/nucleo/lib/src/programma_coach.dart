import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'archivio.dart';
import 'errori.dart';
import 'identita.dart';
import 'nucleo.dart';
import 'portachiavi.dart';
import 'server_http.dart';
import 'tor/processo_tor.dart';
import 'tor/servizio_onion.dart';

/// Il programma del coach in esecuzione: archivio, server HTTP e Tor, con il
/// riavvio di Tor se si chiude (§9.1, §9.2). L'interfaccia lavora su [nucleo]
/// e mostra [statoTor].
class ProgrammaCoach {
  ProgrammaCoach._({
    required this.cartellaDati,
    required this.identita,
    required this.nucleo,
    required RandomAccessFile blocco,
    required Archivio archivio,
    required ServerCoach server,
    required String? eseguibileTor,
    required void Function(String) registra,
  }) : _blocco = blocco,
       _archivio = archivio,
       _server = server,
       _eseguibileTor = eseguibileTor,
       _registra = registra;

  /// Apre la cartella dati e avvia il programma. Senza [eseguibileTor] il
  /// server resta raggiungibile solo in locale, come serve nei test.
  ///
  /// Lancia [ProgrammaGiaAvviato] se un'altra istanza usa la stessa cartella
  /// e [IdentitaIllegibile] se la chiave d'identità non si può decifrare.
  static Future<ProgrammaCoach> avvia({
    required String cartellaDati,
    required Portachiavi portachiavi,
    String? eseguibileTor,
    String versioneProgramma = '1.0.0',
    void Function(String)? registra,
  }) async {
    await Directory(cartellaDati).create(recursive: true);
    final blocco = await File(
      p.join(cartellaDati, 'blocco'),
    ).open(mode: FileMode.write);
    try {
      await blocco.lock(FileLock.exclusive);
    } on FileSystemException {
      await blocco.close();
      throw const ProgrammaGiaAvviato();
    }

    Archivio? archivio;
    try {
      archivio = Archivio.apri(p.join(cartellaDati, 'archivio.db'));
      final identita = await caricaOCreaIdentita(archivio, portachiavi);
      final nucleo = NucleoCoach(
        archivio: archivio,
        indirizzo: identita.indirizzo,
        versioneProgramma: versioneProgramma,
      );
      final server = ServerCoach(nucleo, registra: registra);
      await server.avvia();
      final programma = ProgrammaCoach._(
        cartellaDati: cartellaDati,
        identita: identita,
        nucleo: nucleo,
        blocco: blocco,
        archivio: archivio,
        server: server,
        eseguibileTor: eseguibileTor,
        registra: registra ?? (_) {},
      );
      programma._avviaControlli();
      return programma;
    } catch (_) {
      archivio?.chiudi();
      await blocco.close();
      rethrow;
    }
  }

  final String cartellaDati;
  final Identita identita;
  final NucleoCoach nucleo;
  final RandomAccessFile _blocco;
  final Archivio _archivio;
  final ServerCoach _server;
  final String? _eseguibileTor;
  final void Function(String) _registra;
  final _statoTor = StreamController<StatoTor>.broadcast();
  var _ultimoStato = const StatoTor(FaseTor.avvio);
  Timer? _scadenze;
  ProcessoTor? _tor;
  ServizioOnion? _servizio;
  var _chiuso = false;

  /// Indirizzo onion, senza ".onion".
  String get indirizzo => identita.indirizzo;

  /// Porta locale del server HTTP.
  int get portaLocale => _server.porta;

  StatoTor get statoTor => _ultimoStato;

  Stream<StatoTor> get cambiamentiStatoTor => _statoTor.stream;

  void _avviaControlli() {
    nucleo.inviti.chiudiScaduti();
    _scadenze = Timer.periodic(
      const Duration(minutes: 1),
      (_) => nucleo.inviti.chiudiScaduti(),
    );
    final eseguibile = _eseguibileTor;
    if (eseguibile != null) unawaited(_mantieniTor(eseguibile));
  }

  void _pubblicaStato(StatoTor stato) {
    _ultimoStato = stato;
    if (!_statoTor.isClosed) _statoTor.add(stato);
  }

  /// Avvia Tor e lo riavvia con attesa crescente, fino a un minuto, se si
  /// chiude in modo inatteso (§9.2).
  Future<void> _mantieniTor(String eseguibile) async {
    var attesa = const Duration(seconds: 1);
    while (!_chiuso) {
      try {
        final tor = _tor = await ProcessoTor.avvia(
          eseguibile: eseguibile,
          cartellaDati: p.join(cartellaDati, 'tor'),
          registra: _registra,
        );
        final servizio = _servizio = ServizioOnion(
          controllo: tor.controllo,
          identita: identita,
          portaLocale: _server.porta,
          chiaviAutorizzate: nucleo.chiaviAutorizzate,
          attendiRichiesteInCorso: _server.attendiRichiesteInCorso,
          registra: _registra,
        );
        final stati = servizio.cambiamenti.listen(_pubblicaStato);
        final chiavi = nucleo.chiaviCambiate.listen((_) => servizio.chiaviCambiate());
        try {
          await servizio.avvia();
          attesa = const Duration(seconds: 1);
          await Future.any([tor.uscita, tor.controllo.chiuso]);
        } finally {
          await stati.cancel();
          await chiavi.cancel();
          await servizio.chiudi();
          _servizio = null;
        }
        if (_chiuso) return;
        _registra('Tor si è chiuso: riavvio');
      } catch (e) {
        if (_chiuso) return;
        _registra('Tor non disponibile: $e');
      }
      await _tor?.ferma();
      _tor = null;
      if (_chiuso) return;
      _pubblicaStato(
        const StatoTor(FaseTor.nonRaggiungibile, motivo: 'Riavvio di Tor in corso'),
      );
      await Future<void>.delayed(attesa);
      attesa = Duration(seconds: min(attesa.inSeconds * 2, 60));
    }
  }

  /// Ferma Tor e il server e chiude l'archivio.
  Future<void> chiudi() async {
    if (_chiuso) return;
    _chiuso = true;
    _scadenze?.cancel();
    await _servizio?.chiudi();
    await _tor?.ferma();
    await _server.chiudi();
    await nucleo.chiudi();
    _archivio.chiudi();
    await _statoTor.close();
    await _blocco.unlock();
    await _blocco.close();
  }
}
