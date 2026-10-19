import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'modelli.dart';
import 'schede.dart';

/// Allenamenti registrati dagli atleti, in sola lettura (§9.3).
class GestioneAllenamenti {
  GestioneAllenamenti(this._c, this._schede);

  final ContestoCoach _c;
  final GestioneSchede _schede;

  Database get _db => _c.archivio.db;

  static const _selezione =
      'SELECT log.*, schede.revisione AS revisione_attuale FROM log '
      'LEFT JOIN schede ON schede.id = json_extract(log.contenuto, '
      r"'$.scheda_id') AND schede.atleta_id = log.atleta_id "
      "AND schede.stato != 'eliminata' ";

  /// Allenamenti dell'atleta, dal più recente. Gli eliminati non compaiono.
  List<Allenamento> elenco(String atletaId) => [
    for (final riga in _db.select(
      '$_selezione WHERE log.atleta_id = ? AND log.eliminato = 0 '
      'ORDER BY log.eseguito_il DESC',
      [atletaId],
    ))
      Allenamento.daRiga(
        riga,
        revisioneAttuale: riga['revisione_attuale'] as int?,
      ),
  ];

  Allenamento? cerca(String logId) {
    final riga = _db.select(
      '$_selezione WHERE log.id = ? AND log.eliminato = 0',
      [logId],
    ).firstOrNull;
    return riga == null
        ? null
        : Allenamento.daRiga(
            riga,
            revisioneAttuale: riga['revisione_attuale'] as int?,
          );
  }

  /// Seduta prescritta nella revisione che l'atleta seguiva, se la scheda
  /// esiste ancora.
  Map<String, Object?>? sedutaPrescritta(Allenamento allenamento) {
    final schedaId = allenamento.contenuto['scheda_id'];
    final revisione = allenamento.contenuto['scheda_revisione'];
    final sedutaId = allenamento.contenuto['seduta_id'];
    if (schedaId is! String || revisione is! int || sedutaId is! String) {
      return null;
    }
    final contenuto = _schede.contenutoRevisione(schedaId, revisione);
    final sedute = contenuto?['sedute'];
    if (sedute is! List<Object?>) return null;
    for (final seduta in sedute) {
      if (seduta is Map<String, Object?> && seduta['id'] == sedutaId) {
        return seduta;
      }
    }
    return null;
  }
}
