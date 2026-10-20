import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:protocollo/protocollo.dart';

import 'archivio.dart';
import 'cifratura.dart';
import 'errori.dart';
import 'identita.dart';
import 'portachiavi.dart';
import 'tempo.dart';

// Formato del file di backup (§9.4):
//
//   "OCBACKUP" | versione (1 byte) | memoria, iterazioni (uint32 big endian)
//   | parallelismo (1 byte) | sale (16 byte) | contenuto cifrato
//
// La chiave è Argon2id(passphrase, sale) con i parametri scritti in chiaro;
// il contenuto è cifrato con XChaCha20-Poly1305 (vedi `cifra`) e contiene
// la lunghezza dell'intestazione (uint32), l'intestazione JSON con il seme
// d'identità e l'istantanea SQLite dell'archivio.

const _magia = 'OCBACKUP';
const _versioneFormato = 1;
const _lunghezzaSale = 16;
const _voceChiaveBackup = 'chiave_backup';
const _estensione = '.ocbackup';

/// Backup automatici da conservare (§9.4).
const backupDaConservare = 5;

/// Oltre questa età il programma ricorda di fare un backup (§9.4).
const etaPromemoriaBackup = Duration(days: 30);

/// La passphrase è sbagliata oppure il file è stato alterato.
class PassphraseErrata implements Exception {
  const PassphraseErrata();

  @override
  String toString() => 'PassphraseErrata';
}

/// Il file non è un backup di Open Coach o usa un formato più recente.
class BackupNonValido implements Exception {
  const BackupNonValido(this.messaggio);

  final String messaggio;

  @override
  String toString() => 'BackupNonValido: $messaggio';
}

/// Parametri di Argon2id. Quelli predefiniti chiedono 64 MiB e qualche
/// secondo: rendono lento provare passphrase a caso su un backup rubato.
class ParametriArgon2 {
  const ParametriArgon2({
    this.memoria = 64 * 1024,
    this.iterazioni = 3,
    this.parallelismo = 1,
  });

  /// In KiB.
  final int memoria;
  final int iterazioni;
  final int parallelismo;
}

/// Chiave derivata dalla passphrase, con quanto serve per derivarla di nuovo.
class ChiaveBackup {
  const ChiaveBackup._(this.sale, this.parametri, this.chiave);

  static Future<ChiaveBackup> deriva(
    String passphrase, {
    List<int>? sale,
    ParametriArgon2 parametri = const ParametriArgon2(),
  }) async {
    final saleUsato = Uint8List.fromList(sale ?? byteCasuali(_lunghezzaSale));
    final derivata = await Argon2id(
      parallelism: parametri.parallelismo,
      memory: parametri.memoria,
      iterations: parametri.iterazioni,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: saleUsato);
    return ChiaveBackup._(
      saleUsato,
      parametri,
      Uint8List.fromList(await derivata.extractBytes()),
    );
  }

  final Uint8List sale;
  final ParametriArgon2 parametri;
  final Uint8List chiave;

  Uint8List serializza() => utf8.encode(
    jsonEncode({
      'sale': base64.encode(sale),
      'memoria': parametri.memoria,
      'iterazioni': parametri.iterazioni,
      'parallelismo': parametri.parallelismo,
      'chiave': base64.encode(chiave),
    }),
  );

  static ChiaveBackup? leggi(List<int>? byte) {
    if (byte == null) return null;
    try {
      final m = jsonDecode(utf8.decode(byte)) as Map<String, Object?>;
      return ChiaveBackup._(
        base64.decode(m['sale'] as String),
        ParametriArgon2(
          memoria: m['memoria'] as int,
          iterazioni: m['iterazioni'] as int,
          parallelismo: m['parallelismo'] as int,
        ),
        base64.decode(m['chiave'] as String),
      );
    } on Object {
      return null;
    }
  }
}

/// Contenuto di un backup già decifrato.
class ContenutoBackup {
  const ContenutoBackup({
    required this.seme,
    required this.indirizzo,
    required this.creatoIl,
    required this.versioneProgramma,
    required this.archivio,
    required this.chiave,
  });

  final Uint8List seme;
  final String indirizzo;
  final DateTime creatoIl;
  final String versioneProgramma;

  /// Istantanea SQLite dell'archivio.
  final Uint8List archivio;

  /// Chiave con cui il backup era cifrato.
  final ChiaveBackup chiave;
}

/// Crea il file di backup: identità e istantanea coerente dell'archivio.
Future<Uint8List> creaBackup({
  required Archivio archivio,
  required Identita identita,
  required ChiaveBackup chiave,
  required String versioneProgramma,
  required DateTime ora,
}) async {
  final cartella = await Directory.systemTemp.createTemp('opencoach_backup_');
  final Uint8List istantanea;
  try {
    final percorso = p.join(cartella.path, 'archivio.db');
    archivio.db.execute('VACUUM INTO ?', [percorso]);
    istantanea = await File(percorso).readAsBytes();
  } finally {
    await cartella.delete(recursive: true);
  }

  final intestazione = utf8.encode(
    jsonEncode({
      'indirizzo': identita.indirizzo,
      'seme': base64.encode(identita.seme),
      'creato_il': formattaDataOra(ora),
      'versione_programma': versioneProgramma,
    }),
  );
  final chiaro = BytesBuilder(copy: false)
    ..add(_uint32(intestazione.length))
    ..add(intestazione)
    ..add(istantanea);
  final cifrato = await cifra(chiave.chiave, chiaro.takeBytes());
  final parametri = chiave.parametri;
  return (BytesBuilder(copy: false)
        ..add(ascii.encode(_magia))
        ..addByte(_versioneFormato)
        ..add(_uint32(parametri.memoria))
        ..add(_uint32(parametri.iterazioni))
        ..addByte(parametri.parallelismo)
        ..add(chiave.sale)
        ..add(cifrato))
      .takeBytes();
}

/// Decifra un backup. Lancia [BackupNonValido] o [PassphraseErrata].
Future<ContenutoBackup> leggiBackup(List<int> file, String passphrase) async {
  const testa = 8 + 1 + 4 + 4 + 1 + _lunghezzaSale;
  if (file.length < testa || ascii.decode(file.sublist(0, 8), allowInvalid: true) != _magia) {
    throw const BackupNonValido('Il file non è un backup di Open Coach');
  }
  if (file[8] != _versioneFormato) {
    throw const BackupNonValido('Backup creato da una versione più recente del programma');
  }
  final dati = ByteData.sublistView(Uint8List.fromList(file));
  final parametri = ParametriArgon2(
    memoria: dati.getUint32(9),
    iterazioni: dati.getUint32(13),
    parallelismo: file[17],
  );
  // Limiti di buon senso: un file alterato non deve far usare memoria a
  // piacere.
  if (parametri.memoria > 1024 * 1024 ||
      parametri.iterazioni > 100 ||
      parametri.parallelismo < 1 ||
      parametri.parallelismo > 16) {
    throw const BackupNonValido('Parametri del backup non validi');
  }
  final chiave = await ChiaveBackup.deriva(
    passphrase,
    sale: file.sublist(18, testa),
    parametri: parametri,
  );
  final Uint8List chiaro;
  try {
    chiaro = await decifra(chiave.chiave, file.sublist(testa));
  } on SecretBoxAuthenticationError {
    throw const PassphraseErrata();
  }

  try {
    final lunghezza = ByteData.sublistView(chiaro).getUint32(0);
    final intestazione =
        jsonDecode(utf8.decode(chiaro.sublist(4, 4 + lunghezza))) as Map<String, Object?>;
    return ContenutoBackup(
      seme: base64.decode(intestazione['seme'] as String),
      indirizzo: intestazione['indirizzo'] as String,
      creatoIl: analizzaDataOra(intestazione['creato_il'])!,
      versioneProgramma: intestazione['versione_programma'] as String,
      archivio: Uint8List.sublistView(chiaro, 4 + lunghezza),
      chiave: chiave,
    );
  } on Object {
    throw const BackupNonValido('Contenuto del backup danneggiato');
  }
}

/// Esito di [ripristinaBackup], per gli avvisi dell'interfaccia.
class EsitoRipristino {
  const EsitoRipristino(this.indirizzo, this.creatoIl);

  /// Indirizzo onion ripristinato: lo stesso di prima, così gli atleti non
  /// devono riabbinarsi. L'installazione da cui viene il backup non deve
  /// più essere avviata.
  final String indirizzo;

  /// Momento in cui era stato creato il backup.
  final DateTime creatoIl;
}

/// Ripristina [file] in [cartellaDati], sostituendo l'archivio che c'è.
/// Il programma non deve essere in esecuzione su quella cartella.
///
/// L'identità viene cifrata con la chiave locale di questo [portachiavi] e
/// l'epoca cambia, così i telefoni si riallineano e reinviano i log arrivati
/// dopo il backup (§7.3). La chiave del backup resta nel portachiavi per i
/// backup automatici successivi.
Future<EsitoRipristino> ripristinaBackup({
  required String file,
  required String passphrase,
  required String cartellaDati,
  required Portachiavi portachiavi,
  DateTime Function() adesso = DateTime.now,
}) async {
  final contenuto = await leggiBackup(await File(file).readAsBytes(), passphrase);
  final identita = await Identita.daSeme(contenuto.seme);
  if (identita.indirizzo != contenuto.indirizzo) {
    throw const BackupNonValido('Identità del backup danneggiata');
  }

  await Directory(cartellaDati).create(recursive: true);
  final blocco = await File(p.join(cartellaDati, 'blocco')).open(mode: FileMode.write);
  try {
    try {
      await blocco.lock(FileLock.exclusive);
    } on FileSystemException {
      throw const ProgrammaGiaAvviato();
    }
    final percorso = p.join(cartellaDati, 'archivio.db');
    for (final suffisso in ['', '-wal', '-shm']) {
      final vecchio = File('$percorso$suffisso');
      if (await vecchio.exists()) await vecchio.delete();
    }
    await File(percorso).writeAsBytes(contenuto.archivio, flush: true);

    final semeCifrato = await cifraSeme(portachiavi, identita);
    await portachiavi.scrivi(_voceChiaveBackup, contenuto.chiave.serializza());
    final archivio = Archivio.apri(percorso);
    try {
      archivio.transazione(() {
        scriviIdentita(archivio, identita.indirizzo, semeCifrato, adesso());
        archivio.rigeneraEpoca();
        archivio.scriviImpostazione(
          Impostazioni.ultimoBackup,
          istante(contenuto.creatoIl),
        );
      });
    } finally {
      archivio.chiudi();
    }
    return EsitoRipristino(identita.indirizzo, contenuto.creatoIl);
  } finally {
    await blocco.close();
  }
}

/// Backup del programma in esecuzione: configurazione, backup manuali e
/// automatici con rotazione (§9.4).
class GestioneBackup {
  GestioneBackup({
    required Archivio archivio,
    required Identita Function() identita,
    required Portachiavi portachiavi,
    required String versioneProgramma,
    DateTime Function()? adesso,
    this.parametri = const ParametriArgon2(),
  }) : _archivio = archivio,
       _identita = identita,
       _portachiavi = portachiavi,
       _versioneProgramma = versioneProgramma,
       _adesso = adesso ?? DateTime.now;

  final Archivio _archivio;
  final Identita Function() _identita;
  final Portachiavi _portachiavi;
  final String _versioneProgramma;
  final DateTime Function() _adesso;

  /// Parametri per le nuove passphrase.
  final ParametriArgon2 parametri;

  /// Cartella dei backup automatici, se configurata.
  String? get cartella => _archivio.impostazione(Impostazioni.cartellaBackup);

  Duration get intervallo => Duration(
    days: int.tryParse(_archivio.impostazione(Impostazioni.giorniTraBackup) ?? '') ?? 7,
  );

  DateTime? get ultimoBackup =>
      leggiIstanteFacoltativo(_archivio.impostazione(Impostazioni.ultimoBackup));

  /// Vero se non c'è un backup degli ultimi 30 giorni.
  bool get serveUnBackup {
    final ultimo = ultimoBackup;
    return ultimo == null || _adesso().difference(ultimo) > etaPromemoriaBackup;
  }

  /// Vero se la passphrase dei backup automatici è nel portachiavi.
  Future<bool> configurato() async =>
      cartella != null &&
      ChiaveBackup.leggi(await _portachiavi.leggi(_voceChiaveBackup)) != null;

  /// Imposta passphrase, cartella e frequenza dei backup automatici. La
  /// chiave derivata resta nel portachiavi, così i backup successivi non
  /// chiedono la passphrase.
  Future<void> configura({
    required String passphrase,
    required String cartella,
    Duration intervallo = const Duration(days: 7),
  }) async {
    if (passphrase.length < 8) {
      throw const OperazioneNonValida('La passphrase deve avere almeno 8 caratteri');
    }
    if (intervallo.inDays < 1 || intervallo.inDays > 90) {
      throw const OperazioneNonValida('I backup automatici vanno fatti da ogni giorno a ogni 90 giorni');
    }
    final chiave = await ChiaveBackup.deriva(passphrase, parametri: parametri);
    await _portachiavi.scrivi(_voceChiaveBackup, chiave.serializza());
    _archivio.scriviImpostazione(Impostazioni.cartellaBackup, cartella);
    _archivio.scriviImpostazione(Impostazioni.giorniTraBackup, '${intervallo.inDays}');
  }

  /// Backup nella cartella configurata; conserva gli ultimi
  /// [backupDaConservare].
  Future<File> esegui() async {
    final cartella = this.cartella;
    final chiave = ChiaveBackup.leggi(await _portachiavi.leggi(_voceChiaveBackup));
    if (cartella == null || chiave == null) {
      throw const OperazioneNonValida('I backup automatici non sono configurati');
    }
    await Directory(cartella).create(recursive: true);
    final ora = _adesso();
    final file = File(p.join(cartella, 'opencoach-${_marca(ora)}$_estensione'));
    await _scrivi(file, chiave, ora);
    await _ruota(cartella);
    return file;
  }

  /// Backup automatico, se è passato l'intervallo dall'ultimo. Restituisce il
  /// file creato oppure null.
  Future<File?> eseguiSeDovuto() async {
    if (!await configurato()) return null;
    final ultimo = ultimoBackup;
    if (ultimo != null && _adesso().difference(ultimo) < intervallo) return null;
    return esegui();
  }

  /// Backup manuale in [percorso]. Con [passphrase] usa quella, altrimenti
  /// la chiave dei backup automatici.
  Future<File> salvaIn(String percorso, {String? passphrase}) async {
    final chiave = passphrase != null
        ? await ChiaveBackup.deriva(passphrase, parametri: parametri)
        : ChiaveBackup.leggi(await _portachiavi.leggi(_voceChiaveBackup));
    if (chiave == null) {
      throw const OperazioneNonValida('Serve una passphrase per il backup');
    }
    final file = File(percorso);
    await _scrivi(file, chiave, _adesso());
    return file;
  }

  Future<void> _scrivi(File file, ChiaveBackup chiave, DateTime ora) async {
    final contenuto = await creaBackup(
      archivio: _archivio,
      identita: _identita(),
      chiave: chiave,
      versioneProgramma: _versioneProgramma,
      ora: ora,
    );
    // Scrive accanto e poi rinomina: un backup interrotto non sostituisce
    // mai uno buono.
    final temporaneo = File('${file.path}.parziale');
    await temporaneo.writeAsBytes(contenuto, flush: true);
    await temporaneo.rename(file.path);
    _archivio.scriviImpostazione(Impostazioni.ultimoBackup, istante(ora));
  }

  Future<void> _ruota(String cartella) async {
    final backup = await Directory(cartella)
        .list()
        .where((e) => e is File && RegExp(r'opencoach-\d{8}-\d{6}\.ocbackup$').hasMatch(e.path))
        .map((e) => e.path)
        .toList();
    if (backup.length <= backupDaConservare) return;
    backup.sort();
    for (final vecchio in backup.take(backup.length - backupDaConservare)) {
      await File(vecchio).delete();
    }
  }

  String _marca(DateTime ora) {
    final t = ora.toLocal();
    String due(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${due(t.month)}${due(t.day)}-'
        '${due(t.hour)}${due(t.minute)}${due(t.second)}';
  }
}

Uint8List _uint32(int valore) =>
    (ByteData(4)..setUint32(0, valore)).buffer.asUint8List();
