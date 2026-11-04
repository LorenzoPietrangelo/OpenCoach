import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'modelli.dart';
import 'schede.dart';

/// Una settimana dello storico, che parte dal [lunedi].
class SettimanaStorico {
  const SettimanaStorico(this.lunedi, {required this.allenamenti});

  final DateTime lunedi;
  final int allenamenti;
}

/// Cosa si misura di un esercizio: il massimale stimato se ci sono carichi e
/// ripetizioni; altrimenti il carico, la durata o le ripetizioni.
enum MisuraEsercizio { stima1Rm, carico, ripetizioni, durata }

/// Il massimale stimato di una serie con la formula di Epley. Le ripetizioni
/// rimaste in riserva ([rir]) contano come fatte: 100 kg × 8 con RIR 2 valgono
/// quanto 100 kg × 10 a cedimento. Senza [rir] la serie vale come a cedimento.
double stima1Rm(num chili, num ripetizioni, {num? rir}) {
  final totali = ripetizioni + (rir ?? 0);
  return totali <= 1 ? chili.toDouble() : chili * (1 + totali / 30);
}

final _rirScritto = RegExp(r'^\s*(\d+(?:[.,]\d+)?)(?:\s*[-–]\s*(\d+(?:[.,]\d+)?))?\s*$');

/// Il RIR come lo scrive il coach, che è testo libero: «2» vale 2, «1-2» vale
/// 1,5. Null se non è un numero o un intervallo.
double? rirDaTesto(Object? testo) {
  final trovato = testo is String ? _rirScritto.firstMatch(testo) : null;
  if (trovato == null) return null;
  double numero(String valore) => double.parse(valore.replaceAll(',', '.'));
  final basso = numero(trovato[1]!);
  final alto = trovato[2];
  return alto == null ? basso : (basso + numero(alto)) / 2;
}

/// Un esercizio nel tempo: il valore migliore di ogni allenamento.
class EsercizioStorico {
  const EsercizioStorico({required this.nome, required this.misura, required this.punti});

  final String nome;
  final MisuraEsercizio misura;

  /// Dal più vecchio.
  final List<({DateTime giorno, double valore})> punti;
}

class StoricoAtleta {
  const StoricoAtleta({
    required this.settimane,
    required this.esercizi,
    required this.totale,
    required this.ultimo,
  });

  /// Dalla più vecchia, fino a quella in corso.
  final List<SettimanaStorico> settimane;

  /// Dal più frequente.
  final List<EsercizioStorico> esercizi;

  /// Allenamenti con almeno una serie fatta.
  final int totale;

  /// Il giorno dell'ultimo; null se non ce ne sono.
  final DateTime? ultimo;
}

/// I valori di un esercizio, allenamento per allenamento.
class _Raccolta {
  var nome = '';
  final _righe = <(DateTime, double?, double?, double?, double?)>[];

  void aggiungi(DateTime giorno, double? stima, double? carico, double? ripetizioni, double? durata) {
    if (stima != null || carico != null || ripetizioni != null || durata != null) {
      _righe.add((giorno, stima, carico, ripetizioni, durata));
    }
  }

  EsercizioStorico? risultato() {
    if (_righe.isEmpty) return null;
    final misura = _righe.any((r) => r.$2 != null)
        ? MisuraEsercizio.stima1Rm
        : _righe.any((r) => r.$3 != null)
        ? MisuraEsercizio.carico
        : _righe.any((r) => r.$5 != null)
        ? MisuraEsercizio.durata
        : MisuraEsercizio.ripetizioni;
    return EsercizioStorico(
      nome: nome,
      misura: misura,
      punti: [
        for (final riga in _righe)
          if (switch (misura) {
            MisuraEsercizio.stima1Rm => riga.$2,
            MisuraEsercizio.carico => riga.$3,
            MisuraEsercizio.durata => riga.$5,
            MisuraEsercizio.ripetizioni => riga.$4,
          } case final valore?)
            (giorno: riga.$1, valore: valore),
      ],
    );
  }
}

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

  /// I numeri dello storico dell'atleta, per i grafici: le ultime [settimane]
  /// settimane fino a quella in corso e i progressi di ogni esercizio. Contano
  /// solo le serie fatte: un allenamento senza serie fatte non conta. Con
  /// [schedaId] solo gli allenamenti di quella scheda, con [soloLiberi] solo
  /// quelli senza scheda.
  StoricoAtleta storico(String atletaId, {String? schedaId, bool soloLiberi = false, int settimane = 12}) {
    DateTime soloGiorno(DateTime quando) {
      final locale = quando.toLocal();
      return DateTime(locale.year, locale.month, locale.day);
    }

    DateTime lunediDi(DateTime giorno) => DateTime(giorno.year, giorno.month, giorno.day - (giorno.weekday - 1));

    final questoLunedi = lunediDi(soloGiorno(_c.adesso()));
    final lunedi = [
      for (var i = settimane - 1; i >= 0; i--)
        DateTime(questoLunedi.year, questoLunedi.month, questoLunedi.day - 7 * i),
    ];
    final contati = <DateTime, int>{};
    final perEsercizio = <String, _Raccolta>{};
    var totale = 0;
    DateTime? ultimo;

    for (final allenamento in elenco(atletaId).reversed) {
      final scheda = allenamento.contenuto['scheda_id'];
      if (soloLiberi && scheda != null) continue;
      if (schedaId != null && scheda != schedaId) continue;
      final giorno = soloGiorno(allenamento.eseguitoIl);
      final prescritti = _rirPrescritti(allenamento);
      var fatto = false;
      for (final esercizio in _mappe(allenamento.contenuto['esercizi'])) {
        final nome = esercizio['nome'];
        if (nome is! String || nome.trim().isEmpty) continue;
        final raccolta = perEsercizio.putIfAbsent(nome.trim().toLowerCase(), _Raccolta.new)..nome = nome.trim();
        final rirDelCoach = prescritti[esercizio['esercizio_id']] ?? const <double?>[];
        double? stima;
        double? carico;
        double? ripetizioni;
        double? durata;
        for (final (i, serie) in _mappe(esercizio['serie']).indexed) {
          if (serie['completata'] != true) continue;
          fatto = true;
          final kg = (serie['carico_kg'] as num?)?.toDouble();
          final rip = (serie['ripetizioni'] as num?)?.toDouble();
          final secondi = (serie['durata_s'] as num?)?.toDouble();
          if (kg != null && rip != null && rip > 0) {
            // Lo sforzo scritto dall'atleta nei log vecchi vale più del RIR
            // previsto dal coach. Una serie aggiunta segue l'ultima prevista.
            final rpe = serie['rpe'] as num?;
            final rir = rpe != null
                ? max(0, 10 - rpe)
                : i < rirDelCoach.length
                ? rirDelCoach[i]
                : rirDelCoach.lastOrNull;
            final valore = stima1Rm(kg, rip, rir: rir);
            stima = max(stima ?? valore, valore);
          }
          if (kg != null) carico = max(carico ?? kg, kg);
          if (rip != null) ripetizioni = max(ripetizioni ?? rip, rip);
          if (secondi != null) durata = max(durata ?? secondi, secondi);
        }
        raccolta.aggiungi(giorno, stima, carico, ripetizioni, durata);
      }
      if (!fatto) continue;
      totale++;
      ultimo = giorno;
      final settimana = lunediDi(giorno);
      contati[settimana] = (contati[settimana] ?? 0) + 1;
    }

    final esercizi = [
      for (final raccolta in perEsercizio.values) ?raccolta.risultato(),
    ]..sort((a, b) {
      final frequenza = b.punti.length.compareTo(a.punti.length);
      return frequenza != 0 ? frequenza : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });
    return StoricoAtleta(
      settimane: [
        for (final inizio in lunedi)
          SettimanaStorico(inizio, allenamenti: contati[inizio] ?? 0),
      ],
      esercizi: esercizi,
      totale: totale,
      ultimo: ultimo,
    );
  }

  /// Il RIR previsto per ogni serie di ogni esercizio, per id dell'esercizio,
  /// nella revisione della scheda che l'atleta seguiva.
  Map<Object?, List<double?>> _rirPrescritti(Allenamento allenamento) => {
    for (final esercizio in _mappe(sedutaPrescritta(allenamento)?['esercizi']))
      esercizio['id']: [
        for (final riga in _mappe(esercizio['prescrizione']))
          for (var i = 0; i < ((riga['serie'] as num?)?.toInt() ?? 1); i++) rirDaTesto(riga['rir']),
      ],
  };

  List<Map<String, Object?>> _mappe(Object? lista) =>
      lista is List<Object?> ? lista.whereType<Map<String, Object?>>().toList() : const [];

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
