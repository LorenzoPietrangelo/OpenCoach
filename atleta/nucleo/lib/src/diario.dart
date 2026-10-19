import 'dart:convert';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'errori.dart';
import 'modelli.dart';
import 'tempo.dart';

/// Allenamenti registrati dall'atleta (§8.2, §10.2).
///
/// Ogni log ha la `rev` locale, che cresce a ogni modifica, e l'ultima `rev`
/// confermata dal coach: resta in coda finché la prima supera la seconda,
/// salvo che il coach l'abbia rifiutato (§7.3). Un log appartiene a un solo
/// coach.
class DiarioAllenamenti {
  DiarioAllenamenti(this._c, {required void Function(int coachId) cambiato})
    : _cambiato = cambiato;

  final ContestoAtleta _c;

  /// Avvisa che i log di un coach sono cambiati: in primo piano parte una
  /// sync (§7.4).
  final void Function(int coachId) _cambiato;

  Database get _db => _c.db;

  /// Salva un allenamento eseguito e lo mette in coda per [coachId].
  ///
  /// [contenuto] ha i campi del §8.2 tranne `id`, `rev`, `eliminato` e
  /// `modificato_il`, che aggiunge l'app. Lancia [LogNonValido] se non
  /// rispetta il protocollo e [OperazioneNonAmmessa] se il collegamento con
  /// il coach è chiuso.
  LogAllenamento salva(int coachId, Map<String, Object?> contenuto) {
    final id = nuovoUuid();
    final corpo = _corpoValido(id, 1, contenuto);
    _c.archivio.transazione(() {
      _verificaAttivo(coachId);
      _db.execute(
        'INSERT INTO log (coach_id, id, rev, rev_confermata, eliminato, '
        'contenuto, eseguito_il) VALUES (?, ?, 1, 0, 0, ?, ?)',
        [coachId, id, jsonEncode(corpo), _eseguitoIl(corpo)],
      );
    });
    _dopoModifica(coachId);
    return cerca(coachId, id)!;
  }

  /// Sostituisce il contenuto del log: la `rev` cresce e il log torna in
  /// coda, anche se il coach l'aveva rifiutato.
  LogAllenamento modifica(
    int coachId,
    String id,
    Map<String, Object?> contenuto,
  ) {
    _c.archivio.transazione(() {
      _verificaAttivo(coachId);
      final rev = _revModificabile(coachId, id) + 1;
      final corpo = _corpoValido(id, rev, contenuto);
      _db.execute(
        'UPDATE log SET rev = ?, contenuto = ?, eseguito_il = ?, rifiuto = NULL '
        'WHERE coach_id = ? AND id = ?',
        [rev, jsonEncode(corpo), _eseguitoIl(corpo), coachId, id],
      );
    });
    _dopoModifica(coachId);
    return cerca(coachId, id)!;
  }

  /// Elimina il log. Ne resta la lapide, che arriva al coach con
  /// `eliminato: true` e la `rev` incrementata (§8.2).
  void elimina(int coachId, String id) {
    _c.archivio.transazione(() {
      _verificaAttivo(coachId);
      _revModificabile(coachId, id);
      _db.execute(
        'UPDATE log SET rev = rev + 1, eliminato = 1, contenuto = NULL, '
        'eseguito_il = NULL, rifiuto = NULL WHERE coach_id = ? AND id = ?',
        [coachId, id],
      );
    });
    _dopoModifica(coachId);
  }

  /// Rimette in coda un log rifiutato dal coach, che in automatico non viene
  /// ritentato (§7.3).
  void ritenta(int coachId, String id) {
    _c.archivio.transazione(() {
      _verificaAttivo(coachId);
      _db.execute(
        'UPDATE log SET rifiuto = NULL WHERE coach_id = ? AND id = ?',
        [coachId, id],
      );
    });
    _dopoModifica(coachId);
  }

  /// Il log, anche se eliminato; null se non esiste.
  LogAllenamento? cerca(int coachId, String id) {
    final riga = _db.select('SELECT * FROM log WHERE coach_id = ? AND id = ?', [
      coachId,
      id,
    ]).firstOrNull;
    return riga == null ? null : LogAllenamento.daRiga(riga);
  }

  /// Storico degli allenamenti con il coach, dal più recente. Gli eliminati
  /// non compaiono.
  List<LogAllenamento> elenco(int coachId) => [
    for (final riga in _db.select(
      'SELECT * FROM log WHERE coach_id = ? AND eliminato = 0 '
      'ORDER BY eseguito_il DESC, id',
      [coachId],
    ))
      LogAllenamento.daRiga(riga),
  ];

  /// Log che il coach ha rifiutato, da segnalare all'atleta (§7.3).
  List<LogAllenamento> rifiutati(int coachId) => [
    for (final riga in _db.select(
      'SELECT * FROM log WHERE coach_id = ? AND rifiuto IS NOT NULL '
      'ORDER BY eseguito_il DESC, id',
      [coachId],
    ))
      LogAllenamento.daRiga(riga),
  ];

  /// Numero di log in attesa di invio (§7.5).
  int inAttesa(int coachId) =>
      _db.select(
            'SELECT COUNT(*) AS n FROM log WHERE coach_id = ? '
            'AND $condizioneInCoda',
            [coachId],
          ).first['n']
          as int;

  Map<String, Object?> _corpoValido(
    String id,
    int rev,
    Map<String, Object?> contenuto,
  ) {
    final corpo = corpoDelLog(contenuto)
      ..['modificato_il'] = formattaDataOra(_c.orologio.adesso());
    final log = {'id': id, 'rev': rev, 'eliminato': false, ...corpo};
    final errori = validaLog(log);
    if (errori.isNotEmpty) throw LogNonValido(errori);
    final int dimensione;
    try {
      dimensione = dimensioneJson(log);
    } on JsonUnsupportedObjectError {
      throw const LogNonValido(['log: contiene valori estranei al JSON']);
    }
    if (dimensione > Limiti.logMassimo) {
      throw const LogNonValido(['log: oltre 64 KiB']);
    }
    return corpo;
  }

  String _eseguitoIl(Map<String, Object?> corpo) =>
      istante(analizzaDataOra(corpo['eseguito_il'])!);

  void _verificaAttivo(int coachId) {
    final riga = _db.select('SELECT stato FROM coach WHERE id = ?', [
      coachId,
    ]).firstOrNull;
    if (riga == null) throw const OperazioneNonAmmessa('Coach inesistente');
    if (riga['stato'] != StatoCollegamento.attivo.name) {
      throw const OperazioneNonAmmessa(
        'Il collegamento con questo coach è chiuso: '
        'schede e log sono in sola lettura',
      );
    }
  }

  int _revModificabile(int coachId, String id) {
    final riga = _db.select(
      'SELECT rev, eliminato FROM log WHERE coach_id = ? AND id = ?',
      [coachId, id],
    ).firstOrNull;
    if (riga == null) throw const OperazioneNonAmmessa('Log inesistente');
    if (riga['eliminato'] == 1) {
      throw const OperazioneNonAmmessa('Il log è stato eliminato');
    }
    return riga['rev'] as int;
  }

  void _dopoModifica(int coachId) {
    _c.segnala(coachId);
    _cambiato(coachId);
  }
}
