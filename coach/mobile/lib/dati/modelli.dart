import 'package:protocollo/protocollo.dart';

// Ciò che le schermate mostrano, letto dal JSON del §16.3. I campi facoltativi
// o sconosciuti non fanno cadere l'app: entro la v1 il protocollo ne aggiunge.

DateTime? _quando(Object? valore) => analizzaDataOra(valore)?.toLocal();

int _intero(Object? valore) => valore is num ? valore.toInt() : 0;

String _testo(Object? valore) => valore is String ? valore : '';

Iterable<Map<String, Object?>> _mappe(Object? lista) =>
    lista is List<Object?> ? lista.whereType<Map<String, Object?>>() : const [];

/// L'ultimo messaggio di una chat, per l'elenco.
class Anteprima {
  const Anteprima({required this.dalCoach, required this.testo, required this.conVideo, required this.inviatoIl});

  final bool dalCoach;
  final String testo;
  final bool conVideo;
  final DateTime? inviatoIl;

  static Anteprima? daJson(Object? json) => json is Map<String, Object?>
      ? Anteprima(
          dalCoach: json['autore'] == 'coach',
          testo: _testo(json['testo']),
          conVideo: json['con_video'] == true,
          inviatoIl: _quando(json['inviato_il']),
        )
      : null;
}

class RiepilogoAtleta {
  const RiepilogoAtleta({
    required this.id,
    required this.nome,
    required this.telefonoCollegato,
    required this.ultimoContatto,
    required this.nonLetti,
    required this.risposteNuove,
    required this.ultimoMessaggio,
    required this.ultimoAllenamento,
  });

  factory RiepilogoAtleta.daJson(Map<String, Object?> m) => RiepilogoAtleta(
    id: _testo(m['id']),
    nome: _testo(m['nome']),
    telefonoCollegato: m['telefono_collegato'] == true,
    ultimoContatto: _quando(m['ultimo_contatto']),
    nonLetti: _intero(m['non_letti']),
    risposteNuove: _intero(m['risposte_nuove']),
    ultimoMessaggio: Anteprima.daJson(m['ultimo_messaggio']),
    ultimoAllenamento: _quando(m['ultimo_allenamento']),
  );

  final String id;
  final String nome;
  final bool telefonoCollegato;
  final DateTime? ultimoContatto;
  final int nonLetti;
  final int risposteNuove;
  final Anteprima? ultimoMessaggio;
  final DateTime? ultimoAllenamento;
}

class SchedaAtleta {
  const SchedaAtleta({
    required this.titolo,
    required this.stato,
    required this.revisione,
    required this.ricevutaIl,
  });

  final String titolo;

  /// `bozza`, `pubblicata` o `archiviata`.
  final String stato;
  final int revisione;
  final DateTime? ricevutaIl;
}

class DettaglioAtleta {
  const DettaglioAtleta({
    required this.riepilogo,
    required this.note,
    required this.allenamentiTotali,
    required this.schede,
  });

  factory DettaglioAtleta.daJson(Map<String, Object?> m) => DettaglioAtleta(
    riepilogo: RiepilogoAtleta.daJson(m),
    note: _testo(m['note']),
    allenamentiTotali: _intero(m['allenamenti_totali']),
    schede: [
      for (final s in _mappe(m['schede']))
        SchedaAtleta(
          titolo: _testo(s['titolo']),
          stato: _testo(s['stato']),
          revisione: _intero(s['revisione']),
          ricevutaIl: _quando(s['ricevuta_il']),
        ),
    ],
  );

  final RiepilogoAtleta riepilogo;
  final String note;
  final int allenamentiTotali;
  final List<SchedaAtleta> schede;
}

/// A che punto è un messaggio che il coach ha scritto dal telefono (§16.4).
enum StatoInvio {
  /// È sul PC.
  inviato,

  /// È in coda: parte appena il PC risponde.
  inAttesa,

  /// Il PC l'ha rifiutato: non si ritenta.
  rifiutato,
}

class MessaggioChat {
  const MessaggioChat({
    required this.id,
    required this.dalCoach,
    required this.testo,
    required this.inviatoIl,
    this.conVideo = false,
    this.videoEliminato = false,
    this.durataVideoS,
    this.esercizio,
    this.serie,
    this.statoInvio = StatoInvio.inviato,
  });

  factory MessaggioChat.daJson(Map<String, Object?> m) {
    final video = m['video'];
    final riferimento = m['riferimento'];
    return MessaggioChat(
      id: _testo(m['id']),
      dalCoach: m['autore'] == 'coach',
      testo: _testo(m['testo']),
      inviatoIl: _quando(m['inviato_il']),
      conVideo: video is Map<String, Object?>,
      videoEliminato: m['video_eliminato'] == true,
      durataVideoS: video is Map<String, Object?> ? _intero(video['durata_s']) : null,
      esercizio: riferimento is Map<String, Object?> && riferimento['esercizio'] is String
          ? riferimento['esercizio'] as String
          : null,
      serie: riferimento is Map<String, Object?> && riferimento['serie'] is int ? riferimento['serie'] as int : null,
    );
  }

  final String id;
  final bool dalCoach;
  final String testo;
  final DateTime? inviatoIl;
  final bool conVideo;
  final bool videoEliminato;
  final int? durataVideoS;

  /// L'esercizio e la serie a cui si riferisce il video, se ci sono.
  final String? esercizio;
  final int? serie;
  final StatoInvio statoInvio;
}

class SerieEseguita {
  const SerieEseguita({
    required this.completata,
    required this.ripetizioni,
    required this.caricoKg,
    required this.durataS,
    required this.rpe,
  });

  final bool completata;
  final num? ripetizioni;
  final num? caricoKg;
  final num? durataS;
  final num? rpe;
}

class EsercizioEseguito {
  const EsercizioEseguito({required this.nome, required this.note, required this.serie});

  final String nome;
  final String note;
  final List<SerieEseguita> serie;
}

/// Un allenamento registrato dall'atleta (§8.2).
class AllenamentoAtleta {
  const AllenamentoAtleta({
    required this.id,
    required this.eseguitoIl,
    required this.note,
    required this.durataMin,
    required this.rpe,
    required this.esercizi,
  });

  factory AllenamentoAtleta.daJson(Map<String, Object?> m) => AllenamentoAtleta(
    id: _testo(m['id']),
    eseguitoIl: _quando(m['eseguito_il']),
    note: _testo(m['note']),
    durataMin: m['durata_min'] as num?,
    rpe: m['rpe'] as num?,
    esercizi: [
      for (final e in _mappe(m['esercizi']))
        EsercizioEseguito(
          nome: _testo(e['nome']),
          note: _testo(e['note']),
          serie: [
            for (final s in _mappe(e['serie']))
              SerieEseguita(
                completata: s['completata'] == true,
                ripetizioni: s['ripetizioni'] as num?,
                caricoKg: s['carico_kg'] as num?,
                durataS: s['durata_s'] as num?,
                rpe: s['rpe'] as num?,
              ),
          ],
        ),
    ],
  );

  final String id;
  final DateTime? eseguitoIl;
  final String note;
  final num? durataMin;
  final num? rpe;
  final List<EsercizioEseguito> esercizi;

  /// Serie fatte sul totale.
  (int, int) get serieFatte {
    var fatte = 0;
    var totali = 0;
    for (final esercizio in esercizi) {
      for (final serie in esercizio.serie) {
        totali++;
        if (serie.completata) fatte++;
      }
    }
    return (fatte, totali);
  }
}

/// L'obiettivo del cibo e le giornate dell'atleta (§8.8), dalla più recente.
class CiboAtleta {
  const CiboAtleta({required this.obiettivo, required this.giornate, required this.altri});

  /// Le giornate non conformi al protocollo si saltano: meglio mostrare le
  /// altre che niente.
  factory CiboAtleta.daJson(Map<String, Object?> m) => CiboAtleta(
    obiettivo: switch (m['obiettivo']) {
      final Map<String, Object?> o when validaObiettivoCibo(o).isEmpty => ObiettivoCibo.fromJson(o),
      _ => null,
    },
    giornate: [
      if (m['giornate'] case final List<Object?> giornate)
        for (final g in giornate)
          if (g case {'giorno': final String giorno, 'voci': final List<Object?> voci}
              when validaGiornata({
                'id': '00000000-0000-4000-8000-000000000000',
                'rev': 1,
                'eliminato': false,
                'giorno': giorno,
                'voci': voci,
              }).isEmpty)
            GiornataCibo.fromJson({'giorno': giorno, 'voci': voci}),
    ],
    altri: m['altri'] == true,
  );

  final ObiettivoCibo? obiettivo;
  final List<GiornataCibo> giornate;

  /// Ci sono altre giornate più vecchie.
  final bool altri;
}

class PesoGiorno {
  const PesoGiorno(this.giorno, this.kg);

  final DateTime giorno;
  final double kg;
}

/// Una domanda con la risposta dell'atleta, già in forma di testo.
class RispostaDomanda {
  const RispostaDomanda(this.domanda, this.risposta);

  final String domanda;

  /// Null se l'atleta non ha risposto.
  final String? risposta;
}

/// Un questionario mandato a un atleta, con le risposte se sono arrivate (§8.6).
class QuestionarioAtleta {
  const QuestionarioAtleta({
    required this.id,
    required this.titolo,
    required this.descrizione,
    required this.stato,
    required this.inviatoIl,
    required this.rispostoIl,
    required this.letto,
    required this.risposte,
    required this.foto,
  });

  factory QuestionarioAtleta.daJson(Map<String, Object?> m) {
    final contenuto = m['contenuto'];
    final domande = contenuto is Map<String, Object?> ? _mappe(contenuto['domande']) : const <Map<String, Object?>>[];
    final risposta = m['risposta'];
    final date = <String, Object?>{
      if (risposta is Map<String, Object?>)
        for (final r in _mappe(risposta['risposte'])) _testo(r['domanda_id']): r['valore'],
    };
    return QuestionarioAtleta(
      id: _testo(m['id']),
      titolo: _testo(m['titolo']),
      descrizione: contenuto is Map<String, Object?> ? _testo(contenuto['descrizione']) : '',
      stato: _testo(m['stato']),
      inviatoIl: _quando(m['inviato_il']),
      rispostoIl: _quando(m['risposto_il']),
      letto: m['letto'] == true,
      risposte: [
        for (final d in domande)
          RispostaDomanda(_testo(d['testo']), _valoreLeggibile(date[_testo(d['id'])], _testo(d['unita']))),
      ],
      foto: [
        if (risposta is Map<String, Object?> && risposta['foto'] is List<Object?>)
          ...(risposta['foto']! as List<Object?>).whereType<String>(),
      ],
    );
  }

  /// Il valore dipende dal tipo di domanda (§8.6).
  static String? _valoreLeggibile(Object? valore, String unita) => switch (valore) {
    null => null,
    final String testo => testo,
    final num numero => unita.isEmpty ? '$numero' : '$numero $unita',
    {'scelta': final String scelta} => scelta,
    {'scelte': final List<Object?> scelte, 'altro': final String altro} => [...scelte.whereType<String>(), altro].join(', '),
    {'scelte': final List<Object?> scelte} => scelte.whereType<String>().join(', '),
    {'altro': final String altro} => altro,
    _ => '$valore',
  };

  final String id;
  final String titolo;
  final String descrizione;

  /// `inviato`, `risposto` o `annullato`.
  final String stato;
  final DateTime? inviatoIl;
  final DateTime? rispostoIl;
  final bool letto;
  final List<RispostaDomanda> risposte;

  /// Id delle foto, da scaricare una per una.
  final List<String> foto;

  bool get risposto => stato == 'risposto';
}
