import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'archivio.dart';
import 'cassaforte.dart';
import 'modelli.dart';
import 'orologio.dart';
import 'trasporto.dart';

/// Ciò che condividono le parti del nucleo dell'app: archivio, cassaforte,
/// Tor, orologio e avvisi di cambiamento.
class ContestoAtleta {
  ContestoAtleta({
    required this.archivio,
    required this.cassaforte,
    required this.tor,
    required this.rete,
    required this.orologio,
    required this.dispositivo,
    required this.registra,
  });

  final ArchivioAtleta archivio;
  final Cassaforte cassaforte;
  final TrasportoTor tor;
  final Connettivita rete;
  final Orologio orologio;

  /// Nome del telefono, piattaforma e versione dell'app, inviati al coach.
  final DatiDispositivo dispositivo;

  /// Log tecnico locale: mai token, chiavi o contenuto di schede e log
  /// (§11.2).
  final void Function(String) registra;

  final _cambiamenti = StreamController<int>.broadcast();

  /// Indirizzi per cui in questa esecuzione Tor ha già la chiave del
  /// dispositivo.
  final _chiaviImpostate = <String>{};

  /// Indirizzi per cui Tor sta usando la chiave d'invito: le sync con lo
  /// stesso coach non la toccano finché l'abbinamento non finisce.
  final _inAbbinamento = <String>{};

  Database get db => archivio.db;

  String get versioneApp => dispositivo.versioneApp;

  /// Id dei coach i cui dati o il cui stato sono cambiati.
  Stream<int> get cambiamenti => _cambiamenti.stream;

  void segnala(int coachId) {
    if (!_cambiamenti.isClosed) _cambiamenti.add(coachId);
  }

  CoachCollegato? coach(int id) {
    final riga = db.select('$selezioneCoach WHERE coach.id = ?', [
      id,
    ]).firstOrNull;
    return riga == null ? null : CoachCollegato.daRiga(riga);
  }

  List<CoachCollegato> coachAttivi() => [
    for (final riga in db.select(
      "$selezioneCoach WHERE coach.stato = 'attivo' ORDER BY coach.id",
    ))
      CoachCollegato.daRiga(riga),
  ];

  static String _voce(int coachId) => 'coach.$coachId';

  Future<Credenziali?> credenziali(int coachId) async {
    final byte = await cassaforte.leggi(_voce(coachId));
    return byte == null ? null : Credenziali.decodifica(byte);
  }

  Future<void> salvaCredenziali(int coachId, Credenziali credenziali) =>
      cassaforte.scrivi(_voce(coachId), credenziali.codifica());

  Future<void> eliminaCredenziali(int coachId) =>
      cassaforte.elimina(_voce(coachId));

  /// Imposta in Tor la chiave del dispositivo per [indirizzo], se in questa
  /// esecuzione non l'ha già fatto e se non è in corso un abbinamento con lo
  /// stesso coach.
  Future<void> assicuraChiave(String indirizzo, Uint8List chiave) async {
    if (!_chiaviImpostate.contains(indirizzo) &&
        !_inAbbinamento.contains(indirizzo)) {
      await impostaChiave(indirizzo, chiave);
    }
  }

  Future<void> impostaChiave(String indirizzo, Uint8List chiave) async {
    await tor.impostaChiave(indirizzo, chiave);
    _chiaviImpostate.add(indirizzo);
    _inAbbinamento.remove(indirizzo);
  }

  /// Passa alla chiave d'invito per [indirizzo], per le chiamate
  /// dell'abbinamento (§5.3, punto 3).
  Future<void> usaChiaveInvito(String indirizzo, Uint8List chiave) async {
    _inAbbinamento.add(indirizzo);
    _chiaviImpostate.remove(indirizzo);
    await tor.impostaChiave(indirizzo, chiave);
  }

  /// Toglie la chiave d'invito. Se c'è già un collegamento con lo stesso
  /// coach, la sua sync successiva rimette la chiave del dispositivo.
  Future<void> lasciaChiaveInvito(String indirizzo) async {
    _inAbbinamento.remove(indirizzo);
    _chiaviImpostate.remove(indirizzo);
    await tor.rimuoviChiave(indirizzo);
  }

  /// Toglie da Tor la chiave per [indirizzo], se nessun collegamento attivo
  /// la usa più e non è in corso un abbinamento con lo stesso coach.
  Future<void> rimuoviChiaveSeInutile(String indirizzo) async {
    if (_inAbbinamento.contains(indirizzo) ||
        coachAttivi().any((coach) => coach.indirizzo == indirizzo)) {
      return;
    }
    _chiaviImpostate.remove(indirizzo);
    await tor.rimuoviChiave(indirizzo);
  }

  Future<void> chiudi() => _cambiamenti.close();
}

/// Chiave privata del dispositivo e token per un coach (§4). Stanno nella
/// cassaforte del telefono, mai nell'archivio.
class Credenziali {
  const Credenziali({
    required this.dispositivoId,
    required this.chiave,
    required this.token,
  });

  final String dispositivoId;

  /// Chiave privata X25519 di client authorization.
  final Uint8List chiave;

  /// Token del dispositivo, in base32.
  final String token;

  List<int> codifica() => utf8.encode(
    jsonEncode({
      'dispositivo_id': dispositivoId,
      'chiave': codificaBase32(chiave),
      'token': token,
    }),
  );

  /// Null se [byte] non contiene credenziali valide.
  static Credenziali? decodifica(List<int> byte) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(byte));
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    final dispositivoId = json['dispositivo_id'];
    final chiave = json['chiave'];
    final token = json['token'];
    if (dispositivoId is! String || chiave is! String || token is! String) {
      return null;
    }
    final privata = decodificaChiave32(chiave);
    if (privata == null || decodificaChiave32(token) == null) return null;
    return Credenziali(
      dispositivoId: dispositivoId,
      chiave: privata,
      token: token,
    );
  }
}
