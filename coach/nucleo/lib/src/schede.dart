import 'dart:convert';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'errori.dart';
import 'libreria.dart';
import 'modelli.dart';
import 'tempo.dart';

/// Campi che il programma aggiunge alla scheda inviata all'app: non possono
/// stare nella bozza.
const _campiDiProtocollo = {'id', 'revisione', 'stato', 'pubblicata_il'};

/// Schede di allenamento (§8.1, §9.3).
///
/// Il coach lavora su una bozza; pubblicare crea una revisione, che l'atleta
/// riceve alla sync successiva. Ogni cambiamento visibile all'atleta riceve
/// un numero di sequenza (§7.2).
class GestioneSchede {
  GestioneSchede(this._c);

  final ContestoCoach _c;

  Database get _db => _c.archivio.db;

  /// Crea una scheda in bozza e ne restituisce l'id.
  String crea(String atletaId, {Map<String, Object?>? contenuto}) {
    final bozza = _bozzaValida(
      contenuto ?? {'titolo': 'Nuova scheda', 'note': '', 'sedute': <Object?>[]},
    );
    final id = nuovoUuid();
    final ora = istante(_c.adesso());
    _c.archivio.transazione(() {
      if (_db.select('SELECT 1 FROM atleti WHERE id = ?', [atletaId]).isEmpty) {
        throw const OperazioneNonValida('Atleta inesistente');
      }
      _db.execute(
        'INSERT INTO schede (id, atleta_id, bozza, bozza_modificata, stato, '
        "creata_il, modificata_il) VALUES (?, ?, ?, 1, 'bozza', ?, ?)",
        [id, atletaId, jsonEncode(bozza), ora, ora],
      );
    });
    return id;
  }

  /// Salva la bozza. Le modifiche arrivano all'atleta solo dopo [pubblica].
  void salvaBozza(String schedaId, Map<String, Object?> contenuto) {
    final bozza = jsonEncode(_bozzaValida(contenuto));
    _c.archivio.transazione(() {
      final riga = _riga(schedaId);
      _db.execute(
        'UPDATE schede SET bozza = ?, bozza_modificata = ?, modificata_il = ? '
        'WHERE id = ?',
        [
          bozza,
          _bozzaModificata(schedaId, riga['revisione'] as int, bozza) ? 1 : 0,
          istante(_c.adesso()),
          schedaId,
        ],
      );
    });
  }

  /// Pubblica la bozza come nuova revisione e ne restituisce il numero.
  /// Lancia [SchedaNonValida] se la bozza non è completa. L'atleta ha una sola
  /// scheda attiva: quella che aveva passa nell'archivio.
  int pubblica(String schedaId) {
    return _c.archivio.transazione(() {
      final riga = _riga(schedaId);
      final contenuto = _conVideo(
        jsonDecode(riga['bozza'] as String) as Map<String, Object?>,
      );
      final errori = validaContenutoScheda(contenuto);
      if (errori.isNotEmpty) throw SchedaNonValida(errori);
      final revisione = _nuovaRevisione(riga, jsonEncode(contenuto), bozzaModificata: false);
      _archiviaLeAltre(riga['atleta_id'] as String, schedaId);
      return revisione;
    });
  }

  void _archiviaLeAltre(String atletaId, String schedaId) {
    for (final altra in _db.select(
      "SELECT id FROM schede WHERE atleta_id = ? AND stato = 'pubblicata' AND id != ?",
      [atletaId, schedaId],
    )) {
      archivia(altra['id'] as String);
    }
  }

  /// Schede pubblicate i cui video non sono più quelli della libreria.
  List<Scheda> conVideoDaAggiornare() => [
    for (final riga in _db.select(
      'SELECT schede.*, revisioni.contenuto AS pubblicata FROM schede '
      'JOIN revisioni ON revisioni.scheda_id = schede.id '
      'AND revisioni.revisione = schede.revisione '
      "WHERE schede.stato = 'pubblicata' ORDER BY schede.modificata_il DESC",
    ))
      if (_videoCambiati(riga['pubblicata'] as String) != null) _daRiga(riga),
  ];

  /// Ripubblica la scheda con i video attuali della libreria, senza le
  /// modifiche della bozza non ancora pubblicate. Restituisce la nuova
  /// revisione, o null se i video sono già quelli giusti.
  int? aggiornaVideo(String schedaId) {
    return _c.archivio.transazione(() {
      final riga = _riga(schedaId);
      if (riga['stato'] != 'pubblicata') return null;
      final pubblicata = _db.select(
        'SELECT contenuto FROM revisioni WHERE scheda_id = ? AND revisione = ?',
        [schedaId, riga['revisione']],
      ).first['contenuto'] as String;
      final nuova = _videoCambiati(pubblicata);
      if (nuova == null) return null;
      final bozza = jsonEncode(
        _conVideo(jsonDecode(riga['bozza'] as String) as Map<String, Object?>),
      );
      return _nuovaRevisione(riga, nuova, bozzaModificata: bozza != nuova);
    });
  }

  /// Aggiorna lo stato «modifiche non pubblicate» dopo un cambiamento della
  /// libreria, che cambia i video che la bozza pubblicherebbe.
  void ricalcolaModifiche() {
    _c.archivio.transazione(() {
      for (final riga in _db.select(
        'SELECT id, bozza, revisione, bozza_modificata FROM schede '
        "WHERE revisione > 0 AND stato IN ('pubblicata', 'archiviata')",
      )) {
        final id = riga['id'] as String;
        final modificata = _bozzaModificata(
          id,
          riga['revisione'] as int,
          riga['bozza'] as String,
        );
        if (modificata != (riga['bozza_modificata'] == 1)) {
          _db.execute('UPDATE schede SET bozza_modificata = ? WHERE id = ?', [
            modificata ? 1 : 0,
            id,
          ]);
        }
      }
    });
  }

  int _nuovaRevisione(
    Row riga,
    String contenuto, {
    required bool bozzaModificata,
  }) {
    final schedaId = riga['id'] as String;
    final revisione = (riga['revisione'] as int) + 1;
    final sequenza = _c.archivio.prossimaSequenza();
    _db.execute(
      'INSERT INTO revisioni (scheda_id, revisione, contenuto, pubblicata_il, '
      'sequenza) VALUES (?, ?, ?, ?, ?)',
      [schedaId, revisione, contenuto, formattaDataOra(_c.adesso()), sequenza],
    );
    _db.execute(
      "UPDATE schede SET stato = 'pubblicata', revisione = ?, sequenza = ?, "
      'bozza_modificata = ?, modificata_il = ? WHERE id = ?',
      [
        revisione,
        sequenza,
        bozzaModificata ? 1 : 0,
        istante(_c.adesso()),
        schedaId,
      ],
    );
    return revisione;
  }

  /// Se pubblicare [bozza] cambierebbe la revisione [revisione].
  bool _bozzaModificata(String schedaId, int revisione, String bozza) {
    if (revisione == 0) return true;
    final pubblicata = _db.select(
      'SELECT contenuto FROM revisioni WHERE scheda_id = ? AND revisione = ?',
      [schedaId, revisione],
    ).first;
    return pubblicata['contenuto'] !=
        jsonEncode(_conVideo(jsonDecode(bozza) as Map<String, Object?>));
  }

  /// Il contenuto [pubblicata] con i video attuali della libreria, o null se
  /// non cambia.
  String? _videoCambiati(String pubblicata) {
    final aggiornata = jsonEncode(
      _conVideo(jsonDecode(pubblicata) as Map<String, Object?>),
    );
    return aggiornata == pubblicata ? null : aggiornata;
  }

  /// Copia di [contenuto] in cui ogni esercizio ha il video dell'esercizio
  /// con lo stesso nome nella libreria, o nessun video (§8.1, §9.3).
  Map<String, Object?> _conVideo(Map<String, Object?> contenuto) {
    final video = {
      for (final riga in _db.select(
        'SELECT chiave, video FROM libreria WHERE video IS NOT NULL',
      ))
        riga['chiave'] as String: riga['video'] as String,
    };
    final copia = jsonDecode(jsonEncode(contenuto)) as Map<String, Object?>;
    if (copia['sedute'] case final List<Object?> sedute) {
      for (final seduta in sedute) {
        if (seduta case {'esercizi': final List<Object?> esercizi}) {
          for (final esercizio in esercizi) {
            if (esercizio is! Map<String, Object?>) continue;
            esercizio.remove('video');
            if (esercizio['nome'] case final String nome) {
              final link = video[chiaveEsercizio(nome)];
              if (link != null) esercizio['video'] = link;
            }
          }
        }
      }
    }
    return copia;
  }

  /// Sposta la scheda nell'archivio dell'atleta, in sola lettura.
  void archivia(String schedaId) => _cambiaStato(
    schedaId,
    da: 'pubblicata',
    a: 'archiviata',
    errore: 'Si possono archiviare solo schede pubblicate',
  );

  /// Riporta una scheda archiviata tra quelle attive, al posto di quella che
  /// l'atleta aveva.
  void ripristina(String schedaId) => _c.archivio.transazione(() {
    _cambiaStato(
      schedaId,
      da: 'archiviata',
      a: 'pubblicata',
      errore: 'La scheda non è archiviata',
    );
    _archiviaLeAltre(_riga(schedaId)['atleta_id'] as String, schedaId);
  });

  /// Elimina la scheda. Se l'atleta l'aveva ricevuta, la toglie anche dal suo
  /// telefono alla sync successiva.
  void elimina(String schedaId) {
    _c.archivio.transazione(() {
      final riga = _riga(schedaId);
      if (riga['stato'] == 'bozza') {
        _db.execute('DELETE FROM schede WHERE id = ?', [schedaId]);
        return;
      }
      _db.execute('DELETE FROM revisioni WHERE scheda_id = ?', [schedaId]);
      _db.execute(
        "UPDATE schede SET stato = 'eliminata', bozza = '{}', sequenza = ?, "
        'modificata_il = ? WHERE id = ?',
        [_c.archivio.prossimaSequenza(), istante(_c.adesso()), schedaId],
      );
    });
  }

  /// Copia la bozza in una nuova scheda per [atletaId] (lo stesso atleta se
  /// null), con nuovi id per sedute ed esercizi.
  String duplica(String schedaId, {String? atletaId}) {
    final riga = _riga(schedaId);
    final destinatario = atletaId ?? riga['atleta_id'] as String;
    final copia = _conNuoviId(jsonDecode(riga['bozza'] as String));
    if (destinatario == riga['atleta_id'] && copia is Map<String, Object?>) {
      copia['titolo'] = '${copia['titolo'] ?? ''} (copia)';
    }
    return crea(destinatario, contenuto: copia as Map<String, Object?>);
  }

  Scheda? cerca(String schedaId) {
    final riga = _db.select(
      "SELECT * FROM schede WHERE id = ? AND stato != 'eliminata'",
      [schedaId],
    ).firstOrNull;
    return riga == null ? null : _daRiga(riga);
  }

  /// Schede dell'atleta, dalla modificata più di recente.
  List<Scheda> elenco(String atletaId) => [
    for (final riga in _db.select(
      "SELECT * FROM schede WHERE atleta_id = ? AND stato != 'eliminata' "
      'ORDER BY modificata_il DESC',
      [atletaId],
    ))
      _daRiga(riga),
  ];

  /// Contenuto di una revisione pubblicata, per confrontare un log con la
  /// prescrizione che l'atleta seguiva.
  Map<String, Object?>? contenutoRevisione(String schedaId, int revisione) {
    final riga = _db.select(
      'SELECT contenuto FROM revisioni WHERE scheda_id = ? AND revisione = ?',
      [schedaId, revisione],
    ).firstOrNull;
    return riga == null
        ? null
        : jsonDecode(riga['contenuto'] as String) as Map<String, Object?>;
  }

  /// La scheda come la riceve l'app (§8.1), dall'ultima revisione pubblicata.
  Map<String, Object?> perProtocollo(Row scheda) {
    final revisione = _db.select(
      'SELECT contenuto, pubblicata_il FROM revisioni '
      'WHERE scheda_id = ? AND revisione = ?',
      [scheda['id'], scheda['revisione']],
    ).first;
    return {
      'id': scheda['id'],
      'revisione': scheda['revisione'],
      'stato': scheda['stato'],
      'pubblicata_il': revisione['pubblicata_il'],
      ...jsonDecode(revisione['contenuto'] as String) as Map<String, Object?>,
    };
  }

  void _cambiaStato(
    String schedaId, {
    required String da,
    required String a,
    required String errore,
  }) {
    _c.archivio.transazione(() {
      if (_riga(schedaId)['stato'] != da) throw OperazioneNonValida(errore);
      _db.execute(
        'UPDATE schede SET stato = ?, sequenza = ?, modificata_il = ? WHERE id = ?',
        [a, _c.archivio.prossimaSequenza(), istante(_c.adesso()), schedaId],
      );
    });
  }

  Row _riga(String schedaId) {
    final riga = _db.select(
      "SELECT * FROM schede WHERE id = ? AND stato != 'eliminata'",
      [schedaId],
    ).firstOrNull;
    if (riga == null) throw const OperazioneNonValida('Scheda inesistente');
    return riga;
  }

  Map<String, Object?> _bozzaValida(Map<String, Object?> contenuto) {
    final bozza = Map<String, Object?>.of(contenuto)
      ..removeWhere((chiave, _) => _campiDiProtocollo.contains(chiave));
    // Margine per i campi aggiunti in [perProtocollo].
    if (dimensioneJson(bozza) > Limiti.schedaMassima - 1024) {
      throw const OperazioneNonValida('La scheda è troppo grande');
    }
    return bozza;
  }

  Object? _conNuoviId(Object? valore) {
    if (valore is List<Object?>) return [for (final v in valore) _conNuoviId(v)];
    if (valore is Map<String, Object?>) {
      return {
        for (final MapEntry(:key, :value) in valore.entries)
          key: key == 'id' && uuidValido(value) ? nuovoUuid() : _conNuoviId(value),
      };
    }
    return valore;
  }

  Scheda _daRiga(Row r) {
    final revisioni = [
      for (final v in _db.select(
        'SELECT revisione, pubblicata_il, ricevuta_il FROM revisioni '
        'WHERE scheda_id = ? ORDER BY revisione DESC',
        [r['id']],
      ))
        RevisioneScheda(
          numero: v['revisione'] as int,
          pubblicataIl: v['pubblicata_il'] as String,
          ricevutaIl: leggiIstanteFacoltativo(v['ricevuta_il']),
        ),
    ];
    return Scheda(
      id: r['id'] as String,
      atletaId: r['atleta_id'] as String,
      stato: StatoScheda.values.byName(r['stato'] as String),
      bozza: jsonDecode(r['bozza'] as String) as Map<String, Object?>,
      revisione: r['revisione'] as int,
      modificheNonPubblicate: r['bozza_modificata'] == 1,
      creataIl: leggiIstante(r['creata_il'] as String),
      modificataIl: leggiIstante(r['modificata_il'] as String),
      revisioni: revisioni,
    );
  }
}
