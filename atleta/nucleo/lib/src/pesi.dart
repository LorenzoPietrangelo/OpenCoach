import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'errori.dart';

/// Peso corporeo di un giorno (§8.5).
class PesoDelGiorno {
  const PesoDelGiorno({required this.giorno, required this.kg});

  final DateTime giorno;
  final double kg;
}

/// Il peso dell'atleta, un valore al giorno (§8.5).
///
/// Il peso è dell'atleta, non di un coach: l'atleta sceglie con quali coach
/// condividerlo. Per ogni coach l'app ricorda l'ultima `rev` di ogni peso
/// che il coach ha confermato; gli altri restano in coda per lui.
class RegistroPesi {
  RegistroPesi(this._c, {required void Function(int coachId) cambiato})
    : _cambiato = cambiato;

  final ContestoAtleta _c;
  final void Function(int coachId) _cambiato;

  Database get _db => _c.db;

  /// I pesi registrati, dal giorno più vecchio.
  List<PesoDelGiorno> elenco() => [
    for (final riga in _db.select(
      'SELECT giorno, kg FROM pesi WHERE eliminato = 0 ORDER BY giorno',
    ))
      PesoDelGiorno(
        giorno: analizzaData(riga['giorno'])!,
        kg: (riga['kg'] as num).toDouble(),
      ),
  ];

  PesoDelGiorno? delGiorno(DateTime giorno) {
    final riga = _db.select(
      'SELECT kg FROM pesi WHERE giorno = ? AND eliminato = 0',
      [formattaData(giorno)],
    ).firstOrNull;
    return riga == null
        ? null
        : PesoDelGiorno(giorno: _soloGiorno(giorno), kg: (riga['kg'] as num).toDouble());
  }

  /// Registra il peso del [giorno], o lo corregge se c'era già. Lancia
  /// [OperazioneNonAmmessa] se [kg] è fuori dall'intervallo del protocollo o
  /// se il giorno è nel futuro.
  void salva(DateTime giorno, double kg) {
    if (kg < pesoMinimoKg || kg > pesoMassimoKg) {
      throw const OperazioneNonAmmessa(
        'Il peso deve essere tra $pesoMinimoKg e $pesoMassimoKg kg',
      );
    }
    if (_soloGiorno(giorno).isAfter(_soloGiorno(_c.orologio.adesso()))) {
      throw const OperazioneNonAmmessa('Il giorno è nel futuro');
    }
    _scrivi(giorno, (kg * 100).round() / 100);
  }

  /// Toglie il peso del [giorno]. I coach che l'avevano lo cancellano alla
  /// sync successiva.
  void elimina(DateTime giorno) => _scrivi(giorno, null);

  void _scrivi(DateTime giorno, double? kg) {
    final chiave = formattaData(giorno);
    final ora = formattaDataOra(_c.orologio.adesso());
    _c.archivio.transazione(() {
      final esistente = _db.select('SELECT eliminato FROM pesi WHERE giorno = ?', [
        chiave,
      ]).firstOrNull;
      if (esistente == null) {
        if (kg == null) return;
        _db.execute(
          'INSERT INTO pesi (giorno, id, rev, eliminato, kg, modificato_il) '
          'VALUES (?, ?, 1, 0, ?, ?)',
          [chiave, nuovoUuid(), kg, ora],
        );
      } else {
        if (kg == null && esistente['eliminato'] == 1) return;
        // Lo stesso giorno tiene lo stesso id, anche dopo un'eliminazione:
        // i coach lo trovano con una rev più alta.
        _db.execute(
          'UPDATE pesi SET rev = rev + 1, eliminato = ?, kg = ?, modificato_il = ? '
          'WHERE giorno = ?',
          [kg == null ? 1 : 0, kg, ora, chiave],
        );
      }
    });
    for (final coach in _c.coachAttivi()) {
      if (coach.condividePesi) {
        _c.segnala(coach.id);
        _cambiato(coach.id);
      }
    }
  }

  /// Condivide o smette di condividere il peso con il coach. Smettendo, alla
  /// sync successiva il coach cancella quelli che ha; ricominciando, li
  /// riceve di nuovo tutti.
  void condividi(int coachId, {required bool condividi}) {
    _c.archivio.transazione(() {
      _db.execute('UPDATE coach SET condividi_pesi = ? WHERE id = ?', [
        condividi ? 1 : 0,
        coachId,
      ]);
      _db.execute('DELETE FROM pesi_inviati WHERE coach_id = ?', [coachId]);
    });
    _c.segnala(coachId);
    _cambiato(coachId);
  }

  static DateTime _soloGiorno(DateTime t) => DateTime(t.year, t.month, t.day);
}

/// Pesi da mandare al coach (§8.5): quelli con una `rev` che non ha ancora
/// confermato, tranne le eliminazioni di pesi che non ha mai ricevuto.
List<Map<String, Object?>> pesiInCoda(
  Database db,
  int coachId, {
  int massimo = Limiti.pesiPerRichiesta,
}) => [
    for (final riga in db.select(
      'SELECT pesi.* FROM pesi LEFT JOIN pesi_inviati inviati '
      'ON inviati.coach_id = ? AND inviati.peso_id = pesi.id '
      'WHERE pesi.rev > COALESCE(inviati.rev, 0) '
      'AND NOT (pesi.eliminato = 1 AND inviati.rev IS NULL) '
      'ORDER BY pesi.giorno LIMIT ?',
      [coachId, massimo],
    ))
      riga['eliminato'] == 1
          ? {'id': riga['id'], 'rev': riga['rev'], 'eliminato': true}
          : {
              'id': riga['id'],
              'rev': riga['rev'],
              'eliminato': false,
              'giorno': riga['giorno'],
              'kg': riga['kg'],
              'modificato_il': riga['modificato_il'],
            },
  ];
