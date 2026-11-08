import 'dart:convert';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'allenamenti.dart';
import 'atleti.dart';
import 'chat.dart';
import 'cibo.dart';
import 'contesto.dart';
import 'errori.dart';
import 'eventi.dart';
import 'modelli.dart';
import 'pesi.dart';
import 'questionari.dart';
import 'schede.dart';

/// I dati del coach nella forma che legge l'app del coach (§16.3). Il server
/// li manda al telefono; se un giorno il telefono farà da server, l'app potrà
/// leggerli da qui direttamente.
class VistaTelefonoCoach {
  VistaTelefonoCoach(
    this._c, {
    required GestioneAtleti atleti,
    required GestioneMessaggi messaggi,
    required GestioneAllenamenti allenamenti,
    required GestionePesi pesi,
    required GestioneCibo cibo,
    required GestioneQuestionari questionari,
    required GestioneSchede schede,
    int budgetPagina = _budgetPredefinito,
  }) : _atleti = atleti,
       _messaggi = messaggi,
       _allenamenti = allenamenti,
       _pesi = pesi,
       _cibo = cibo,
       _questionari = questionari,
       _schede = schede,
       _budgetPagina = budgetPagina;

  final ContestoCoach _c;
  final GestioneAtleti _atleti;
  final GestioneMessaggi _messaggi;
  final GestioneAllenamenti _allenamenti;
  final GestionePesi _pesi;
  final GestioneCibo _cibo;
  final GestioneQuestionari _questionari;
  final GestioneSchede _schede;
  final int _budgetPagina;

  /// Una pagina resta ben sotto il limite di 2 MiB (§6.2).
  static const _budgetPredefinito = 1536 * 1024;
  static const _messaggiPerPagina = 200;
  static const _allenamentiPerPagina = 50;
  static const _giornatePerPagina = 28;

  Database get _db => _c.archivio.db;

  /// Riassume lo stato dei dati che l'app mostra (§16.3): se non cambia, non
  /// c'è niente di nuovo da chiedere.
  String impronta() {
    final r = _db.select('''
SELECT
  (SELECT COUNT(*) FROM atleti WHERE stato = 'attivo') AS atleti,
  (SELECT COUNT(*) FROM messaggi) AS messaggi,
  (SELECT COUNT(*) FROM messaggi WHERE autore = 'atleta' AND letto = 0) AS non_letti,
  (SELECT COUNT(*) || '.' || COALESCE(SUM(rev), 0) FROM log) AS log,
  (SELECT COUNT(*) || '.' || COALESCE(SUM(rev), 0) FROM pesi) AS pesi,
  (SELECT COUNT(*) || '.' || COALESCE(SUM(rev), 0) FROM giornate) AS giornate,
  (SELECT COUNT(*) || '.' || COALESCE(MAX(sequenza), 0) FROM obiettivi_cibo) AS obiettivi,
  (SELECT COUNT(*) FROM questionari_inviati) AS questionari,
  (SELECT COUNT(*) FROM questionari_inviati WHERE stato = 'risposto') AS risposti,
  (SELECT COUNT(*) FROM questionari_inviati WHERE stato = 'risposto' AND letto = 0) AS nuovi,
  (SELECT COUNT(*) FROM dispositivi WHERE stato = 'attivo') AS telefoni
''').first;
    return [
      _c.archivio.epoca,
      r['atleti'],
      r['messaggi'],
      r['non_letti'],
      r['log'],
      r['pesi'],
      r['giornate'],
      r['obiettivi'],
      r['questionari'],
      r['risposti'],
      r['nuovi'],
      r['telefoni'],
    ].join('-');
  }

  /// `GET /v1/coach/atleti`.
  Map<String, Object?> elenco() => {
    'atleti': [
      for (final r in _atleti.elenco()) _riepilogo(r.atleta, r.dispositivo),
    ],
    'impronta': impronta(),
  };

  /// `GET /v1/coach/atleti/<id>`.
  Map<String, Object?> atleta(String id) {
    final atleta = _esistente(id);
    return {
      ..._riepilogo(atleta, _dispositivoAttivo(id)),
      'note': atleta.note,
      'allenamenti_totali':
          _db.select('SELECT COUNT(*) AS n FROM log WHERE atleta_id = ? AND eliminato = 0', [id]).first['n'],
      'schede': [
        for (final s in _schede.elenco(id))
          {
            'id': s.id,
            'titolo': s.titolo,
            'stato': s.stato.name,
            'revisione': s.revisione,
            'ricevuta_il': switch (s.revisioni.where((r) => r.numero == s.revisione).firstOrNull?.ricevutaIl) {
              final DateTime quando => formattaDataOra(quando),
              null => null,
            },
          },
      ],
    };
  }

  /// `GET /v1/coach/atleti/<id>/messaggi`: gli ultimi prima di [prima], dal
  /// più vecchio.
  Map<String, Object?> messaggi(String atletaId, {String? prima}) {
    _esistente(atletaId);
    var condizione = '';
    final parametri = <Object?>[atletaId];
    if (prima != null) {
      final limite = _db.select('SELECT ordine FROM messaggi WHERE id = ? AND atleta_id = ?', [prima, atletaId]).firstOrNull;
      if (limite == null) throw const ErroreHttp(404, CodiceErrore.nonTrovato);
      condizione = 'AND (ordine, id) < (?, ?)';
      parametri.addAll([limite['ordine'], prima]);
    }
    final righe = _db.select(
      'SELECT * FROM messaggi WHERE atleta_id = ? $condizione ORDER BY ordine DESC, id DESC LIMIT ?',
      [...parametri, _messaggiPerPagina + 1],
    );
    final (scelti, altri) = _riempi(righe.map(_messaggio), _messaggiPerPagina);
    return {'messaggi': scelti.reversed.toList(), 'altri': altri};
  }

  /// `POST /v1/coach/atleti/<id>/messaggi`: idempotente sull'[id], così l'app
  /// può ritentare senza doppioni.
  Map<String, Object?> inviaMessaggio(String atletaId, String id, String testo) {
    _esistente(atletaId);
    final esistente = _db.select('SELECT * FROM messaggi WHERE id = ?', [id]).firstOrNull;
    if (esistente != null) {
      if (esistente['atleta_id'] != atletaId || esistente['autore'] != 'coach') {
        throw const ErroreHttp(409, CodiceErrore.richiestaNonValida, messaggio: 'Id già usato');
      }
      return _messaggio(esistente);
    }
    try {
      _messaggi.invia(atletaId, testo, id: id);
    } on OperazioneNonValida catch (e) {
      throw ErroreHttp(400, CodiceErrore.richiestaNonValida, messaggio: e.messaggio);
    }
    _c.emetti(ModificaDalTelefonoCoach(atletaId));
    return _messaggio(_db.select('SELECT * FROM messaggi WHERE id = ?', [id]).first);
  }

  /// `POST /v1/coach/atleti/<id>/messaggi/letti`.
  void segnaLetti(String atletaId) {
    _esistente(atletaId);
    _messaggi.segnaLetti(atletaId);
    _c.emetti(ModificaDalTelefonoCoach(atletaId));
  }

  /// `GET /v1/coach/atleti/<id>/allenamenti`: dal più recente, dopo [prima].
  Map<String, Object?> allenamenti(String atletaId, {String? prima}) {
    _esistente(atletaId);
    final tutti = _allenamenti.elenco(atletaId);
    var inizio = 0;
    if (prima != null) {
      inizio = tutti.indexWhere((a) => a.id == prima) + 1;
      if (inizio == 0) throw const ErroreHttp(404, CodiceErrore.nonTrovato);
    }
    final (scelti, altri) = _riempi(
      tutti.skip(inizio).map(
        (a) => {...a.contenuto, 'ricevuto_il': formattaDataOra(a.ricevutoIl)},
      ),
      _allenamentiPerPagina,
    );
    return {'allenamenti': scelti, 'altri': altri};
  }

  /// `GET /v1/coach/atleti/<id>/pesi`.
  Map<String, Object?> pesi(String atletaId) {
    _esistente(atletaId);
    return {
      'pesi': [
        for (final p in _pesi.elenco(atletaId)) {'giorno': formattaData(p.giorno), 'kg': p.kg},
      ],
    };
  }

  /// `GET /v1/coach/atleti/<id>/cibo`: l'obiettivo e le giornate prima del
  /// giorno [prima], dalla più recente, fino a 28 e fin dove stanno nella
  /// risposta.
  Map<String, Object?> cibo(String atletaId, {String? prima}) {
    _esistente(atletaId);
    final limite = prima == null ? null : analizzaData(prima);
    if (prima != null && limite == null) throw const ErroreHttp(400, CodiceErrore.richiestaNonValida);
    final giornate = [
      for (final g in _cibo.elenco(atletaId).reversed)
        if (limite == null || g.giorno.isBefore(limite))
          {'giorno': formattaData(g.giorno), 'voci': [for (final v in g.voci) v.toJson()]},
    ];
    final (scelte, altre) = _riempi(giornate, _giornatePerPagina);
    return {'obiettivo': _cibo.obiettivo(atletaId)?.toJson(), 'giornate': scelte, 'altri': altre};
  }

  /// `GET /v1/coach/atleti/<id>/questionari`: dal più recente, fin dove sta
  /// nella risposta. Non si pagina: sono pochi, e le foto si scaricano a parte.
  Map<String, Object?> questionari(String atletaId) {
    _esistente(atletaId);
    final (scelti, altri) = _riempi(
      _questionari.inviati(atletaId).map(
        (q) => {
          'id': q.id,
          'titolo': q.titolo,
          'contenuto': q.contenuto,
          'inviato_il': formattaDataOra(q.inviatoIl),
          'stato': q.stato.name,
          'risposta': q.risposta,
          'risposto_il': switch (q.rispostoIl) {
            final DateTime quando => formattaDataOra(quando),
            null => null,
          },
          'letto': q.letto,
        },
      ),
      null,
    );
    return {'questionari': scelti, 'altri': altri};
  }

  /// `POST /v1/coach/questionari/<id>/letto`.
  void segnaQuestionarioLetto(String id) {
    final questionario = _questionari.inviato(id);
    if (questionario == null) throw const ErroreHttp(404, CodiceErrore.nonTrovato);
    _questionari.segnaLetto(id);
    _c.emetti(ModificaDalTelefonoCoach(questionario.atletaId));
  }

  Atleta _esistente(String id) {
    final atleta = _atleti.cerca(id);
    if (atleta == null) throw const ErroreHttp(404, CodiceErrore.nonTrovato);
    return atleta;
  }

  Dispositivo? _dispositivoAttivo(String atletaId) {
    final riga = _db.select(
      "SELECT * FROM dispositivi WHERE atleta_id = ? AND stato = 'attivo'",
      [atletaId],
    ).firstOrNull;
    return riga == null ? null : Dispositivo.daRiga(riga);
  }

  Map<String, Object?> _riepilogo(Atleta atleta, Dispositivo? dispositivo) {
    final ultimo = _db.select(
      'SELECT * FROM messaggi WHERE atleta_id = ? ORDER BY ordine DESC, id DESC LIMIT 1',
      [atleta.id],
    ).firstOrNull;
    final allenamento = _db.select(
      r"SELECT json_extract(contenuto, '$.eseguito_il') AS quando FROM log "
      'WHERE atleta_id = ? AND eliminato = 0 ORDER BY eseguito_il DESC LIMIT 1',
      [atleta.id],
    ).firstOrNull;
    return {
      'id': atleta.id,
      'nome': atleta.nome,
      'telefono_collegato': dispositivo != null,
      'ultimo_contatto': switch (dispositivo?.ultimoContatto) {
        final DateTime quando => formattaDataOra(quando),
        null => null,
      },
      'non_letti': _messaggi.nonLetti(atleta.id),
      'risposte_nuove': _questionari.nonLette(atleta.id),
      'ultimo_messaggio': ultimo == null ? null : _anteprima(ultimo),
      'ultimo_allenamento': allenamento?['quando'],
    };
  }

  /// Per l'elenco: una riga basta, e l'elenco di 200 atleti resta leggero.
  Map<String, Object?> _anteprima(Row r) {
    final testo = r['testo'] as String;
    return {
      'autore': r['autore'],
      'testo': testo.length > 120 ? '${testo.substring(0, 119)}…' : testo,
      'inviato_il': r['inviato_il'],
      'con_video': r['video'] != null,
    };
  }

  Map<String, Object?> _messaggio(Row r) => {
    ..._messaggi.perProtocollo(r),
    'letto': r['letto'] == 1,
    'video_eliminato': r['video_eliminato'] == 1,
  };

  /// Prende gli elementi in ordine finché ci stanno in una risposta: al più
  /// [massimo] e sotto [_budgetPagina]. Almeno uno passa sempre, così l'app
  /// avanza comunque. Il secondo valore dice se ne restano altri.
  (List<Map<String, Object?>>, bool) _riempi(Iterable<Map<String, Object?>> elementi, int? massimo) {
    final scelti = <Map<String, Object?>>[];
    var byte = 0;
    for (final elemento in elementi) {
      byte += utf8.encode(jsonEncode(elemento)).length;
      final oltre = (massimo != null && scelti.length >= massimo) || (scelti.isNotEmpty && byte > _budgetPagina);
      if (oltre) return (scelti, true);
      scelti.add(elemento);
    }
    return (scelti, false);
  }
}
