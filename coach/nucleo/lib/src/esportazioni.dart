import 'package:protocollo/protocollo.dart';

import 'allenamenti.dart';
import 'atleti.dart';
import 'contesto.dart';
import 'errori.dart';
import 'modelli.dart';
import 'cibo.dart';
import 'pesi.dart';
import 'schede.dart';

/// Esportazione dei dati di un atleta (§9.3, §11.3).
class GestioneEsportazioni {
  GestioneEsportazioni(this._c, this._atleti, this._schede, this._allenamenti);

  final ContestoCoach _c;
  final GestioneAtleti _atleti;
  final GestioneSchede _schede;
  final GestioneAllenamenti _allenamenti;

  /// Tutti i dati dell'atleta in JSON: anagrafica, schede con le revisioni
  /// pubblicate, allenamenti, pesi, cibo. Le note private del coach ci sono solo con
  /// [notePrivate], perché l'esportazione può finire all'atleta.
  Map<String, Object?> json(String atletaId, {bool notePrivate = false}) {
    final atleta = _atleta(atletaId);
    return {
      'formato': 'opencoach-atleta',
      'versione': 1,
      'esportato_il': formattaDataOra(_c.adesso()),
      'coach': _c.nomeCoach,
      'atleta': {
        'id': atleta.id,
        'nome': atleta.nome,
        if (notePrivate) 'note_private': atleta.note,
        'creato_il': formattaDataOra(atleta.creatoIl),
      },
      'schede': [
        for (final scheda in _schede.elenco(atletaId))
          {
            'id': scheda.id,
            'stato': scheda.stato.name,
            'bozza': scheda.bozza,
            'revisioni': [
              for (final r in scheda.revisioni.reversed)
                {
                  'revisione': r.numero,
                  'pubblicata_il': r.pubblicataIl,
                  'ricevuta_il': r.ricevutaIl == null ? null : formattaDataOra(r.ricevutaIl!),
                  'contenuto': _schede.contenutoRevisione(scheda.id, r.numero),
                },
            ],
          },
      ],
      'allenamenti': [
        for (final a in _allenamenti.elenco(atletaId).reversed) a.contenuto,
      ],
      'pesi': [
        for (final p in GestionePesi(_c).elenco(atletaId))
          {'giorno': formattaData(p.giorno), 'kg': p.kg},
      ],
      'cibo': {
        'obiettivo': GestioneCibo(_c).obiettivo(atletaId)?.toJson(),
        'giornate': [
          for (final g in GestioneCibo(_c).elenco(atletaId))
            {'giorno': formattaData(g.giorno), 'voci': [for (final v in g.voci) v.toJson()]},
        ],
      },
    };
  }

  /// Allenamenti dell'atleta in CSV, una riga per serie, dal più vecchio.
  ///
  /// Con il separatore `;` predefinito i decimali usano la virgola e il testo
  /// inizia con il BOM UTF-8: è il formato che Excel in italiano apre
  /// direttamente.
  String csv(String atletaId, {String separatore = ';'}) {
    _atleta(atletaId);
    final virgola = separatore == ';';
    String numero(Object? v) {
      if (v is! num) return '';
      final testo = v is int || v == v.roundToDouble() ? '${v.round()}' : '$v';
      return virgola ? testo.replaceAll('.', ',') : testo;
    }

    String campo(Object? v) {
      final testo = v?.toString() ?? '';
      final speciale = testo.contains(separatore) ||
          testo.contains('"') ||
          testo.contains('\n') ||
          testo.contains('\r');
      return speciale ? '"${testo.replaceAll('"', '""')}"' : testo;
    }

    final righe = <List<String>>[
      [
        'data', 'scheda', 'revisione', 'seduta', 'esercizio', 'serie', //
        'ripetizioni', 'carico_kg', 'durata_s', 'rpe', 'completata',
        'note_esercizio', 'durata_seduta_min', 'rpe_seduta', 'note_seduta',
      ],
    ];
    for (final allenamento in _allenamenti.elenco(atletaId).reversed) {
      final l = allenamento.contenuto;
      final prescritta = _allenamenti.sedutaPrescritta(allenamento);
      final titolo = _titoloScheda(l);
      final comuni = (
        data: _dataLocale(l['eseguito_il']),
        durata: numero(l['durata_min']),
        rpe: numero(l['rpe']),
        note: l['note'] is String ? l['note'] as String : '',
      );
      List<String> riga({
        String esercizio = '',
        String noteEsercizio = '',
        String serie = '',
        Map<String, Object?> dati = const {},
      }) => [
        comuni.data,
        titolo,
        numero(l['scheda_revisione']),
        prescritta?['nome'] is String ? prescritta!['nome'] as String : '',
        esercizio,
        serie,
        numero(dati['ripetizioni']),
        numero(dati['carico_kg']),
        numero(dati['durata_s']),
        numero(dati['rpe']),
        dati['completata'] == null ? '' : (dati['completata'] == true ? 'sì' : 'no'),
        noteEsercizio,
        comuni.durata,
        comuni.rpe,
        comuni.note,
      ];

      final esercizi = (l['esercizi'] as List<Object?>?) ?? const [];
      if (esercizi.isEmpty) righe.add(riga());
      for (final e in esercizi.whereType<Map<String, Object?>>()) {
        final nome = e['nome'] as String? ?? '';
        final note = e['note'] is String ? e['note'] as String : '';
        final serie = (e['serie'] as List<Object?>?) ?? const [];
        if (serie.isEmpty) righe.add(riga(esercizio: nome, noteEsercizio: note));
        for (final (i, s) in serie.whereType<Map<String, Object?>>().indexed) {
          righe.add(riga(esercizio: nome, noteEsercizio: note, serie: '${i + 1}', dati: s));
        }
      }
    }
    final testo = righe.map((r) => r.map(campo).join(separatore)).join('\r\n');
    return virgola ? '﻿$testo\r\n' : '$testo\r\n';
  }

  Atleta _atleta(String atletaId) {
    final atleta = _atleti.cerca(atletaId);
    if (atleta == null) throw const OperazioneNonValida('Atleta inesistente');
    return atleta;
  }

  String _titoloScheda(Map<String, Object?> log) {
    final schedaId = log['scheda_id'];
    final revisione = log['scheda_revisione'];
    if (schedaId is! String || revisione is! int) return '';
    final titolo = _schede.contenutoRevisione(schedaId, revisione)?['titolo'];
    return titolo is String ? titolo : '';
  }

  /// Data e ora come le ha registrate l'atleta, nel suo fuso:
  /// `2026-10-21 18:30`.
  String _dataLocale(Object? eseguitoIl) =>
      eseguitoIl is String && eseguitoIl.length >= 16
          ? eseguitoIl.substring(0, 16).replaceFirst('T', ' ')
          : '';
}
