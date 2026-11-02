import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'archivio.dart';
import 'backup.dart';
import 'errori.dart';
import 'identita.dart';
import 'nucleo.dart';
import 'portachiavi.dart';
import 'registro.dart';
import 'server_http.dart';
import 'tor/processo_tor.dart';
import 'tor/servizio_onion.dart';

/// Il programma del coach in esecuzione: archivio, server HTTP e Tor, con il
/// riavvio di Tor se si chiude (§9.1, §9.2), i backup automatici (§9.4) e il
/// registro tecnico (§11.2). L'interfaccia lavora su [nucleo] e [backup] e
/// mostra [statoTor].
class ProgrammaCoach {
  ProgrammaCoach._({
    required this.cartellaDati,
    required Identita identita,
    required this.nucleo,
    required this.backup,
    required RandomAccessFile blocco,
    required Archivio archivio,
    required Portachiavi portachiavi,
    required ServerCoach server,
    required String? eseguibileTor,
    required void Function(String) registra,
  }) : _identita = identita,
       _blocco = blocco,
       _archivio = archivio,
       _portachiavi = portachiavi,
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
    bool registroSuFile = true,
    ParametriArgon2 parametriBackup = const ParametriArgon2(),
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

    final file = registroSuFile ? RegistroFile(p.join(cartellaDati, 'registro')) : null;
    void scrivi(String messaggio) {
      file?.scrivi(messaggio);
      registra?.call(messaggio);
    }

    Archivio? archivio;
    try {
      archivio = Archivio.apri(p.join(cartellaDati, 'archivio.db'));
      final identita = await caricaOCreaIdentita(archivio, portachiavi);
      final nucleo = NucleoCoach(
        archivio: archivio,
        indirizzo: identita.indirizzo,
        versioneProgramma: versioneProgramma,
        cartellaVideo: p.join(cartellaDati, 'video'),
      );
      final server = ServerCoach(nucleo, registra: scrivi);
      await server.avvia();
      late final ProgrammaCoach programma;
      programma = ProgrammaCoach._(
        cartellaDati: cartellaDati,
        identita: identita,
        nucleo: nucleo,
        backup: GestioneBackup(
          archivio: archivio,
          identita: () => programma._identita,
          portachiavi: portachiavi,
          versioneProgramma: versioneProgramma,
          parametri: parametriBackup,
        ),
        blocco: blocco,
        archivio: archivio,
        portachiavi: portachiavi,
        server: server,
        eseguibileTor: eseguibileTor,
        registra: scrivi,
      );
      scrivi('Programma avviato, versione $versioneProgramma');
      programma._avviaControlli();
      return programma;
    } catch (_) {
      archivio?.chiudi();
      await blocco.close();
      rethrow;
    }
  }

  /// Ripristina un backup in [cartellaDati] (§9.4). Il programma non deve
  /// essere avviato su quella cartella; dopo il ripristino si avvia con
  /// [avvia]. Vedi [ripristinaBackup].
  static Future<EsitoRipristino> ripristina({
    required String file,
    required String passphrase,
    required String cartellaDati,
    required Portachiavi portachiavi,
  }) => ripristinaBackup(
    file: file,
    passphrase: passphrase,
    cartellaDati: cartellaDati,
    portachiavi: portachiavi,
  );

  /// Ultima risorsa quando l'identità è illeggibile ([IdentitaIllegibile]) e
  /// non c'è un backup: nuova identità nell'archivio che c'è (§4). Atleti,
  /// schede e allenamenti restano; i telefoni vanno riabbinati. Il programma
  /// non deve essere avviato su quella cartella.
  static Future<void> sostituisciIdentitaIllegibile({
    required String cartellaDati,
    required Portachiavi portachiavi,
  }) async {
    final blocco = await File(
      p.join(cartellaDati, 'blocco'),
    ).open(mode: FileMode.write);
    try {
      try {
        await blocco.lock(FileLock.exclusive);
      } on FileSystemException {
        throw const ProgrammaGiaAvviato();
      }
      final archivio = Archivio.apri(p.join(cartellaDati, 'archivio.db'));
      final nuova = await Identita.genera();
      final nucleo = NucleoCoach(archivio: archivio, indirizzo: nuova.indirizzo);
      try {
        nucleo.reimpostaIdentita(
          nuova.indirizzo,
          await cifraSeme(portachiavi, nuova),
        );
      } finally {
        await nucleo.chiudi();
        archivio.chiudi();
      }
    } finally {
      await blocco.close();
    }
  }

  final String cartellaDati;
  final NucleoCoach nucleo;
  final GestioneBackup backup;
  Identita _identita;
  final RandomAccessFile _blocco;
  final Archivio _archivio;
  final Portachiavi _portachiavi;
  final ServerCoach _server;
  final String? _eseguibileTor;
  final void Function(String) _registra;
  final _statoTor = StreamController<StatoTor>.broadcast();
  var _ultimoStato = const StatoTor(FaseTor.avvio);
  final _timer = <Timer>[];
  ProcessoTor? _tor;
  ServizioOnion? _servizio;
  var _chiuso = false;

  Identita get identita => _identita;

  /// Indirizzo onion, senza ".onion".
  String get indirizzo => _identita.indirizzo;

  /// Porta locale del server HTTP.
  int get portaLocale => _server.porta;

  StatoTor get statoTor => _ultimoStato;

  Stream<StatoTor> get cambiamentiStatoTor => _statoTor.stream;

  /// Nuovo indirizzo e nuova identità (§4), da usare se la chiave è stata
  /// compromessa: tutti i telefoni vengono revocati e gli atleti vanno
  /// reinvitati. Tor riparte per pubblicare il nuovo servizio.
  Future<void> reimpostaIdentita() async {
    final nuova = await Identita.genera();
    final semeCifrato = await cifraSeme(_portachiavi, nuova);
    nucleo.reimpostaIdentita(nuova.indirizzo, semeCifrato);
    _identita = nuova;
    _registra('Identità reimpostata');
    // Il ciclo di [_mantieniTor] riavvia Tor con la nuova identità.
    await _tor?.ferma();
  }

  void _avviaControlli() {
    nucleo.inviti.chiudiScaduti();
    _timer
      ..add(
        Timer.periodic(
          const Duration(minutes: 1),
          (_) => nucleo.inviti.chiudiScaduti(),
        ),
      )
      ..add(Timer.periodic(const Duration(hours: 1), (_) => _backupAutomatico()));
    unawaited(_backupAutomatico());
    final eseguibile = _eseguibileTor;
    if (eseguibile != null) unawaited(_mantieniTor(eseguibile));
  }

  Future<void> _backupAutomatico() async {
    try {
      final file = await backup.eseguiSeDovuto();
      if (file != null) _registra('Backup automatico: ${p.basename(file.path)}');
    } catch (e) {
      _registra('Backup automatico non riuscito: $e');
    }
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
          identita: _identita,
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
    for (final t in _timer) {
      t.cancel();
    }
    await _servizio?.chiudi();
    await _tor?.ferma();
    await _server.chiudi();
    await nucleo.chiudi();
    _archivio.chiudi();
    _registra('Programma chiuso');
    await _statoTor.close();
    await _blocco.unlock();
    await _blocco.close();
  }
}
