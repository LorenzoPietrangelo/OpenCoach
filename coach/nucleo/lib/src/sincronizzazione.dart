import 'dart:convert';
import 'dart:math';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'cursore.dart';
import 'errori.dart';
import 'eventi.dart';
import 'modelli.dart';
import 'schede.dart';
import 'tempo.dart';

/// Sincronizzazione lato programma (§7.2): salva i log ricevuti e restituisce
/// le modifiche alle schede, una pagina per volta.
class ServizioSincronizzazione {
  ServizioSincronizzazione(
    this._c,
    this._schede, {
    this.budgetPagina = 1536 * 1024,
  });

  final ContestoCoach _c;
  final GestioneSchede _schede;

  /// Byte di schede e log per risposta, sotto il limite di 2 MiB (§6.2).
  final int budgetPagina;

  static const _righePerQuery = 500;

  Database get _db => _c.archivio.db;

  /// `POST /v1/sync`.
  RispostaSync sincronizza(Dispositivo dispositivo, RichiestaSync richiesta) {
    if (confrontaVersioni(richiesta.versioneApp, _c.versioneAppMinima) < 0) {
      throw const ErroreHttp(426, CodiceErrore.aggiornaApp);
    }
    if (richiesta.log.length > Limiti.logPerRichiesta) {
      throw const ErroreHttp(
        413,
        CodiceErrore.troppoGrande,
        messaggio: 'Troppi log in una richiesta',
      );
    }
    final atletaId = dispositivo.atletaId;
    final eventi = <EventoCoach>[];

    final risposta = _c.archivio.transazione(() {
      final accettati = <LogConfermato>[];
      final rifiutati = <LogRifiutato>[];
      for (final log in richiesta.log) {
        _salvaLog(dispositivo, log, accettati, rifiutati, eventi);
      }

      final epoca = _c.archivio.epoca;
      final cursore = Cursore.analizza(richiesta.cursore);
      final ora = istante(_c.adesso());
      final incrementale =
          cursore is CursoreIncrementale &&
          cursore.epoca == epoca &&
          richiesta.epoca == epoca;
      if (incrementale) {
        _registraConsegna(dispositivo, cursore.sequenza, ora, eventi);
      }
      _db.execute(
        'UPDATE dispositivi SET ultimo_contatto = ?, versione_app = ? '
        'WHERE id = ?',
        [ora, richiesta.versioneApp, dispositivo.id],
      );

      final pagina = switch (cursore) {
        final CursoreCompleto c when c.epoca == epoca => _paginaCompleta(
          atletaId,
          c,
        ),
        final CursoreIncrementale c when incrementale => _paginaIncrementale(
          atletaId,
          epoca,
          c.sequenza,
        ),
        _ => _paginaCompleta(
          atletaId,
          CursoreCompleto(epoca, _c.archivio.sequenzaCorrente, 0, null),
        ),
      };
      return RispostaSync(
        epoca: epoca,
        completo: pagina.completa,
        logAccettati: accettati,
        logRifiutati: rifiutati,
        schede: pagina.schede,
        schedeEliminate: pagina.eliminate,
        log: pagina.log,
        cursore: pagina.cursore.toString(),
        altro: pagina.altro,
      );
    });

    eventi.add(DispositivoSincronizzato(atletaId, dispositivo.id));
    eventi.forEach(_c.emetti);
    return risposta;
  }

  void _salvaLog(
    Dispositivo dispositivo,
    Object? log,
    List<LogConfermato> accettati,
    List<LogRifiutato> rifiutati,
    List<EventoCoach> eventi,
  ) {
    final id = log is Map<String, Object?> && log['id'] is String
        ? log['id'] as String
        : '';
    if (log is! Map<String, Object?> || !uuidValido(id)) {
      rifiutati.add(LogRifiutato(id, RifiutoLog.nonValido));
      return;
    }
    if (dimensioneJson(log) > Limiti.logMassimo) {
      rifiutati.add(LogRifiutato(id, RifiutoLog.troppoGrande));
      return;
    }
    if (validaLog(log).isNotEmpty) {
      rifiutati.add(LogRifiutato(id, RifiutoLog.nonValido));
      return;
    }

    final rev = log['rev'] as int;
    final eliminato = log['eliminato'] as bool;
    final esistente = _db.select('SELECT atleta_id, rev FROM log WHERE id = ?', [
      id,
    ]).firstOrNull;
    if (esistente != null && esistente['atleta_id'] != dispositivo.atletaId) {
      rifiutati.add(LogRifiutato(id, RifiutoLog.altroAtleta));
      return;
    }
    if (esistente != null && (esistente['rev'] as int) >= rev) {
      accettati.add(LogConfermato(id, rev));
      return;
    }

    _db.execute(
      'INSERT INTO log (id, atleta_id, dispositivo_id, rev, eliminato, '
      'contenuto, eseguito_il, ricevuto_il) VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (id) DO UPDATE SET dispositivo_id = excluded.dispositivo_id, '
      'rev = excluded.rev, eliminato = excluded.eliminato, '
      'contenuto = excluded.contenuto, eseguito_il = excluded.eseguito_il, '
      'ricevuto_il = excluded.ricevuto_il',
      [
        id,
        dispositivo.atletaId,
        dispositivo.id,
        rev,
        eliminato ? 1 : 0,
        // Di un log eliminato resta solo la lapide: id, rev, eliminato.
        eliminato ? null : jsonEncode(log),
        eliminato ? null : istante(analizzaDataOra(log['eseguito_il'])!),
        istante(_c.adesso()),
      ],
    );
    accettati.add(LogConfermato(id, rev));
    eventi.add(LogRicevuto(dispositivo.atletaId, id, eliminato: eliminato));
  }

  /// Il dispositivo ha salvato le modifiche fino a [sequenza]: per ogni
  /// scheda, l'ultima revisione entro quella sequenza risulta ricevuta.
  /// Le revisioni sostituite prima di arrivare restano senza data.
  void _registraConsegna(
    Dispositivo dispositivo,
    int sequenza,
    String ora,
    List<EventoCoach> eventi,
  ) {
    final confermata = min(sequenza, _c.archivio.sequenzaCorrente);
    if (confermata > dispositivo.ultimaSequenza) {
      _db.execute('UPDATE dispositivi SET ultima_sequenza = ? WHERE id = ?', [
        confermata,
        dispositivo.id,
      ]);
    }
    final ricevute = _db.select(
      'UPDATE revisioni SET ricevuta_il = ? '
      'WHERE ricevuta_il IS NULL AND sequenza <= ? '
      'AND scheda_id IN (SELECT id FROM schede WHERE atleta_id = ?) '
      'AND revisione = (SELECT MAX(r.revisione) FROM revisioni r '
      'WHERE r.scheda_id = revisioni.scheda_id AND r.sequenza <= ?) '
      'RETURNING scheda_id, revisione',
      [ora, confermata, dispositivo.atletaId, confermata],
    );
    for (final riga in ricevute) {
      eventi.add(
        RevisioneRicevuta(
          dispositivo.atletaId,
          riga['scheda_id'] as String,
          riga['revisione'] as int,
        ),
      );
    }
  }

  /// Schede cambiate dopo [sequenza], in ordine di sequenza.
  _Pagina _paginaIncrementale(String atletaId, String epoca, int sequenza) {
    final pagina = _Pagina(budgetPagina, completa: false);
    var ultima = sequenza;
    final righe = _db.select(
      'SELECT * FROM schede WHERE atleta_id = ? AND sequenza > ? '
      'ORDER BY sequenza LIMIT ?',
      [atletaId, sequenza, _righePerQuery],
    );
    for (final riga in righe) {
      if (riga['stato'] == 'eliminata') {
        pagina.eliminate.add(riga['id'] as String);
      } else if (!pagina.aggiungi(pagina.schede, _schede.perProtocollo(riga))) {
        break;
      }
      ultima = riga['sequenza'] as int;
    }
    if (righe.length == _righePerQuery) pagina.altro = true;
    pagina.cursore = pagina.altro
        ? CursoreIncrementale(epoca, ultima)
        : CursoreIncrementale(epoca, _c.archivio.sequenzaCorrente);
    return pagina;
  }

  /// Stato completo: prima tutte le schede pubblicate e archiviate, poi tutti
  /// i log, compresi gli eliminati (§6.3).
  _Pagina _paginaCompleta(String atletaId, CursoreCompleto da) {
    final pagina = _Pagina(budgetPagina, completa: true);
    var fase = da.fase;
    var dopo = da.dopo;

    if (fase == 0) {
      final righe = _db.select(
        'SELECT * FROM schede WHERE atleta_id = ? '
        "AND stato IN ('pubblicata', 'archiviata') AND id > ? "
        'ORDER BY id LIMIT ?',
        [atletaId, dopo ?? '', _righePerQuery],
      );
      for (final riga in righe) {
        if (!pagina.aggiungi(pagina.schede, _schede.perProtocollo(riga))) break;
        dopo = riga['id'] as String;
      }
      if (righe.length == _righePerQuery) pagina.altro = true;
      if (!pagina.altro) {
        fase = 1;
        dopo = null;
      }
    }

    if (fase == 1 && !pagina.altro) {
      final righe = _db.select(
        'SELECT id, rev, eliminato, contenuto FROM log '
        'WHERE atleta_id = ? AND id > ? ORDER BY id LIMIT ?',
        [atletaId, dopo ?? '', _righePerQuery],
      );
      for (final riga in righe) {
        final voce = riga['eliminato'] == 1
            ? <String, Object?>{
                'id': riga['id'],
                'rev': riga['rev'],
                'eliminato': true,
              }
            : jsonDecode(riga['contenuto'] as String) as Map<String, Object?>;
        if (!pagina.aggiungi(pagina.log, voce)) break;
        dopo = riga['id'] as String;
      }
      if (righe.length == _righePerQuery) pagina.altro = true;
    }

    pagina.cursore = pagina.altro
        ? CursoreCompleto(da.epoca, da.istantanea, fase, dopo)
        : CursoreIncrementale(da.epoca, da.istantanea);
    return pagina;
  }
}

class _Pagina {
  _Pagina(this._budget, {required this.completa});

  final int _budget;
  final bool completa;
  final schede = <Map<String, Object?>>[];
  final eliminate = <String>[];
  final log = <Map<String, Object?>>[];
  late Cursore cursore;
  var altro = false;
  var _usati = 0;

  /// Aggiunge [voce] a [lista] se c'è spazio; altrimenti segna che servono
  /// altre pagine. Una pagina contiene sempre almeno una voce.
  bool aggiungi(List<Map<String, Object?>> lista, Map<String, Object?> voce) {
    final dimensione = dimensioneJson(voce);
    final vuota = schede.isEmpty && log.isEmpty;
    if (!vuota && _usati + dimensione > _budget) {
      altro = true;
      return false;
    }
    lista.add(voce);
    _usati += dimensione;
    return true;
  }
}
