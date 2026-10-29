import 'package:protocollo/protocollo.dart';

import 'modelli.dart';

/// Allenamento che l'atleta sta eseguendo (§10.2, «Esecuzione»).
///
/// Nasce da una seduta di una scheda, con le serie precompilate dalla
/// prescrizione; oppure vuoto, per un allenamento libero; oppure da un log
/// dello storico, per modificarlo. L'interfaccia cambia esercizi e serie,
/// poi passa [contenuto] a `DiarioAllenamenti.salva` o `modifica`, che lo
/// validano.
class AllenamentoInCorso {
  AllenamentoInCorso._({
    required this.coachId,
    required this.schedaId,
    required this.schedaRevisione,
    required this.sedutaId,
    required this.inizio,
    required this.esercizi,
    this.note = '',
    this.rpe,
    this.durataMin,
  });

  /// La seduta [sedutaId] di [scheda]: un esercizio per ogni esercizio
  /// previsto, con le serie della prescrizione. Lancia [ArgumentError] se la
  /// seduta non è nella scheda.
  factory AllenamentoInCorso.daSeduta(
    SchedaRicevuta scheda,
    String sedutaId, {
    required DateTime inizio,
  }) {
    final seduta = _oggetti(
      scheda.contenuto['sedute'],
    ).where((s) => s['id'] == sedutaId).firstOrNull;
    if (seduta == null) {
      throw ArgumentError.value(sedutaId, 'sedutaId', 'non è nella scheda');
    }
    return AllenamentoInCorso._(
      coachId: scheda.coachId,
      schedaId: scheda.id,
      schedaRevisione: scheda.revisione,
      sedutaId: sedutaId,
      inizio: inizio,
      esercizi: [
        for (final esercizio in _oggetti(seduta['esercizi']))
          EsercizioInCorso._daPrescrizione(esercizio),
      ],
    );
  }

  /// Allenamento libero, senza scheda. Se l'atleta ha più coach sceglie a
  /// chi va con [coachId] (§8.2).
  factory AllenamentoInCorso.libero({required DateTime inizio, int? coachId}) =>
      AllenamentoInCorso._(
        coachId: coachId,
        schedaId: null,
        schedaRevisione: null,
        sedutaId: null,
        inizio: inizio,
        esercizi: [],
      );

  /// Riapre un log dello storico per modificarlo (§10.2): data, durata e
  /// collegamento alla seduta restano quelli del log.
  factory AllenamentoInCorso.daLog(LogAllenamento log) {
    final c = log.contenuto;
    if (c == null) {
      throw ArgumentError.value(log.id, 'log', 'il log è stato eliminato');
    }
    return AllenamentoInCorso._(
      coachId: log.coachId,
      schedaId: _testo(c['scheda_id']),
      schedaRevisione: _intero(c['scheda_revisione']),
      sedutaId: _testo(c['seduta_id']),
      inizio: analizzaDataOra(c['eseguito_il'])!,
      esercizi: [
        for (final esercizio in _oggetti(c['esercizi']))
          EsercizioInCorso._daLog(esercizio),
      ],
      note: _testo(c['note']) ?? '',
      rpe: _numero(c['rpe']),
      durataMin: _intero(c['durata_min']),
    );
  }

  /// Coach a cui va il log: quello della scheda; per un allenamento libero
  /// lo sceglie l'atleta.
  int? coachId;
  final String? schedaId;
  final int? schedaRevisione;
  final String? sedutaId;
  DateTime inizio;
  final List<EsercizioInCorso> esercizi;
  String note;

  /// Sforzo percepito della seduta, da 1 a 10.
  num? rpe;

  /// Durata in minuti; se resta null, [contenuto] la calcola dall'inizio
  /// alla fine.
  int? durataMin;

  bool get libero => schedaId == null;

  /// Aggiunge un esercizio non previsto dalla scheda, con una serie vuota.
  EsercizioInCorso aggiungiEsercizio(String nome) {
    final esercizio = EsercizioInCorso(nome: nome, serie: [SerieInCorso()]);
    esercizi.add(esercizio);
    return esercizio;
  }

  /// Il log da salvare (§8.2), senza `id`, `rev` ed `eliminato`. Con [fine]
  /// la durata, se [durataMin] è null, va dall'inizio a quell'istante.
  Map<String, Object?> contenuto({DateTime? fine}) {
    final durata =
        durataMin ??
        (fine == null
            ? null
            : (fine.difference(inizio).inSeconds / 60).round().clamp(0, 1440));
    return {
      'scheda_id': schedaId,
      'scheda_revisione': schedaRevisione,
      'seduta_id': sedutaId,
      'eseguito_il': formattaDataOra(inizio),
      'durata_min': ?durata,
      'rpe': ?rpe,
      'note': note,
      'esercizi': [for (final esercizio in esercizi) esercizio._perLog()],
    };
  }
}

/// Esercizio di un allenamento in corso.
class EsercizioInCorso {
  EsercizioInCorso({
    this.esercizioId,
    required this.nome,
    this.note = '',
    this.noteCoach = '',
    List<SerieInCorso>? serie,
  }) : serie = serie ?? [];

  factory EsercizioInCorso._daPrescrizione(Map<String, Object?> esercizio) {
    final serie = [
      for (final riga in _oggetti(esercizio['prescrizione']))
        for (var i = 0; i < (_intero(riga['serie']) ?? 1); i++)
          SerieInCorso._daPrescrizione(riga),
    ];
    return EsercizioInCorso(
      esercizioId: _testo(esercizio['id']),
      nome: _testo(esercizio['nome']) ?? '',
      noteCoach: _testo(esercizio['note']) ?? '',
      serie: serie.isEmpty ? [SerieInCorso()] : serie,
    );
  }

  factory EsercizioInCorso._daLog(Map<String, Object?> esercizio) =>
      EsercizioInCorso(
        esercizioId: _testo(esercizio['esercizio_id']),
        nome: _testo(esercizio['nome']) ?? '',
        note: _testo(esercizio['note']) ?? '',
        serie: [
          for (final serie in _oggetti(esercizio['serie']))
            SerieInCorso(
              ripetizioni: _intero(serie['ripetizioni']),
              caricoKg: _numero(serie['carico_kg']),
              durataS: _intero(serie['durata_s']),
              rpe: _numero(serie['rpe']),
              completata: serie['completata'] == true,
            ),
        ],
      );

  /// Id dell'esercizio nella scheda; null se l'ha aggiunto l'atleta.
  final String? esercizioId;

  /// Il log copia il nome, così resta leggibile anche se la scheda cambia o
  /// viene eliminata (§8.2).
  String nome;

  /// Note dell'atleta.
  String note;

  /// Note del coach nella scheda, da mostrare durante l'esecuzione.
  final String noteCoach;
  final List<SerieInCorso> serie;

  bool get previsto => esercizioId != null;

  /// Aggiunge una serie che riparte dai valori e dalla prescrizione
  /// dell'ultima.
  SerieInCorso aggiungiSerie() {
    final ultima = serie.lastOrNull;
    final nuova = SerieInCorso(
      ripetizioni: ultima?.ripetizioni,
      caricoKg: ultima?.caricoKg,
      durataS: ultima?.durataS,
      obiettivoRipetizioni: ultima?.obiettivoRipetizioni,
      obiettivoCarico: ultima?.obiettivoCarico,
      recupero: ultima?.recupero,
    );
    serie.add(nuova);
    return nuova;
  }

  Map<String, Object?> _perLog() => {
    'esercizio_id': esercizioId,
    'nome': nome,
    'note': note,
    'serie': [for (final s in serie) s._perLog()],
  };
}

/// Serie di un esercizio: i valori effettivi, precompilati dalla
/// prescrizione quando il testo del coach è un numero semplice.
class SerieInCorso {
  SerieInCorso({
    this.ripetizioni,
    this.caricoKg,
    this.durataS,
    this.rpe,
    this.completata = false,
    this.obiettivoRipetizioni,
    this.obiettivoCarico,
    this.recupero,
  });

  /// Ripetizioni e carico sono testo libero (§8.1): «8» diventa 8
  /// ripetizioni, «30 s» o «2 min» una durata, «60 kg» o «60,5» un carico.
  /// Intervalli come «6-8» e indicazioni come «75% 1RM» o «RPE 8» restano
  /// solo come obiettivo da mostrare.
  factory SerieInCorso._daPrescrizione(Map<String, Object?> riga) {
    final ripetizioni = _testo(riga['ripetizioni']);
    final carico = _testo(riga['carico']);
    final recupero = _intero(riga['recupero_s']);
    return SerieInCorso(
      ripetizioni: _ripetizioniDa(ripetizioni),
      durataS: _secondiDa(ripetizioni),
      caricoKg: _chiliDa(carico),
      obiettivoRipetizioni: ripetizioni,
      obiettivoCarico: carico,
      recupero: recupero == null ? null : Duration(seconds: recupero),
    );
  }

  int? ripetizioni;
  num? caricoKg;
  int? durataS;

  /// Da 0 a 10, a passi di 0,5.
  num? rpe;
  bool completata;

  /// Prescrizione del coach, come l'ha scritta: «6-8», «75% 1RM».
  final String? obiettivoRipetizioni;
  final String? obiettivoCarico;

  /// Recupero prescritto dopo la serie, per il timer.
  final Duration? recupero;

  Map<String, Object?> _perLog() => {
    'ripetizioni': ?ripetizioni,
    'carico_kg': ?caricoKg,
    'durata_s': ?durataS,
    'rpe': ?rpe,
    'completata': completata,
  };
}

/// Una serie già registrata in un log, per suggerire i valori la volta
/// successiva.
class SerieFatta {
  const SerieFatta({this.ripetizioni, this.caricoKg, this.durataS});

  factory SerieFatta.daLog(Map<String, Object?> serie) => SerieFatta(
    ripetizioni: _intero(serie['ripetizioni']),
    caricoKg: _numero(serie['carico_kg']),
    durataS: _intero(serie['durata_s']),
  );

  final int? ripetizioni;
  final num? caricoKg;
  final int? durataS;

  bool get vuota => ripetizioni == null && caricoKg == null && durataS == null;
}

final _numeroIntero = RegExp(r'^\s*(\d{1,5})\s*$');

/// Secondi o minuti, anche con la notazione 30" e 2'.
final _durata = RegExp(
  r'''^\s*(\d{1,5})\s*(s|sec|secondi|"|min|minuti|')\s*$''',
  caseSensitive: false,
);
final _chili = RegExp(
  r'^\s*(\d{1,5}(?:[.,]\d{1,3})?)\s*(?:kg)?\s*$',
  caseSensitive: false,
);

int? _ripetizioniDa(String? testo) {
  final m = testo == null ? null : _numeroIntero.firstMatch(testo);
  final valore = m == null ? null : int.parse(m[1]!);
  return valore != null && valore <= 10000 ? valore : null;
}

int? _secondiDa(String? testo) {
  final m = testo == null ? null : _durata.firstMatch(testo);
  if (m == null) return null;
  final unita = m[2]!.toLowerCase();
  final minuti = unita.startsWith('min') || unita == "'";
  final secondi = int.parse(m[1]!) * (minuti ? 60 : 1);
  return secondi <= 86400 ? secondi : null;
}

num? _chiliDa(String? testo) {
  final m = testo == null ? null : _chili.firstMatch(testo);
  final valore = m == null ? null : num.parse(m[1]!.replaceAll(',', '.'));
  return valore != null && valore <= 10000 ? valore : null;
}

List<Map<String, Object?>> _oggetti(Object? valore) => [
  if (valore is List<Object?>)
    for (final elemento in valore)
      if (elemento is Map<String, Object?>) elemento,
];

String? _testo(Object? valore) => valore is String ? valore : null;

int? _intero(Object? valore) => valore is int ? valore : null;

num? _numero(Object? valore) => valore is num ? valore : null;
