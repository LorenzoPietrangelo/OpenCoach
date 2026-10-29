import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'modelli.dart';

/// Pesi corporei che gli atleti condividono con il coach (§8.5), in sola
/// lettura: li scrive l'atleta.
class GestionePesi {
  GestionePesi(this._c);

  final ContestoCoach _c;

  Database get _db => _c.archivio.db;

  /// I pesi dell'atleta, dal giorno più vecchio. Se per errore due pesi hanno
  /// lo stesso giorno vale l'ultimo ricevuto.
  List<PesoDelGiorno> elenco(String atletaId) {
    final perGiorno = <String, double>{};
    for (final riga in _db.select(
      'SELECT giorno, kg FROM pesi WHERE atleta_id = ? AND eliminato = 0 '
      'ORDER BY giorno, ricevuto_il',
      [atletaId],
    )) {
      perGiorno[riga['giorno'] as String] = (riga['kg'] as num).toDouble();
    }
    return [
      for (final MapEntry(key: giorno, value: kg) in perGiorno.entries)
        if (analizzaData(giorno) case final data?) PesoDelGiorno(giorno: data, kg: kg),
    ];
  }
}
