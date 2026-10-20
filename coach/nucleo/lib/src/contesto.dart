import 'dart:async';

import 'archivio.dart';
import 'eventi.dart';

/// Ciò che condividono le parti del nucleo: archivio, orologio, eventi.
class ContestoCoach {
  ContestoCoach({
    required this.archivio,
    required this.indirizzo,
    required this.versioneProgramma,
    DateTime Function()? adesso,
  }) : adesso = adesso ?? DateTime.now;

  final Archivio archivio;

  /// Indirizzo onion del coach, senza ".onion". Cambia solo quando il coach
  /// reimposta l'identità.
  String indirizzo;
  final String versioneProgramma;
  final DateTime Function() adesso;

  final _eventi = StreamController<EventoCoach>.broadcast();
  final _chiavi = StreamController<void>.broadcast();

  /// Nome mostrato agli atleti; vuoto finché il coach non lo sceglie.
  String get nomeCoach => archivio.impostazione(Impostazioni.nomeCoach) ?? '';

  /// Versione minima dell'app che può sincronizzare (§6.4, codice 426).
  String get versioneAppMinima =>
      archivio.impostazione(Impostazioni.versioneAppMinima) ?? '1.0.0';

  Stream<EventoCoach> get eventi => _eventi.stream;

  /// Segnala ogni cambiamento delle chiavi autorizzate: il servizio onion va
  /// ripubblicato (§9.2).
  Stream<void> get chiaviCambiate => _chiavi.stream;

  void emetti(EventoCoach evento) => _eventi.add(evento);

  void segnalaChiaviCambiate() => _chiavi.add(null);

  Future<void> chiudi() async {
    await _eventi.close();
    await _chiavi.close();
  }
}
