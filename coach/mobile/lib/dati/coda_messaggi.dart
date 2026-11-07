import 'dart:async';
import 'dart:convert';

import 'package:protocollo/protocollo.dart';

import 'cassaforte.dart';
import 'fonte_dati.dart';
import 'modelli.dart';

const _voce = 'coda_messaggi';

class MessaggioInCoda {
  const MessaggioInCoda({
    required this.id,
    required this.atletaId,
    required this.testo,
    required this.scrittoIl,
    this.rifiutato = false,
  });

  final String id;
  final String atletaId;
  final String testo;
  final DateTime scrittoIl;

  /// Il PC non lo vuole: non si ritenta, e il coach decide cosa farne.
  final bool rifiutato;

  MessaggioChat comeMessaggio() => MessaggioChat(
    id: id,
    dalCoach: true,
    testo: testo,
    inviatoIl: scrittoIl,
    statoInvio: rifiutato ? StatoInvio.rifiutato : StatoInvio.inAttesa,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'atleta_id': atletaId,
    'testo': testo,
    'scritto_il': formattaDataOra(scrittoIl),
    'rifiutato': rifiutato,
  };

  static MessaggioInCoda? daJson(Object? json) {
    if (json case {
      'id': final String id,
      'atleta_id': final String atletaId,
      'testo': final String testo,
      'scritto_il': final String scrittoIl,
    }) {
      return MessaggioInCoda(
        id: id,
        atletaId: atletaId,
        testo: testo,
        scrittoIl: analizzaDataOra(scrittoIl) ?? DateTime.now(),
        rifiutato: (json as Map)['rifiutato'] == true,
      );
    }
    return null;
  }
}

/// I messaggi scritti dal telefono e non ancora arrivati al PC (§16.4). Stanno
/// nella cassaforte e ripartono con lo stesso id: il PC non li duplica.
class CodaMessaggi {
  CodaMessaggi(this._cassaforte);

  final Cassaforte _cassaforte;
  final _messaggi = <MessaggioInCoda>[];
  Future<void>? _invio;

  List<MessaggioInCoda> perAtleta(String atletaId) => [
    for (final m in _messaggi)
      if (m.atletaId == atletaId) m,
  ];

  List<MessaggioInCoda> get tutti => List.unmodifiable(_messaggi);

  bool get vuota => _messaggi.isEmpty;

  Future<void> carica() async {
    final salvati = await leggiJson(_cassaforte, _voce);
    _messaggi.clear();
    if (salvati is List<Object?>) {
      for (final s in salvati) {
        if (MessaggioInCoda.daJson(s) case final messaggio?) _messaggi.add(messaggio);
      }
    }
  }

  Future<void> aggiungi(MessaggioInCoda messaggio) async {
    _messaggi.add(messaggio);
    await _salva();
  }

  Future<void> togli(String id) async {
    _messaggi.removeWhere((m) => m.id == id);
    await _salva();
  }

  /// Un solo invio alla volta, in ordine. Lancia [ErroreCoach] e lascia in coda
  /// quel che resta se il PC non risponde.
  Future<void> svuota(FonteDatiCoach fonte) =>
      _invio ??= _svuota(fonte).whenComplete(() => _invio = null);

  Future<void> _svuota(FonteDatiCoach fonte) async {
    while (true) {
      final prossimo = _messaggi.where((m) => !m.rifiutato).firstOrNull;
      if (prossimo == null) return;
      try {
        await fonte.inviaMessaggio(prossimo.atletaId, prossimo.id, prossimo.testo);
        _messaggi.removeWhere((m) => m.id == prossimo.id);
      } on ErroreCoach catch (e) {
        if (e.problema != ProblemaCoach.rifiutata) rethrow;
        final i = _messaggi.indexWhere((m) => m.id == prossimo.id);
        if (i >= 0) {
          _messaggi[i] = MessaggioInCoda(
            id: prossimo.id,
            atletaId: prossimo.atletaId,
            testo: prossimo.testo,
            scrittoIl: prossimo.scrittoIl,
            rifiutato: true,
          );
        }
      }
      await _salva();
    }
  }

  Future<void> cancellaTutto() async {
    _messaggi.clear();
    await _cassaforte.elimina(_voce);
  }

  Future<void> _salva() => _messaggi.isEmpty
      ? _cassaforte.elimina(_voce)
      : _cassaforte.scrivi(_voce, jsonEncode([for (final m in _messaggi) m.toJson()]));
}
