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

  /// Aggiunge una serie vuota, che mostra in grigio la prescrizione o i valori
  /// dell'ultima: fatta lo diventa quando l'atleta la compila.
  SerieInCorso aggiungiSerie() {
    final ultima = serie.lastOrNull;
    final nuova = SerieInCorso(
      obiettivoRipetizioni: ultima?.obiettivoRipetizioni ?? ultima?.ripetizioni?.toString(),
      obiettivoCarico: ultima?.obiettivoCarico ?? ultima?.caricoKg?.toString().replaceAll('.', ','),
      obiettivoDurataS: ultima?.obiettivoDurataS ?? ultima?.durataS,
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

/// Serie di un esercizio: i valori che scrive l'atleta. La prescrizione del
/// coach resta un obiettivo, che i campi vuoti mostrano in grigio. La serie è
/// fatta se ha almeno un valore.
class SerieInCorso {
  SerieInCorso({
    this.ripetizioni,
    this.caricoKg,
    this.durataS,
    this.rpe,
    this.obiettivoRipetizioni,
    this.obiettivoCarico,
    this.obiettivoDurataS,
    this.recupero,
  });

  /// Ripetizioni e carico sono testo libero (§8.1): «30 s» o «2 min» dicono
  /// che l'esercizio è a tempo.
  factory SerieInCorso._daPrescrizione(Map<String, Object?> riga) {
    final ripetizioni = _testo(riga['ripetizioni']);
    final recupero = _intero(riga['recupero_s']);
    return SerieInCorso(
      obiettivoRipetizioni: ripetizioni,
      obiettivoCarico: _testo(riga['carico']),
      obiettivoDurataS: _secondiDa(ripetizioni),
      recupero: recupero == null ? null : Duration(seconds: recupero),
    );
  }

  int? ripetizioni;
  num? caricoKg;
  int? durataS;

  /// Da 0 a 10, a passi di 0,5.
  num? rpe;

  /// La serie conta come fatta se l'atleta ha scritto almeno un valore.
  bool get completata => ripetizioni != null || caricoKg != null || durataS != null;

  /// Prescrizione del coach, come l'ha scritta: «6-8», «75% 1RM».
  final String? obiettivoRipetizioni;
  final String? obiettivoCarico;

  /// La durata prescritta, se l'esercizio è a tempo.
  final int? obiettivoDurataS;

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

/// Secondi o minuti, anche con la notazione 30" e 2'.
final _durata = RegExp(
  r'''^\s*(\d{1,5})\s*(s|sec|secondi|"|min|minuti|')\s*$''',
  caseSensitive: false,
);
int? _secondiDa(String? testo) {
  final m = testo == null ? null : _durata.firstMatch(testo);
  if (m == null) return null;
  final unita = m[2]!.toLowerCase();
  final minuti = unita.startsWith('min') || unita == "'";
  final secondi = int.parse(m[1]!) * (minuti ? 60 : 1);
  return secondi <= 86400 ? secondi : null;
}

List<Map<String, Object?>> _oggetti(Object? valore) => [
  if (valore is List<Object?>)
    for (final elemento in valore)
      if (elemento is Map<String, Object?>) elemento,
];

String? _testo(Object? valore) => valore is String ? valore : null;

int? _intero(Object? valore) => valore is int ? valore : null;

num? _numero(Object? valore) => valore is num ? valore : null;
