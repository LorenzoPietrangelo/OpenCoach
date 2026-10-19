import 'contesto.dart';
import 'modelli.dart';

/// Schede ricevute dai coach, in sola lettura (§8.1, §10.2). Arrivano con la
/// sync; ogni coach ha le sue.
class SchedeRicevute {
  SchedeRicevute(this._c);

  final ContestoAtleta _c;

  /// Schede del coach, dalla più recente; con [archiviate] quelle della
  /// sezione «Archivio».
  List<SchedaRicevuta> elenco(int coachId, {bool archiviate = false}) => [
    for (final riga in _c.db.select(
      'SELECT * FROM schede WHERE coach_id = ? AND archiviata = ? '
      r"ORDER BY json_extract(contenuto, '$.valida_dal') DESC, "
      r"json_extract(contenuto, '$.titolo') COLLATE NOCASE",
      [coachId, archiviate ? 1 : 0],
    ))
      SchedaRicevuta.daRiga(riga),
  ];

  SchedaRicevuta? cerca(int coachId, String schedaId) {
    final riga = _c.db.select(
      'SELECT * FROM schede WHERE coach_id = ? AND id = ?',
      [coachId, schedaId],
    ).firstOrNull;
    return riga == null ? null : SchedaRicevuta.daRiga(riga);
  }

  /// L'atleta ha aperto l'ultima revisione della scheda: l'avviso di
  /// revisione nuova sparisce.
  void segnaVista(int coachId, String schedaId) {
    _c.db.execute(
      'UPDATE schede SET revisione_vista = revisione '
      'WHERE coach_id = ? AND id = ?',
      [coachId, schedaId],
    );
    _c.segnala(coachId);
  }
}
