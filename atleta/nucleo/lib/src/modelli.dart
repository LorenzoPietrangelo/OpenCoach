import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'problemi.dart';
import 'tempo.dart';

/// Stato del collegamento con un coach.
/// Come è finita un'attesa di novità dal coach (§7.4).
enum EsitoAttesa {
  /// Il coach ha qualcosa di nuovo: conviene sincronizzare.
  novita,

  /// L'attesa è finita senza novità.
  nessunaNovita,

  /// Il programma del coach non lo sa fare: è precedente alla 1.3.1.
  nonSupportata,

  /// Il coach non si è raggiunto.
  guasto,

  /// Il collegamento è chiuso.
  nonDisponibile,
}

enum StatoCollegamento {
  /// Il telefono sincronizza con il coach.
  attivo,

  /// Il coach ha revocato il dispositivo (HTTP 401). Schede e log restano
  /// consultabili ed esportabili, ma non si sincronizzano più (§10.2).
  revocato,

  /// L'atleta si è scollegato, oppure si è abbinato allo stesso coach come
  /// un altro atleta. Come dopo una revoca, i dati restano finché l'atleta
  /// non li cancella.
  scollegato,
}

/// Condizione SQL dei log in coda (§7.3, punto 2): `rev` maggiore
/// dell'ultima confermata dal coach, e non rifiutati.
const condizioneInCoda = 'log.rev > log.rev_confermata AND log.rifiuto IS NULL';

/// Selezione dei coach con i conteggi dei log per lo stato (§7.5).
const selezioneCoach =
    'SELECT coach.*, '
    '(SELECT COUNT(*) FROM log WHERE log.coach_id = coach.id '
    'AND $condizioneInCoda) AS log_in_attesa, '
    '(SELECT COUNT(*) FROM log WHERE log.coach_id = coach.id '
    'AND log.rifiuto IS NOT NULL) AS log_rifiutati '
    'FROM coach';

/// Coach a cui il telefono è o è stato abbinato, con lo stato da mostrare
/// all'atleta (§7.5).
class CoachCollegato {
  const CoachCollegato({
    required this.id,
    required this.indirizzo,
    required this.nomeCoach,
    required this.nomeAtleta,
    required this.atletaId,
    required this.dispositivoId,
    required this.stato,
    required this.confermaInSospeso,
    required this.abbinatoIl,
    required this.epoca,
    required this.cursore,
    required this.ultimaSync,
    required this.problema,
    required this.problemaIl,
    required this.logInAttesa,
    required this.logRifiutati,
    this.condividePesi = true,
    this.pesiSupportati,
    this.chatSupportata,
  });

  factory CoachCollegato.daRiga(Row r) => CoachCollegato(
    id: r['id'] as int,
    indirizzo: r['indirizzo'] as String,
    nomeCoach: r['nome_coach'] as String,
    nomeAtleta: r['nome_atleta'] as String,
    atletaId: r['atleta_id'] as String,
    dispositivoId: r['dispositivo_id'] as String,
    stato: StatoCollegamento.values.byName(r['stato'] as String),
    confermaInSospeso: r['conferma_in_sospeso'] == 1,
    abbinatoIl: leggiIstante(r['abbinato_il'] as String),
    epoca: r['epoca'] as String?,
    cursore: r['cursore'] as String?,
    ultimaSync: leggiIstanteFacoltativo(r['ultima_sync']),
    problema: switch (r['problema']) {
      final String nome => ProblemaSync.values.byName(nome),
      _ => null,
    },
    problemaIl: leggiIstanteFacoltativo(r['problema_il']),
    logInAttesa: r['log_in_attesa'] as int,
    logRifiutati: r['log_rifiutati'] as int,
    condividePesi: r['condividi_pesi'] == 1,
    pesiSupportati: switch (r['pesi_supportati']) {
      final int valore => valore == 1,
      _ => null,
    },
    chatSupportata: switch (r['chat_supportata']) {
      final int valore => valore == 1,
      _ => null,
    },
  );

  /// Id locale del collegamento.
  final int id;

  /// Indirizzo onion del coach, senza ".onion".
  final String indirizzo;
  final String nomeCoach;
  final String nomeAtleta;
  final String atletaId;
  final String dispositivoId;
  final StatoCollegamento stato;

  /// Vero finché il coach non ha ricevuto `POST /v1/abbinamento/conferma`
  /// (§5.3, punto 6): l'app la ritenta prima di ogni sync.
  final bool confermaInSospeso;
  final DateTime abbinatoIl;
  final String? epoca;
  final String? cursore;

  /// Ultima sync riuscita.
  final DateTime? ultimaSync;

  /// Esito dell'ultimo tentativo, se non è riuscito; null se è riuscito.
  final ProblemaSync? problema;
  final DateTime? problemaIl;

  /// Log in attesa di invio.
  final int logInAttesa;

  /// Log rifiutati dal coach, da segnalare all'atleta.
  final int logRifiutati;

  /// L'atleta condivide il proprio peso con questo coach (§8.5).
  final bool condividePesi;

  /// Se il programma del coach riceve i pesi: falso se è di una versione
  /// che non li conosce, null finché nessuna sync lo ha detto.
  final bool? pesiSupportati;

  /// Se il programma del coach riceve i messaggi della chat (§8.7), come
  /// [pesiSupportati].
  final bool? chatSupportata;
}

/// Scheda ricevuta da un coach, in sola lettura (§8.1).
class SchedaRicevuta {
  const SchedaRicevuta({
    required this.coachId,
    required this.id,
    required this.revisione,
    required this.archiviata,
    required this.contenuto,
    required this.ricevutaIl,
    required this.daVedere,
  });

  factory SchedaRicevuta.daRiga(Row r) => SchedaRicevuta(
    coachId: r['coach_id'] as int,
    id: r['id'] as String,
    revisione: r['revisione'] as int,
    archiviata: r['archiviata'] == 1,
    contenuto: jsonDecode(r['contenuto'] as String) as Map<String, Object?>,
    ricevutaIl: leggiIstante(r['ricevuta_il'] as String),
    daVedere: (r['revisione_vista'] as int) < (r['revisione'] as int),
  );

  final int coachId;
  final String id;

  /// Ultima revisione ricevuta: l'app mostra sempre questa.
  final int revisione;

  /// Le schede archiviate stanno nella sezione «Archivio».
  final bool archiviata;

  /// La scheda come l'ha inviata il coach (§8.1).
  final Map<String, Object?> contenuto;

  /// Quando è arrivata questa revisione.
  final DateTime ricevutaIl;

  /// Vero finché l'atleta non ha aperto questa revisione: l'interfaccia
  /// avvisa che ne è arrivata una nuova (§10.2).
  final bool daVedere;

  String get titolo => contenuto['titolo'] as String;
}

/// Campi del log che l'app gestisce da sé (§8.2).
const _campiDiProtocollo = {'id', 'rev', 'eliminato'};

/// [log] senza `id`, `rev` ed `eliminato`, come lo conserva l'archivio.
Map<String, Object?> corpoDelLog(Map<String, Object?> log) =>
    Map<String, Object?>.of(log)
      ..removeWhere((chiave, _) => _campiDiProtocollo.contains(chiave));

/// Allenamento registrato dall'atleta (§8.2).
class LogAllenamento {
  const LogAllenamento({
    required this.coachId,
    required this.id,
    required this.rev,
    required this.revConfermata,
    required this.eliminato,
    required this.contenuto,
    required this.eseguitoIl,
    required this.rifiuto,
  });

  factory LogAllenamento.daRiga(Row r) => LogAllenamento(
    coachId: r['coach_id'] as int,
    id: r['id'] as String,
    rev: r['rev'] as int,
    revConfermata: r['rev_confermata'] as int,
    eliminato: r['eliminato'] == 1,
    contenuto: switch (r['contenuto']) {
      final String testo => jsonDecode(testo) as Map<String, Object?>,
      _ => null,
    },
    eseguitoIl: leggiIstanteFacoltativo(r['eseguito_il']),
    rifiuto: r['rifiuto'] as String?,
  );

  final int coachId;
  final String id;

  /// Cresce a ogni modifica sul telefono.
  final int rev;

  /// Ultima `rev` che il coach ha confermato di avere; 0 se nessuna.
  final int revConfermata;
  final bool eliminato;

  /// Campi del §8.2 senza `id`, `rev` ed `eliminato`; null per un log
  /// eliminato, di cui resta solo la lapide.
  final Map<String, Object?>? contenuto;
  final DateTime? eseguitoIl;

  /// Motivo per cui il coach ha rifiutato questa `rev` (vedi `RifiutoLog`).
  /// Un log rifiutato non viene ritentato in automatico.
  final String? rifiuto;

  /// Vero se il log aspetta di essere inviato.
  bool get inAttesa => rev > revConfermata && rifiuto == null;

  /// Il log come lo invia l'app (§8.2).
  Map<String, Object?> get perProtocollo => {
    'id': id,
    'rev': rev,
    'eliminato': eliminato,
    if (!eliminato) ...?contenuto,
  };
}

/// Risultato di una sync con un coach.
class EsitoSync {
  const EsitoSync({
    required this.coachId,
    this.problema,
    this.completa = false,
    this.logConfermati = 0,
    this.logRifiutati = 0,
    this.logRimessiInCoda = 0,
    this.schedeNuove = const [],
    this.questionariNuovi = const [],
    this.messaggiNuovi = const [],
  });

  final int coachId;

  /// Perché la sync non è riuscita; null se è riuscita.
  final ProblemaSync? problema;

  /// Vero se il coach ha inviato lo stato completo: prima sync, epoca
  /// cambiata.
  final bool completa;
  final int logConfermati;
  final int logRifiutati;

  /// Log che il coach non aveva più, per esempio dopo un ripristino da
  /// backup, rimessi in coda e reinviati (§7.3).
  final int logRimessiInCoda;

  /// Schede nuove o con una nuova revisione, non archiviate. Dopo una sync
  /// in background l'app le annuncia con una notifica locale (§7.4).
  final List<SchedaRicevuta> schedeNuove;

  /// Id dei questionari arrivati con questa sync, da annunciare come le
  /// schede.
  final List<String> questionariNuovi;

  /// Id dei messaggi del coach arrivati con questa sync, da annunciare con
  /// una notifica.
  final List<String> messaggiNuovi;

  bool get riuscita => problema == null;
}
