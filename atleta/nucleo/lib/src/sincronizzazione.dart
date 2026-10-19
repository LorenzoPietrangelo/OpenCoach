import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'guasti.dart';
import 'modelli.dart';
import 'problemi.dart';
import 'schede.dart';
import 'tempo.dart';
import 'trasporto.dart';

/// Sincronizzazione con i coach, lato app (§7.3).
///
/// Con lo stesso coach gira una sola operazione per volta: chi chiede una
/// sync mentre un'altra è in corso ottiene la successiva, che parte appena
/// la prima finisce e prende anche i log arrivati nel frattempo. Con coach
/// diversi le sync procedono in parallelo, sull'unica istanza di Tor.
class MotoreSync {
  MotoreSync(
    this._c,
    this._schede, {
    this.logPerRichiesta = Limiti.logPerRichiesta,
    this.budgetRichiesta = budgetPredefinito,
  });

  /// Byte di log per richiesta, sotto il limite di 2 MiB (§6.2).
  static const budgetPredefinito = 1536 * 1024;

  /// Sync consecutive con errori SOCKS F4 o F5 dopo le quali la chiave si
  /// considera non più autorizzata (§7.5).
  static const rifiutiChiaveMassimi = 3;

  /// Per almeno questo tempo dopo l'abbinamento l'app ritenta la conferma,
  /// perché il nuovo descrittore può impiegare qualche minuto a propagarsi
  /// (§5.3, punto 6).
  static const durataConferma = Duration(minutes: 10);

  static const _primaAttesaConferma = Duration(seconds: 15);
  static const _attesaConfermaMassima = Duration(minutes: 2);

  /// Ritentativi della stessa richiesta dopo 429, 503 e 5xx (§6.4).
  static const _ritentativiMassimi = 4;
  static const _primaAttesaErrore = Duration(seconds: 2);

  /// Oltre questa attesa la sync si arrende e riprova all'occasione
  /// successiva.
  static const _attesaMassima = Duration(minutes: 2);

  final ContestoAtleta _c;
  final SchedeRicevute _schede;

  /// Log per richiesta, al massimo 100 (§6.2).
  final int logPerRichiesta;
  final int budgetRichiesta;

  /// Fine dell'ultima operazione in coda per ogni coach.
  final _code = <int, Future<void>>{};

  /// Sync chiesta e non ancora partita: le richieste successive si
  /// aggregano a questa.
  final _inAttesa = <int, Future<EsitoSync>>{};

  final _confermaProlungata = <int>{};

  Database get _db => _c.db;

  /// Vero se una sync o un'altra operazione con il coach è in corso o in
  /// coda.
  bool inCorso(int coachId) => _code.containsKey(coachId);

  bool get occupato => _code.isNotEmpty;

  /// Sincronizza con il coach (§7.3). Non lancia eccezioni: l'esito dice se
  /// è riuscita, e lo stesso esito resta nell'archivio per l'interfaccia
  /// (§7.5).
  ///
  /// Con [dopoAbbinamento] la conferma dell'abbinamento, se manca, si
  /// ritenta per almeno [durataConferma].
  Future<EsitoSync> sincronizza(int coachId, {bool dopoAbbinamento = false}) {
    if (dopoAbbinamento) _confermaProlungata.add(coachId);
    return _inAttesa[coachId] ??= inEsclusiva(coachId, () {
      _inAttesa.remove(coachId);
      return _esegui(
        coachId,
        dopoAbbinamento: _confermaProlungata.remove(coachId),
      );
    });
  }

  /// Sincronizza con tutti i coach attivi, in parallelo.
  Future<List<EsitoSync>> sincronizzaTutti() => Future.wait([
    for (final coach in _c.coachAttivi()) sincronizza(coach.id),
  ]);

  /// Aspetta che finiscano tutte le operazioni in corso o in coda.
  Future<void> attendiTutte() async {
    while (_code.isNotEmpty) {
      await Future.wait(_code.values.toList());
    }
  }

  /// Esegue [operazione] quando nessun'altra operazione con [coachId] è in
  /// corso, e trattiene quelle successive finché non finisce.
  Future<T> inEsclusiva<T>(int coachId, Future<T> Function() operazione) {
    final precedente = _code[coachId] ?? Future<void>.value();
    final fine = Completer<void>();
    _code[coachId] = fine.future;
    return precedente.then((_) => operazione()).whenComplete(() {
      fine.complete();
      if (identical(_code[coachId], fine.future)) _code.remove(coachId);
    });
  }

  Future<EsitoSync> _esegui(
    int coachId, {
    required bool dopoAbbinamento,
  }) async {
    final coach = _c.coach(coachId);
    if (coach == null || coach.stato == StatoCollegamento.scollegato) {
      return EsitoSync(coachId: coachId, problema: ProblemaSync.scollegato);
    }
    if (coach.stato == StatoCollegamento.revocato) {
      return EsitoSync(coachId: coachId, problema: ProblemaSync.revocato);
    }
    final esito = _Esito(coachId);
    try {
      await _sincronizza(coach, esito, dopoAbbinamento: dopoAbbinamento);
      _db.execute(
        'UPDATE coach SET ultima_sync = ?, problema = NULL, problema_il = NULL, '
        'rifiuti_chiave = 0 WHERE id = ?',
        [istante(_c.orologio.adesso()), coachId],
      );
    } on _Fallimento catch (fallimento) {
      esito.problema = await _registraFallimento(coach, fallimento);
    } catch (e, traccia) {
      _c.registra('Errore imprevisto nella sync: $e\n$traccia');
      esito.problema = await _registraFallimento(
        coach,
        const _Fallimento(ProblemaSync.erroreImprevisto),
      );
    }
    _c.segnala(coachId);
    return esito.risultato(_schede);
  }

  Future<void> _sincronizza(
    CoachCollegato coach,
    _Esito esito, {
    required bool dopoAbbinamento,
  }) async {
    // Punto 1: rete e Tor.
    if (!await _c.rete.disponibile()) {
      throw const _Fallimento(ProblemaSync.offline);
    }
    try {
      await _c.tor.avvia();
    } on TorNonParte {
      throw const _Fallimento(ProblemaSync.torNonParte);
    }
    final credenziali = await _c.credenziali(coach.id);
    if (credenziali == null ||
        credenziali.dispositivoId != coach.dispositivoId) {
      // Chiave e token non passano ai backup del telefono (§4): un archivio
      // ripristinato senza di loro va riabbinato.
      throw const _Fallimento(ProblemaSync.chiaveNonAccettata);
    }
    await _c.assicuraChiave(coach.indirizzo, credenziali.chiave);
    final canale = _Canale(_c, coach.indirizzo, credenziali.token);
    try {
      if (coach.confermaInSospeso) {
        await _conferma(coach, canale, prolungata: dopoAbbinamento);
      }
      await _scambia(coach, canale, esito);
    } on _Fallimento {
      rethrow;
    } catch (e, traccia) {
      throw _fallimento(e, traccia);
    } finally {
      canale.chiudi();
    }
  }

  /// `POST /v1/abbinamento/conferma` (§5.3, punto 6). Con [prolungata], se
  /// il coach non si raggiunge, ritenta con attesa crescente per almeno
  /// [durataConferma]; altrimenti un tentativo per sync.
  Future<void> _conferma(
    CoachCollegato coach,
    _Canale canale, {
    required bool prolungata,
  }) async {
    final inizio = _c.orologio.adesso();
    var attesa = _primaAttesaConferma;
    while (true) {
      try {
        await _conRitentativi(canale.api.confermaAbbinamento);
        _db.execute('UPDATE coach SET conferma_in_sospeso = 0 WHERE id = ?', [
          coach.id,
        ]);
        return;
      } catch (e) {
        final tipo = classifica(e)?.tipo;
        final diRete =
            tipo == TipoGuasto.irraggiungibile ||
            tipo == TipoGuasto.chiaveRifiutata;
        final trascorso = _c.orologio.adesso().difference(inizio);
        if (!prolungata || !diRete || trascorso >= durataConferma) rethrow;
        await _c.orologio.attendi(attesa);
        attesa = attesa * 2 > _attesaConfermaMassima
            ? _attesaConfermaMassima
            : attesa * 2;
        if (tipo == TipoGuasto.chiaveRifiutata) {
          // Tor può avere in cache il descrittore pubblicato prima della
          // chiave del dispositivo: il riavvio lo scarta.
          await _c.tor.riavvia();
          canale.rinnova();
        }
      }
    }
  }

  /// Punti 2–5 del §7.3.
  Future<void> _scambia(
    CoachCollegato coach,
    _Canale canale,
    _Esito esito,
  ) async {
    var epoca = coach.epoca;
    var cursore = coach.cursore;
    var massimo = logPerRichiesta;
    while (true) {
      // Punto 2: fino a 100 log dalla coda.
      final lotto = _lotto(coach.id, massimo);
      final RispostaSync prima;
      try {
        // Punto 3.
        prima = await _chiama(canale, epoca, cursore, lotto);
      } on ErroreApi catch (e) {
        if (e.stato != 413 || lotto.isEmpty) rethrow;
        // Richiesta oltre i limiti del coach: si divide il lotto (§6.4).
        if (lotto.length > 1) {
          massimo = lotto.length ~/ 2;
        } else {
          _segnaRifiutato(coach.id, lotto.single, RifiutoLog.troppoGrande);
          esito.rifiutati++;
        }
        continue;
      }

      final inviati = {for (final log in lotto) log.id: log.rev};
      var progressi = 0;
      _Accumulo? accumulo;
      var risposta = prima;
      while (true) {
        _verifica(risposta);
        final pagina = risposta;
        if (pagina.completo) {
          // Lo stato completo si accumula e si applica tutto insieme dopo
          // l'ultima pagina. Se il coach cambia epoca a metà, ricomincia.
          if (accumulo == null || accumulo.epoca != pagina.epoca) {
            accumulo = _Accumulo(pagina.epoca);
          }
          final completo = accumulo..aggiungi(pagina);
          progressi += _c.archivio.transazione(() {
            final esiti = _applicaEsitiLog(coach.id, pagina, inviati, esito);
            if (!pagina.altro) {
              _applicaCompleto(coach.id, completo, pagina.cursore, esito);
            }
            return esiti;
          });
        } else {
          if (accumulo != null) {
            throw const FormatException(
              'Pagina incrementale durante lo stato completo',
            );
          }
          // Punto 4: un'unica transazione locale.
          progressi += _c.archivio.transazione(() {
            final esiti = _applicaEsitiLog(coach.id, pagina, inviati, esito);
            _applicaIncrementale(coach.id, pagina, esito);
            return esiti;
          });
        }
        epoca = pagina.epoca;
        cursore = pagina.cursore;
        if (!pagina.altro) break;
        // Le pagine successive si chiedono con il nuovo cursore e senza log
        // (§6.3).
        inviati.clear();
        risposta = await _chiama(canale, epoca, cursore, const []);
      }
      _c.segnala(coach.id);

      // Punto 5: se restano log in coda si torna al punto 2.
      if (!_ciSonoInCoda(coach.id)) return;
      if (lotto.isNotEmpty && progressi == 0) {
        _c.registra('Il coach non ha confermato né rifiutato i log inviati');
        return;
      }
    }
  }

  Future<RispostaSync> _chiama(
    _Canale canale,
    String? epoca,
    String? cursore,
    List<LogAllenamento> lotto,
  ) => _conRitentativi(
    () => canale.api.sincronizza(
      RichiestaSync(
        epoca: epoca,
        cursore: cursore,
        log: [for (final log in lotto) log.perProtocollo],
        versioneApp: _c.versioneApp,
      ),
    ),
  );

  /// Esegue [chiamata] ritentando dopo 429 e 503 secondo `Retry-After` e
  /// dopo gli altri 5xx con attesa crescente (§6.4).
  Future<T> _conRitentativi<T>(Future<T> Function() chiamata) async {
    var attesa = _primaAttesaErrore;
    for (var tentativo = 0; ; tentativo++) {
      try {
        return await chiamata();
      } on ErroreApi catch (e) {
        final limite = e.stato == 429 || e.stato == 503;
        if ((!limite && e.stato < 500) || tentativo >= _ritentativiMassimi) {
          rethrow;
        }
        final pausa = limite ? e.riprovaTra ?? attesa : attesa;
        if (pausa > _attesaMassima) rethrow;
        await _c.orologio.attendi(pausa);
        attesa *= 2;
      }
    }
  }

  /// Log in coda per una richiesta: al massimo [massimo] e [budgetRichiesta]
  /// byte, ma sempre almeno uno se la coda non è vuota.
  List<LogAllenamento> _lotto(int coachId, int massimo) {
    final lotto = <LogAllenamento>[];
    var byte = 0;
    for (final riga in _db.select(
      'SELECT * FROM log WHERE coach_id = ? AND $condizioneInCoda '
      'ORDER BY rowid LIMIT ?',
      [coachId, massimo],
    )) {
      final log = LogAllenamento.daRiga(riga);
      final dimensione = dimensioneJson(log.perProtocollo);
      if (lotto.isNotEmpty && byte + dimensione > budgetRichiesta) break;
      lotto.add(log);
      byte += dimensione;
    }
    return lotto;
  }

  bool _ciSonoInCoda(int coachId) => _db.select(
    'SELECT 1 FROM log WHERE coach_id = ? AND $condizioneInCoda LIMIT 1',
    [coachId],
  ).isNotEmpty;

  /// Controlla che la risposta si possa salvare così com'è. Se non è
  /// conforme al protocollo non si applica nulla: meglio fermarsi che
  /// salvare dati che l'interfaccia non sa mostrare.
  void _verifica(RispostaSync r) {
    if (r.epoca.isEmpty ||
        r.epoca.length > 100 ||
        r.cursore.isEmpty ||
        r.cursore.length > 1000) {
      throw const FormatException('Epoca o cursore non validi');
    }
    for (final scheda in r.schede) {
      final errori = validaScheda(scheda);
      if (errori.isNotEmpty) {
        throw FormatException('Scheda non valida: ${errori.first}');
      }
    }
    if (!r.schedeEliminate.every(uuidValido)) {
      throw const FormatException('Id di scheda eliminata non valido');
    }
    for (final log in r.log) {
      final errori = validaLog(log);
      if (errori.isNotEmpty) {
        throw FormatException('Log non valido: ${errori.first}');
      }
    }
  }

  /// Log confermati e rifiutati nella risposta; restituisce quanti dei log
  /// inviati hanno avuto un esito.
  int _applicaEsitiLog(
    int coachId,
    RispostaSync r,
    Map<String, int> inviati,
    _Esito esito,
  ) {
    var progressi = 0;
    for (final confermato in r.logAccettati) {
      final rev = inviati[confermato.id];
      if (rev == null || rev != confermato.rev) continue;
      progressi++;
      // Solo se la rev locale è ancora quella inviata (punto 4): un log
      // modificato nel frattempo resta in coda.
      _db.execute(
        'UPDATE log SET rev_confermata = ? '
        'WHERE coach_id = ? AND id = ? AND rev = ? AND rev_confermata < ?',
        [rev, coachId, confermato.id, rev, rev],
      );
      if (_db.updatedRows > 0) esito.confermati++;
    }
    for (final rifiutato in r.logRifiutati) {
      final rev = inviati[rifiutato.id];
      if (rev == null) continue;
      progressi++;
      final motivo = rifiutato.errore.length > 50
          ? rifiutato.errore.substring(0, 50)
          : rifiutato.errore;
      _db.execute(
        'UPDATE log SET rifiuto = ? '
        'WHERE coach_id = ? AND id = ? AND rev = ? AND rifiuto IS NULL',
        [motivo, coachId, rifiutato.id, rev],
      );
      if (_db.updatedRows > 0) esito.rifiutati++;
    }
    return progressi;
  }

  void _segnaRifiutato(int coachId, LogAllenamento log, String motivo) =>
      _db.execute(
        'UPDATE log SET rifiuto = ? WHERE coach_id = ? AND id = ? AND rev = ?',
        [motivo, coachId, log.id, log.rev],
      );

  /// Risposta incrementale (punto 4): schede nuove o cambiate, schede
  /// eliminate, nuovo cursore.
  void _applicaIncrementale(int coachId, RispostaSync r, _Esito esito) {
    final ora = istante(_c.orologio.adesso());
    for (final scheda in r.schede) {
      _salvaScheda(coachId, scheda, ora, esito);
    }
    for (final id in r.schedeEliminate) {
      _db.execute('DELETE FROM schede WHERE coach_id = ? AND id = ?', [
        coachId,
        id,
      ]);
      esito.schedeNuove.remove(id);
    }
    _salvaPosizione(coachId, r.epoca, r.cursore);
  }

  /// Stato completo, dopo l'ultima pagina (§7.3).
  void _applicaCompleto(
    int coachId,
    _Accumulo completo,
    String cursore,
    _Esito esito,
  ) {
    esito.completa = true;
    final ora = istante(_c.orologio.adesso());

    // L'insieme delle schede ricevuto sostituisce quello locale.
    for (final riga in _db.select('SELECT id FROM schede WHERE coach_id = ?', [
      coachId,
    ])) {
      if (!completo.schede.containsKey(riga['id'])) {
        _db.execute('DELETE FROM schede WHERE coach_id = ? AND id = ?', [
          coachId,
          riga['id'],
        ]);
      }
    }
    for (final scheda in completo.schede.values) {
      _salvaScheda(coachId, scheda, ora, esito);
    }

    final locali = {
      for (final riga in _db.select(
        'SELECT id, rev, rev_confermata FROM log WHERE coach_id = ?',
        [coachId],
      ))
        riga['id'] as String: (
          rev: riga['rev'] as int,
          confermata: riga['rev_confermata'] as int,
        ),
    };
    for (final log in completo.log.values) {
      final id = log['id'] as String;
      final rev = log['rev'] as int;
      final locale = locali[id];
      if (locale == null || locale.rev < rev) {
        // Inserisce i log che non ha e prende la versione del coach se ha
        // rev maggiore.
        _salvaVersioneDelCoach(coachId, log);
      } else {
        // Il coach ha questa rev; se quella locale è maggiore il log resta
        // o torna in coda.
        _db.execute(
          'UPDATE log SET rev_confermata = ? WHERE coach_id = ? AND id = ?',
          [rev, coachId, id],
        );
        if (locale.rev > rev && locale.confermata >= locale.rev) {
          esito.rimessiInCoda++;
        }
      }
    }
    // Rimette in coda i log che il coach non ha: dopo un ripristino da
    // backup i telefoni reinviano quelli arrivati dopo.
    for (final MapEntry(key: id, value: locale) in locali.entries) {
      if (completo.log.containsKey(id)) continue;
      _db.execute(
        'UPDATE log SET rev_confermata = 0 WHERE coach_id = ? AND id = ?',
        [coachId, id],
      );
      if (locale.confermata >= locale.rev) esito.rimessiInCoda++;
    }
    _salvaPosizione(coachId, completo.epoca, cursore);
  }

  void _salvaScheda(
    int coachId,
    Map<String, Object?> scheda,
    String ora,
    _Esito esito,
  ) {
    final id = scheda['id'] as String;
    final revisione = scheda['revisione'] as int;
    final archiviata = scheda['stato'] == 'archiviata';
    final precedente =
        _db.select(
              'SELECT revisione FROM schede WHERE coach_id = ? AND id = ?',
              [coachId, id],
            ).firstOrNull?['revisione']
            as int?;
    _db.execute(
      'INSERT INTO schede (coach_id, id, revisione, archiviata, contenuto, '
      'ricevuta_il) VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (coach_id, id) DO UPDATE SET '
      'archiviata = excluded.archiviata, contenuto = excluded.contenuto, '
      'ricevuta_il = CASE WHEN revisione = excluded.revisione '
      'THEN ricevuta_il ELSE excluded.ricevuta_il END, '
      'revisione = excluded.revisione',
      [coachId, id, revisione, archiviata ? 1 : 0, jsonEncode(scheda), ora],
    );
    if (archiviata) {
      esito.schedeNuove.remove(id);
    } else if (precedente == null || revisione > precedente) {
      esito.schedeNuove.add(id);
    }
  }

  void _salvaVersioneDelCoach(int coachId, Map<String, Object?> log) {
    final rev = log['rev'] as int;
    final eliminato = log['eliminato'] == true;
    _db.execute(
      'INSERT INTO log (coach_id, id, rev, rev_confermata, eliminato, '
      'contenuto, eseguito_il) VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (coach_id, id) DO UPDATE SET rev = excluded.rev, '
      'rev_confermata = excluded.rev_confermata, '
      'eliminato = excluded.eliminato, contenuto = excluded.contenuto, '
      'eseguito_il = excluded.eseguito_il, rifiuto = NULL',
      [
        coachId,
        log['id'],
        rev,
        rev,
        eliminato ? 1 : 0,
        eliminato ? null : jsonEncode(corpoDelLog(log)),
        eliminato ? null : istante(analizzaDataOra(log['eseguito_il'])!),
      ],
    );
  }

  void _salvaPosizione(int coachId, String epoca, String cursore) =>
      _db.execute('UPDATE coach SET epoca = ?, cursore = ? WHERE id = ?', [
        epoca,
        cursore,
        coachId,
      ]);

  _Fallimento _fallimento(Object errore, StackTrace traccia) {
    final guasto = classifica(errore);
    switch (guasto?.tipo) {
      case null:
        _c.registra('Errore imprevisto nella sync: $errore\n$traccia');
        return const _Fallimento(ProblemaSync.erroreImprevisto);
      case TipoGuasto.irraggiungibile:
        return const _Fallimento(ProblemaSync.coachIrraggiungibile);
      case TipoGuasto.chiaveRifiutata:
        return const _Fallimento(
          ProblemaSync.coachIrraggiungibile,
          chiaveRifiutata: true,
        );
      case TipoGuasto.protocollo:
        _c.registra('Risposta del coach non conforme al protocollo: $errore');
        return const _Fallimento(
          ProblemaSync.erroreImprevisto,
          rispostaRicevuta: true,
        );
      case TipoGuasto.risposta:
        final problema = switch (guasto!.errore!.stato) {
          401 => ProblemaSync.revocato,
          426 => ProblemaSync.aggiornaApp,
          429 || >= 500 => ProblemaSync.coachOccupato,
          _ => ProblemaSync.erroreImprevisto,
        };
        if (problema == ProblemaSync.erroreImprevisto) {
          _c.registra('Risposta inattesa del coach: $errore');
        }
        return _Fallimento(problema, rispostaRicevuta: true);
    }
  }

  /// Salva l'esito per l'interfaccia (§7.5) e restituisce il problema da
  /// mostrare.
  Future<ProblemaSync> _registraFallimento(
    CoachCollegato coach,
    _Fallimento fallimento,
  ) async {
    var problema = fallimento.problema;
    final revocato = _c.archivio.transazione(() {
      final riga = _db.select('SELECT rifiuti_chiave FROM coach WHERE id = ?', [
        coach.id,
      ]).firstOrNull;
      var rifiuti = riga == null ? 0 : riga['rifiuti_chiave'] as int;
      // F4 e F5 contano solo se si ripetono: dopo una ripubblicazione del
      // servizio Tor può avere in cache il descrittore precedente. Una
      // risposta HTTP, di qualunque tipo, prova che la chiave funziona.
      if (fallimento.chiaveRifiutata) {
        rifiuti++;
        if (rifiuti >= rifiutiChiaveMassimi) {
          problema = ProblemaSync.chiaveNonAccettata;
        }
      } else if (fallimento.rispostaRicevuta) {
        rifiuti = 0;
      }
      _db.execute(
        'UPDATE coach SET problema = ?, problema_il = ?, rifiuti_chiave = ? '
        'WHERE id = ?',
        [problema.name, istante(_c.orologio.adesso()), rifiuti, coach.id],
      );
      if (problema != ProblemaSync.revocato) return false;
      _db.execute(
        "UPDATE coach SET stato = 'revocato' WHERE id = ? AND stato = 'attivo'",
        [coach.id],
      );
      return _db.updatedRows > 0;
    });
    if (revocato) {
      // La sync con questo coach è sospesa (§6.4): chiave e token non servono
      // più. Schede e log restano consultabili.
      await _c.eliminaCredenziali(coach.id);
      await _c.rimuoviChiaveSeInutile(coach.indirizzo);
    }
    return problema;
  }
}

/// Sync interrotta, con il problema da mostrare.
class _Fallimento implements Exception {
  const _Fallimento(
    this.problema, {
    this.chiaveRifiutata = false,
    this.rispostaRicevuta = false,
  });

  final ProblemaSync problema;

  /// Errore SOCKS F4 o F5.
  final bool chiaveRifiutata;

  /// Il programma del coach ha risposto: Tor e la chiave funzionano.
  final bool rispostaRicevuta;
}

/// Client HTTP verso un coach attraverso Tor. Dopo un riavvio di Tor va
/// rinnovato: le connessioni aperte non valgono più.
class _Canale {
  _Canale(this._c, this._indirizzo, this._token) {
    rinnova();
  }

  final ContestoAtleta _c;
  final String _indirizzo;
  final String _token;
  HttpClient? _http;
  late ClienteApi api;

  void rinnova() {
    _http?.close(force: true);
    final http = _http = _c.tor.creaHttpClient();
    api = ClienteApi(indirizzo: _indirizzo, http: http, token: _token);
  }

  void chiudi() => _http?.close(force: true);
}

/// Pagine di uno stato completo, da applicare insieme dopo l'ultima.
class _Accumulo {
  _Accumulo(this.epoca);

  final String epoca;
  final schede = <String, Map<String, Object?>>{};
  final log = <String, Map<String, Object?>>{};

  void aggiungi(RispostaSync pagina) {
    for (final scheda in pagina.schede) {
      schede[scheda['id'] as String] = scheda;
    }
    for (final voce in pagina.log) {
      log[voce['id'] as String] = voce;
    }
  }
}

class _Esito {
  _Esito(this.coachId);

  final int coachId;
  ProblemaSync? problema;
  var completa = false;
  var confermati = 0;
  var rifiutati = 0;
  var rimessiInCoda = 0;
  final schedeNuove = <String>{};

  EsitoSync risultato(SchedeRicevute schede) => EsitoSync(
    coachId: coachId,
    problema: problema,
    completa: completa,
    logConfermati: confermati,
    logRifiutati: rifiutati,
    logRimessiInCoda: rimessiInCoda,
    schedeNuove: [for (final id in schedeNuove) ?schede.cerca(coachId, id)],
  );
}
