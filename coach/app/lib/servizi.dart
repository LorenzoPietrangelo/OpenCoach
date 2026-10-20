import 'dart:async';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/foundation.dart';

/// Ciò che l'interfaccia usa del programma del coach. In esecuzione è
/// [CoachInEsecuzione]; nei test un nucleo in memoria.
abstract interface class Coach {
  NucleoCoach get nucleo;

  /// Indirizzo onion, senza ".onion".
  String get indirizzo;

  StatoTor get statoTor;

  Stream<StatoTor> get cambiamentiStatoTor;

  GestioneBackup get backup;

  /// Cartella dati del programma.
  String get cartellaDati;

  Future<void> reimpostaIdentita();

  Future<void> chiudi();
}

/// Il [ProgrammaCoach] avviato da `main`.
class CoachInEsecuzione implements Coach {
  CoachInEsecuzione(this.programma, {required this.torTrovato});

  final ProgrammaCoach programma;

  /// Falso se non c'è un eseguibile tor: il servizio non può partire.
  final bool torTrovato;

  @override
  NucleoCoach get nucleo => programma.nucleo;

  @override
  String get indirizzo => programma.indirizzo;

  @override
  StatoTor get statoTor => torTrovato
      ? programma.statoTor
      : const StatoTor(FaseTor.nonRaggiungibile, motivo: 'Tor non trovato');

  @override
  Stream<StatoTor> get cambiamentiStatoTor => programma.cambiamentiStatoTor;

  @override
  GestioneBackup get backup => programma.backup;

  @override
  String get cartellaDati => programma.cartellaDati;

  @override
  Future<void> reimpostaIdentita() => programma.reimpostaIdentita();

  @override
  Future<void> chiudi() => programma.chiudi();
}

/// Avvisa l'interfaccia che i dati del coach sono cambiati, per un evento
/// del nucleo (un log arrivato, un telefono abbinato) o un'azione del coach.
/// Le schermate leggono il nucleo, che è sincrono, a ogni ricostruzione.
class Aggiornamenti extends ChangeNotifier {
  Aggiornamenti(NucleoCoach nucleo) {
    _iscrizione = nucleo.eventi.listen((_) => notifyListeners());
  }

  late final StreamSubscription<EventoCoach> _iscrizione;

  void segnala() => notifyListeners();

  @override
  void dispose() {
    unawaited(_iscrizione.cancel());
    super.dispose();
  }
}

/// Preferenze dell'interfaccia, salvate nell'archivio del coach.
class Preferenze {
  Preferenze(this._archivio);

  final Archivio _archivio;

  static const _notifiche = 'interfaccia_notifiche';
  static const _sospensione = 'interfaccia_impedisci_sospensione';

  /// Notifiche sul desktop per log, abbinamenti e inviti contestati (§9.3).
  bool get notifiche => _archivio.impostazione(_notifiche) != '0';

  set notifiche(bool attive) =>
      _archivio.scriviImpostazione(_notifiche, attive ? '1' : '0');

  /// «Impedisci la sospensione del PC», disattivata per default (§9.1).
  bool get impedisciSospensione => _archivio.impostazione(_sospensione) == '1';

  set impedisciSospensione(bool attiva) =>
      _archivio.scriviImpostazione(_sospensione, attiva ? '1' : '0');
}
