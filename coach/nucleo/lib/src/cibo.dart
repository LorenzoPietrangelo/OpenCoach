import 'dart:convert';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'errori.dart';
import 'tempo.dart';

/// Il diario del cibo degli atleti, in sola lettura, e l'obiettivo di
/// calorie e macronutrienti che il coach fissa per ciascuno (§8.8).
class GestioneCibo {
  GestioneCibo(this._c);

  final ContestoCoach _c;

  Database get _db => _c.archivio.db;

  /// Le giornate che l'atleta condivide, dal giorno più vecchio. Se per
  /// errore due giornate hanno lo stesso giorno vale l'ultima ricevuta.
  List<GiornataCibo> elenco(String atletaId) {
    final perGiorno = <String, GiornataCibo>{};
    for (final riga in _db.select(
      'SELECT giorno, contenuto FROM giornate WHERE atleta_id = ? AND eliminato = 0 '
      'ORDER BY giorno, ricevuto_il',
      [atletaId],
    )) {
      final giornata = jsonDecode(riga['contenuto'] as String) as Map<String, Object?>;
      perGiorno[riga['giorno'] as String] = GiornataCibo.fromJson(giornata);
    }
    return perGiorno.values.toList();
  }

  /// L'obiettivo dell'atleta, o null se il coach non l'ha fissato.
  ObiettivoCibo? obiettivo(String atletaId) {
    final contenuto = _db.select('SELECT contenuto FROM obiettivi_cibo WHERE atleta_id = ?', [
      atletaId,
    ]).firstOrNull?['contenuto'];
    return contenuto is String
        ? ObiettivoCibo.fromJson(jsonDecode(contenuto) as Map<String, Object?>)
        : null;
  }

  /// Fissa, cambia o, con null, toglie l'obiettivo: l'atleta lo riceve alla
  /// sync successiva. Lancia [OperazioneNonValida] se i valori sono fuori dagli
  /// intervalli del protocollo o l'atleta non esiste.
  void fissaObiettivo(String atletaId, ObiettivoCibo? obiettivo) {
    if (obiettivo != null && validaObiettivoCibo(obiettivo.toJson()).isNotEmpty) {
      throw const OperazioneNonValida(
        'Le calorie vanno da ${LimitiCibo.kcalObiettivoMinime} a ${LimitiCibo.kcalObiettivoMassime}, '
        'i grammi da 0 a ${LimitiCibo.grammiObiettivoMassimi}',
      );
    }
    _c.archivio.transazione(() {
      if (_db.select('SELECT 1 FROM atleti WHERE id = ?', [atletaId]).isEmpty) {
        throw const OperazioneNonValida('Atleta inesistente');
      }
      final esistente = _db.select('SELECT contenuto FROM obiettivi_cibo WHERE atleta_id = ?', [
        atletaId,
      ]).firstOrNull;
      final contenuto = obiettivo == null ? null : jsonEncode(obiettivo.toJson());
      // Senza un obiettivo da togliere, o con lo stesso, non c'è niente da
      // mandare all'atleta.
      if (esistente == null ? obiettivo == null : esistente['contenuto'] == contenuto) return;
      _db.execute(
        'INSERT INTO obiettivi_cibo (atleta_id, contenuto, modificato_il, sequenza) '
        'VALUES (?, ?, ?, ?) ON CONFLICT (atleta_id) DO UPDATE SET '
        'contenuto = excluded.contenuto, modificato_il = excluded.modificato_il, '
        'sequenza = excluded.sequenza',
        [atletaId, contenuto, istante(_c.adesso()), _c.archivio.prossimaSequenza()],
      );
    });
  }
}
