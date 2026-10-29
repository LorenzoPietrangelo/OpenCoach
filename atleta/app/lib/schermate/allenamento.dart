import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/testi.dart';
import 'avvisi.dart';
import 'contenuto_scheda.dart';
import 'formati.dart';
import 'video_esercizio.dart';

/// Esecuzione di un allenamento (§10.2): le serie partono dalla
/// prescrizione; l'atleta scrive ripetizioni, carico, durata e RPE
/// effettivi, segna le serie fatte, usa il timer di recupero e scrive note.
/// Può aggiungere esercizi non previsti. Al salvataggio il log entra in coda
/// e parte una sync (§7.4).
///
/// La stessa schermata registra un allenamento libero e modifica un log
/// dello storico. Si chiude con true se l'allenamento è stato salvato.
class SchermataAllenamento extends StatefulWidget {
  const SchermataAllenamento({
    super.key,
    required this.nucleo,
    required this.allenamento,
    this.titolo,
    this.seduta,
    this.logId,
  });

  final NucleoAtleta nucleo;
  final AllenamentoInCorso allenamento;

  /// Nome della seduta; null per un allenamento libero.
  final String? titolo;

  /// La seduta della scheda, per mostrare accanto agli esercizi la
  /// prescrizione e le note del coach.
  final Seduta? seduta;

  /// Il log dello storico da modificare; null per un allenamento nuovo.
  final String? logId;

  @override
  State<SchermataAllenamento> createState() => _SchermataAllenamentoState();
}

/// Valori di una serie che l'atleta scrive.
enum _Campo { ripetizioni, durata, carico, rpe }

class _SchermataAllenamentoState extends State<SchermataAllenamento> {
  late final _note = TextEditingController(text: widget.allenamento.note);
  late final _durata = TextEditingController(
    text: widget.allenamento.durataMin?.toString() ?? '',
  );
  late final _coachAttivi = widget.nucleo.collegamenti.attivi();

  /// Esercizi misurati a tempo invece che a ripetizioni.
  final _aTempo = <EsercizioInCorso>{};

  /// Esercizi aperti per registrare le serie; gli altri mostrano solo nome
  /// e prescrizione.
  final _aperti = <EsercizioInCorso>{};

  void _apriOChiudi(EsercizioInCorso esercizio) => setState(
    () => _aperti.remove(esercizio) || _aperti.add(esercizio),
  );

  /// Campi con un valore non valido: finché ce ne sono non si salva.
  final _nonValidi = <(SerieInCorso, _Campo)>{};
  var _durataValida = true;

  /// Ci sono modifiche da salvare: per uscire serve una conferma.
  var _modificato = false;

  /// L'atleta ha cambiato l'inizio, per esempio per registrare un
  /// allenamento di ieri: la durata non va più dall'inizio al salvataggio.
  var _inizioCambiato = false;

  /// Timer di recupero: fine del recupero in corso, oppure recupero appena
  /// finito.
  Timer? _tic;
  DateTime? _fineRecupero;
  var _secondiMostrati = 0;
  var _recuperoFinito = false;

  AllenamentoInCorso get _a => widget.allenamento;

  Orologio get _orologio => widget.nucleo.contesto.orologio;

  @override
  void initState() {
    super.initState();
    _aTempo.addAll(
      _a.esercizi.where((e) => e.serie.any((s) => s.durataS != null)),
    );
    // Un allenamento già registrato si apre per correggerlo: le serie si
    // vedono subito.
    if (widget.logId != null) {
      _aperti.addAll(_a.esercizi);
    } else {
      // Dove c'è un valore dell'ultima volta il campo resta vuoto e lo
      // mostra in grigio, invece del numero preso dalla prescrizione.
      for (final esercizio in _a.esercizi) {
        final precedenti = _ultimaVolta(esercizio);
        for (final (i, serie) in esercizio.serie.indexed) {
          final prima = precedenti.elementAtOrNull(i);
          if (prima == null) continue;
          if (prima.ripetizioni != null) serie.ripetizioni = null;
          if (prima.caricoKg != null) serie.caricoKg = null;
          if (prima.durataS != null) serie.durataS = null;
        }
      }
    }
  }

  /// Le serie fatte l'ultima volta con l'esercizio, per nome e id: se
  /// l'atleta rinomina un esercizio aggiunto, si cercano di nuovo.
  final _precedenti = <(EsercizioInCorso, String), List<SerieFatta>>{};

  List<SerieFatta> _ultimaVolta(EsercizioInCorso esercizio) =>
      _precedenti[(esercizio, esercizio.nome)] ??= widget.nucleo.diario
          .ultimaVolta(
            esercizioId: esercizio.esercizioId,
            nome: esercizio.nome,
            prima: _a.inizio,
          );

  @override
  void dispose() {
    _tic?.cancel();
    _note.dispose();
    _durata.dispose();
    super.dispose();
  }

  void _cambia(VoidCallback modifica) => setState(() {
    modifica();
    _modificato = true;
  });

  void _segnaModificato() {
    if (!_modificato) setState(() => _modificato = true);
  }

  void _valore(SerieInCorso serie, _Campo campo, num? valore, bool valido) =>
      _cambia(() {
        if (!valido) {
          _nonValidi.add((serie, campo));
          return;
        }
        _nonValidi.remove((serie, campo));
        switch (campo) {
          case _Campo.ripetizioni:
            serie.ripetizioni = valore?.toInt();
          case _Campo.durata:
            serie.durataS = valore?.toInt();
          case _Campo.carico:
            serie.caricoKg = valore;
          case _Campo.rpe:
            serie.rpe = valore;
        }
      });

  /// Segna la serie fatta e, se il coach ha previsto un recupero, avvia il
  /// timer. I campi lasciati vuoti prendono i valori dell'ultima volta, che
  /// l'atleta vedeva in grigio.
  void _completa(SerieInCorso serie, SerieFatta? prima, bool fatta) {
    _cambia(() {
      serie.completata = fatta;
      if (!fatta || prima == null) return;
      serie.ripetizioni ??= prima.ripetizioni;
      serie.caricoKg ??= prima.caricoKg;
      serie.durataS ??= prima.durataS;
    });
    final recupero = serie.recupero;
    if (fatta && recupero != null && recupero > Duration.zero) {
      _avviaRecupero(recupero);
    }
  }

  // Timer di recupero. Il tempo che resta si misura sull'orologio, così il
  // timer resta giusto anche se l'app passa un po' in background.

  int get _secondiRestanti {
    final fine = _fineRecupero;
    if (fine == null) return 0;
    final millisecondi = fine.difference(_orologio.adesso()).inMilliseconds;
    return millisecondi <= 0 ? 0 : (millisecondi / 1000).ceil();
  }

  void _avviaRecupero(Duration tempo) {
    _tic?.cancel();
    setState(() {
      _fineRecupero = _orologio.adesso().add(tempo);
      _secondiMostrati = _secondiRestanti;
      _recuperoFinito = false;
    });
    _tic = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _scorreRecupero(),
    );
  }

  void _scorreRecupero() {
    if (!mounted) return;
    final restanti = _secondiRestanti;
    if (restanti > 0) {
      if (restanti != _secondiMostrati) {
        setState(() => _secondiMostrati = restanti);
      }
      return;
    }
    _tic?.cancel();
    _tic = null;
    setState(() {
      _fineRecupero = null;
      _recuperoFinito = true;
    });
    unawaited(HapticFeedback.vibrate());
    unawaited(SystemSound.play(SystemSoundType.alert));
  }

  void _spostaRecupero(Duration differenza) {
    final fine = _fineRecupero;
    if (fine == null) return;
    _fineRecupero = fine.add(differenza);
    _scorreRecupero();
  }

  void _chiudiRecupero() {
    _tic?.cancel();
    _tic = null;
    setState(() {
      _fineRecupero = null;
      _recuperoFinito = false;
    });
  }

  Future<void> _scegliRecupero() async {
    final testi = Testi.of(context);
    final scelta = await showModalBottomSheet<Duration>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                testi.timerRecupero,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final secondi in const [30, 60, 90, 120, 180])
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(durata(Duration(seconds: secondi))),
                onTap: () =>
                    Navigator.of(context).pop(Duration(seconds: secondi)),
              ),
          ],
        ),
      ),
    );
    if (scelta != null && mounted) _avviaRecupero(scelta);
  }

  // Esercizi e serie.

  Future<void> _aggiungiEsercizio() async {
    final testi = Testi.of(context);
    final nome = await _chiediTesto(
      titolo: testi.aggiungiEsercizio,
      etichetta: testi.nomeEsercizio,
      conferma: testi.aggiungi,
      massimo: 200,
    );
    if (nome == null || nome.isEmpty) return;
    // Un esercizio aggiunto si apre: l'atleta lo aggiunge per registrarlo.
    _cambia(() => _aperti.add(_a.aggiungiEsercizio(nome)));
  }

  Future<void> _rinomina(EsercizioInCorso esercizio) async {
    final testi = Testi.of(context);
    final nome = await _chiediTesto(
      titolo: testi.rinomina,
      etichetta: testi.nomeEsercizio,
      conferma: testi.salva,
      iniziale: esercizio.nome,
      massimo: 200,
    );
    if (nome == null || nome.isEmpty) return;
    _cambia(() => esercizio.nome = nome);
  }

  Future<void> _noteEsercizio(EsercizioInCorso esercizio) async {
    final testi = Testi.of(context);
    final note = await _chiediTesto(
      titolo: esercizio.nome,
      etichetta: testi.leTueNote,
      conferma: testi.salva,
      iniziale: esercizio.note,
      massimo: 2000,
      righeMultiple: true,
    );
    if (note == null) return;
    _cambia(() => esercizio.note = note);
  }

  void _togliUltimaSerie(EsercizioInCorso esercizio) => _cambia(() {
    final tolta = esercizio.serie.removeLast();
    _nonValidi.removeWhere((campo) => identical(campo.$1, tolta));
  });

  void _togliEsercizio(EsercizioInCorso esercizio) => _cambia(() {
    _a.esercizi.remove(esercizio);
    _aTempo.remove(esercizio);
    _aperti.remove(esercizio);
    _nonValidi.removeWhere(
      (campo) => esercizio.serie.any((serie) => identical(serie, campo.$1)),
    );
  });

  Future<String?> _chiediTesto({
    required String titolo,
    required String etichetta,
    required String conferma,
    String iniziale = '',
    required int massimo,
    bool righeMultiple = false,
  }) => showDialog<String>(
    context: context,
    builder: (_) => _DialogoTesto(
      titolo: titolo,
      etichetta: etichetta,
      conferma: conferma,
      iniziale: iniziale,
      massimo: massimo,
      righeMultiple: righeMultiple,
    ),
  );

  Future<void> _scegliInizio() async {
    final adesso = _orologio.adesso().toLocal();
    final attuale = _a.inizio.toLocal();
    final giorno = await showDatePicker(
      context: context,
      initialDate: attuale.isAfter(adesso) ? adesso : attuale,
      firstDate: DateTime(2000),
      lastDate: adesso,
    );
    if (giorno == null || !mounted) return;
    final ora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(attuale),
    );
    if (ora == null) return;
    _cambia(() {
      _a.inizio = DateTime(
        giorno.year,
        giorno.month,
        giorno.day,
        ora.hour,
        ora.minute,
      );
      _inizioCambiato = true;
    });
  }

  // Salvataggio e uscita.

  void _salva() {
    final testi = Testi.of(context);
    final messaggi = ScaffoldMessenger.of(context);
    final coachId = _a.coachId;
    if (_nonValidi.isNotEmpty || !_durataValida || coachId == null) {
      // I valori da correggere devono vedersi: si aprono i loro esercizi.
      setState(() {
        for (final esercizio in _a.esercizi) {
          if (esercizio.serie.any(
            (serie) => _nonValidi.any((campo) => identical(campo.$1, serie)),
          )) {
            _aperti.add(esercizio);
          }
        }
      });
      messaggi.avvisa(testi.correggiValori);
      return;
    }
    _a.note = _note.text.trim();
    final logId = widget.logId;
    try {
      if (logId == null) {
        // Senza una durata scritta dall'atleta, va dall'inizio a adesso.
        widget.nucleo.diario.salva(
          coachId,
          _a.contenuto(fine: _inizioCambiato ? null : _orologio.adesso()),
        );
      } else {
        widget.nucleo.diario.modifica(coachId, logId, _a.contenuto());
      }
    } on LogNonValido catch (e) {
      messaggi.avvisa(testi.allenamentoNonValido(e.errori.join('\n')));
      return;
    } on OperazioneNonAmmessa catch (e) {
      messaggi.avvisa(e.messaggio);
      return;
    }
    _tic?.cancel();
    Navigator.of(context).pop(true);
  }

  Future<void> _uscita(bool uscito, bool? _) async {
    if (uscito) return;
    final testi = Testi.of(context);
    final esci = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(testi.uscireSenzaSalvare),
        content: Text(
          widget.logId == null ? testi.allenamentoPerso : testi.modifichePerse,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(testi.resta),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(testi.esci),
          ),
        ],
      ),
    );
    if (esci == true && mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final noteSeduta = widget.seduta?.note ?? '';
    return PopScope<bool>(
      canPop: !_modificato,
      onPopInvokedWithResult: _uscita,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.titolo ??
                (_a.libero ? testi.allenamentoLibero : testi.allenamento),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.timer_outlined),
              tooltip: testi.timerRecupero,
              onPressed: _scegliRecupero,
            ),
            TextButton(onPressed: _salva, child: Text(testi.salva)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            // Per un allenamento libero l'atleta sceglie il coach, se ne ha
            // più di uno (§8.2).
            if (_a.libero && widget.logId == null && _coachAttivi.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: DropdownButtonFormField<int>(
                  initialValue: _a.coachId,
                  decoration: InputDecoration(
                    labelText: testi.coachDellAllenamento,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final coach in _coachAttivi)
                      DropdownMenuItem(
                        value: coach.id,
                        child: Text(coach.nomeCoach),
                      ),
                  ],
                  onChanged: (id) => _cambia(() => _a.coachId = id),
                ),
              ),
            if (noteSeduta.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(noteSeduta, style: tema.bodyMedium),
              ),
            if (_a.esercizi.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(testi.nessunEsercizio),
              ),
            for (final esercizio in _a.esercizi) _esercizio(esercizio),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _aggiungiEsercizio,
                icon: const Icon(Icons.add),
                label: Text(testi.aggiungiEsercizio),
              ),
            ),
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(testi.rpeSeduta, style: tema.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (var valore = 1; valore <= 10; valore++)
                    ChoiceChip(
                      label: Text('$valore'),
                      selected: _a.rpe == valore,
                      onSelected: (scelto) =>
                          _cambia(() => _a.rpe = scelto ? valore : null),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: TextField(
                controller: _note,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(10000)],
                decoration: InputDecoration(
                  labelText: testi.noteAllenamento,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => _segnaModificato(),
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(Icons.event),
              title: Text(testi.inizioAllenamento),
              subtitle: Text(giornoEOra(context, _a.inizio)),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _scegliInizio,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: _durata,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: testi.durataMinuti,
                  border: const OutlineInputBorder(),
                  helperText: widget.logId == null && !_inizioCambiato
                      ? testi.durataAutomatica
                      : null,
                  helperMaxLines: 2,
                  errorText: _durataValida ? null : testi.valoreNonValido,
                ),
                onChanged: (testo) => _cambia(() {
                  try {
                    _a.durataMin = leggiIntero(testo, massimo: 1440);
                    _durataValida = true;
                  } on FormatException {
                    _durataValida = false;
                  }
                }),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _salva,
              icon: const Icon(Icons.check),
              label: Text(testi.salvaAllenamento),
            ),
          ],
        ),
        bottomNavigationBar: _barraRecupero(),
      ),
    );
  }

  Widget _esercizio(EsercizioInCorso esercizio) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final previsto = widget.seduta?.esercizi
        .where((e) => e.id == esercizio.esercizioId)
        .firstOrNull;
    final aTempo = _aTempo.contains(esercizio);
    final conRipetizioni =
        !aTempo || esercizio.serie.any((s) => s.ripetizioni != null);
    final conDurata = aTempo || esercizio.serie.any((s) => s.durataS != null);
    final noteCoach = esercizio.noteCoach.isNotEmpty
        ? esercizio.noteCoach
        : previsto?.note ?? '';
    final aperto = _aperti.contains(esercizio);
    final fatte = esercizio.serie.where((s) => s.completata).length;
    // Chiuso, l'esercizio mostra solo serie, ripetizioni e RIR (§8.1);
    // carico e recupero si vedono aprendolo.
    final riepilogo = previsto == null || previsto.prescrizione.isEmpty
        ? testi.numeroSerie(esercizio.serie.length)
        : [
            for (final riga in previsto.prescrizione)
              testoPrescrizione(
                testi,
                serie: riga.serie,
                ripetizioni: riga.ripetizioni,
                rir: riga.rir,
              ),
          ].where((t) => t.isNotEmpty).join(' + ');
    final dettagli = [
      if (previsto != null)
        for (final riga in previsto.prescrizione)
          testoPrescrizione(
            testi,
            carico: riga.carico,
            recupero: riga.recupero,
          ),
    ].where((t) => t.isNotEmpty);
    return Card(
      key: ObjectKey(esercizio),
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(esercizio.nome, style: tema.titleMedium),
            subtitle: riepilogo.isEmpty ? null : Text(riepilogo),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  testi.serieFatte(fatte, esercizio.serie.length),
                  style: tema.labelMedium,
                ),
                Icon(aperto ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: () => _apriOChiudi(esercizio),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            // Chiuso, l'esercizio tiene vivi i suoi campi: un valore ancora da
            // correggere non si perde.
            child: Visibility(
              visible: aperto,
              maintainState: true,
              replacement: const SizedBox(width: double.infinity),
              child: _registrazione(
                esercizio,
                aTempo: aTempo,
                conRipetizioni: conRipetizioni,
                conDurata: conDurata,
                dettagli: dettagli,
                noteCoach: noteCoach,
                video: previsto?.video,
                aperto: aperto,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// La parte che si apre toccando l'esercizio: carico e recupero previsti,
  /// note, le serie da registrare e il menu dell'esercizio.
  Widget _registrazione(
    EsercizioInCorso esercizio, {
    required bool aTempo,
    required bool conRipetizioni,
    required bool conDurata,
    required Iterable<String> dettagli,
    required String noteCoach,
    required Uri? video,
    required bool aperto,
  }) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final precedenti = _ultimaVolta(esercizio);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final dettaglio in dettagli) Text(dettaglio)],
                ),
              ),
              _menu(esercizio, aTempo),
            ],
          ),
          if (noteCoach.isNotEmpty)
            Text(
              noteCoach,
              style: tema.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
          if (esercizio.note.isNotEmpty)
            Text(testi.tueNote(esercizio.note), style: tema.bodySmall),
          if (video != null) VideoEsercizio(link: video, visibile: aperto),
          const SizedBox(height: 8),
          _colonne(
            numero: Text(testi.serie, style: tema.labelSmall),
            ripetizioni: conRipetizioni
                ? Text(testi.ripetizioniBreve, style: tema.labelSmall)
                : null,
            durata: conDurata
                ? Text(testi.secondiBreve, style: tema.labelSmall)
                : null,
            carico: Text(testi.kg, style: tema.labelSmall),
            rpe: Text(testi.rpe, style: tema.labelSmall),
            fatta: Text(testi.fatta, style: tema.labelSmall),
          ),
          for (final (indice, serie) in esercizio.serie.indexed)
            _serie(
              indice,
              serie,
              precedenti.elementAtOrNull(indice),
              conRipetizioni: conRipetizioni,
              conDurata: conDurata,
            ),
          TextButton.icon(
            onPressed: () => _cambia(esercizio.aggiungiSerie),
            icon: const Icon(Icons.add),
            label: Text(testi.aggiungiSerie),
          ),
        ],
      ),
    );
  }

  Widget _menu(EsercizioInCorso esercizio, bool aTempo) {
    final testi = Testi.of(context);
    return PopupMenuButton<VoidCallback>(
      onSelected: (azione) => azione(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: () => unawaited(_noteEsercizio(esercizio)),
          child: Text(testi.leTueNote),
        ),
        PopupMenuItem(
          value: () => _cambia(
            () => aTempo ? _aTempo.remove(esercizio) : _aTempo.add(esercizio),
          ),
          child: Text(aTempo ? testi.misuraARipetizioni : testi.misuraATempo),
        ),
        if (esercizio.serie.length > 1)
          PopupMenuItem(
            value: () => _togliUltimaSerie(esercizio),
            child: Text(testi.togliUltimaSerie),
          ),
        // Gli esercizi della scheda restano: le serie non fatte dicono al
        // coach che l'esercizio è stato saltato.
        if (!esercizio.previsto) ...[
          PopupMenuItem(
            value: () => unawaited(_rinomina(esercizio)),
            child: Text(testi.rinomina),
          ),
          PopupMenuItem(
            value: () => _togliEsercizio(esercizio),
            child: Text(testi.togliEsercizio),
          ),
        ],
      ],
    );
  }

  /// Una serie da registrare. In grigio, nei campi vuoti, i valori della
  /// stessa serie l'ultima volta ([prima]) o la prescrizione del coach.
  Widget _serie(
    int indice,
    SerieInCorso serie,
    SerieFatta? prima, {
    required bool conRipetizioni,
    required bool conDurata,
  }) {
    String? precedente(num? valore) => valore == null ? null : numero(valore);

    Widget casella(
      _Campo campo,
      num? valore,
      String? suggerimento,
      num? Function(String testo) leggi, {
      bool decimale = false,
    }) => _CampoNumero(
      valore: valore,
      suggerimento: suggerimento ?? '',
      decimale: decimale,
      leggi: leggi,
      nonValido: _nonValidi.contains((serie, campo)),
      onChanged: (valore, valido) => _valore(serie, campo, valore, valido),
    );

    return KeyedSubtree(
      key: ObjectKey(serie),
      child: _colonne(
        numero: Text('${indice + 1}'),
        ripetizioni: conRipetizioni
            ? casella(
                _Campo.ripetizioni,
                serie.ripetizioni,
                precedente(prima?.ripetizioni) ?? serie.obiettivoRipetizioni,
                (testo) => leggiIntero(testo, massimo: 10000),
              )
            : null,
        durata: conDurata
            ? casella(
                _Campo.durata,
                serie.durataS,
                precedente(prima?.durataS) ??
                    (conRipetizioni ? null : serie.obiettivoRipetizioni),
                (testo) => leggiIntero(testo, massimo: 86400),
              )
            : null,
        carico: casella(
          _Campo.carico,
          serie.caricoKg,
          precedente(prima?.caricoKg) ?? serie.obiettivoCarico,
          (testo) => leggiDecimale(testo, massimo: 10000),
          decimale: true,
        ),
        rpe: casella(
          _Campo.rpe,
          serie.rpe,
          null,
          (testo) => leggiDecimale(testo, massimo: 10, passo: 0.5),
          decimale: true,
        ),
        fatta: Checkbox(
          value: serie.completata,
          semanticLabel: Testi.of(context).serieFatta(indice + 1),
          onChanged: (fatta) => _completa(serie, prima, fatta ?? false),
        ),
      ),
    );
  }

  /// Le colonne delle serie, uguali per l'intestazione e per ogni serie.
  /// Ogni colonna ha la sua chiave: se compare o sparisce la durata, i
  /// campi delle altre colonne restano quelli.
  Widget _colonne({
    required Widget numero,
    Widget? ripetizioni,
    Widget? durata,
    required Widget carico,
    required Widget rpe,
    required Widget fatta,
  }) {
    Widget colonna(_Campo campo, Widget figlio) => Expanded(
      key: ValueKey(campo),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: Center(child: figlio),
      ),
    );
    return Row(
      children: [
        SizedBox(width: 36, child: numero),
        if (ripetizioni != null) colonna(_Campo.ripetizioni, ripetizioni),
        if (durata != null) colonna(_Campo.durata, durata),
        colonna(_Campo.carico, carico),
        colonna(_Campo.rpe, rpe),
        SizedBox(width: 48, child: Center(child: fatta)),
      ],
    );
  }

  Widget? _barraRecupero() {
    if (_fineRecupero == null && !_recuperoFinito) return null;
    final testi = Testi.of(context);
    final tema = Theme.of(context);
    final compatto = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(48, 40),
    );
    return Material(
      color: _recuperoFinito
          ? tema.colorScheme.tertiaryContainer
          : tema.colorScheme.secondaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Icon(_recuperoFinito ? Icons.alarm : Icons.timer_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: _recuperoFinito
                    ? Text(
                        testi.recuperoFinito,
                        style: tema.textTheme.titleMedium,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            testi.recupero,
                            style: tema.textTheme.labelSmall,
                          ),
                          Text(
                            durata(Duration(seconds: _secondiMostrati)),
                            style: tema.textTheme.titleLarge,
                          ),
                        ],
                      ),
              ),
              if (!_recuperoFinito) ...[
                TextButton(
                  style: compatto,
                  onPressed: () =>
                      _spostaRecupero(const Duration(seconds: -15)),
                  child: Text(testi.menoQuindiciSecondi),
                ),
                TextButton(
                  style: compatto,
                  onPressed: () => _spostaRecupero(const Duration(seconds: 15)),
                  child: Text(testi.piuQuindiciSecondi),
                ),
              ],
              TextButton(
                style: compatto,
                onPressed: _chiudiRecupero,
                child: Text(_recuperoFinito ? testi.chiudi : testi.salta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Campo numerico di una serie. Il testo resta quello scritto dall'atleta;
/// al genitore arrivano il valore letto o il fatto che il testo non è
/// valido.
class _CampoNumero extends StatefulWidget {
  const _CampoNumero({
    required this.valore,
    required this.suggerimento,
    required this.decimale,
    required this.leggi,
    required this.nonValido,
    required this.onChanged,
  });

  final num? valore;

  /// La prescrizione del coach, come «6-8» o «75% 1RM», finché il campo è
  /// vuoto.
  final String suggerimento;
  final bool decimale;

  /// Il valore del testo, null se è vuoto; lancia [FormatException] se il
  /// testo non è valido.
  final num? Function(String testo) leggi;
  final bool nonValido;
  final void Function(num? valore, bool valido) onChanged;

  @override
  State<_CampoNumero> createState() => _CampoNumeroState();
}

class _CampoNumeroState extends State<_CampoNumero> {
  late final _testo = TextEditingController(
    text: switch (widget.valore) {
      final num valore => numero(valore),
      null => '',
    },
  );

  /// Un valore arrivato da fuori, come quelli dell'ultima volta quando
  /// l'atleta segna la serie fatta, riempie il campo se è vuoto.
  @override
  void didUpdateWidget(_CampoNumero vecchio) {
    super.didUpdateWidget(vecchio);
    final valore = widget.valore;
    if (valore != null && valore != vecchio.valore && _testo.text.isEmpty) {
      _testo.text = numero(valore);
    }
  }

  @override
  void dispose() {
    _testo.dispose();
    super.dispose();
  }

  void _cambiato(String testo) {
    final num? valore;
    try {
      valore = widget.leggi(testo);
    } on FormatException {
      widget.onChanged(null, false);
      return;
    }
    widget.onChanged(valore, true);
  }

  @override
  Widget build(BuildContext context) {
    final errore = BorderSide(
      color: Theme.of(context).colorScheme.error,
      width: 2,
    );
    return TextField(
      controller: _testo,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimale),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        hintText: widget.suggerimento,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        border: const OutlineInputBorder(),
        enabledBorder: widget.nonValido
            ? OutlineInputBorder(borderSide: errore)
            : null,
        focusedBorder: widget.nonValido
            ? OutlineInputBorder(borderSide: errore)
            : null,
      ),
      onChanged: _cambiato,
    );
  }
}

class _DialogoTesto extends StatefulWidget {
  const _DialogoTesto({
    required this.titolo,
    required this.etichetta,
    required this.conferma,
    required this.iniziale,
    required this.massimo,
    required this.righeMultiple,
  });

  final String titolo;
  final String etichetta;
  final String conferma;
  final String iniziale;
  final int massimo;
  final bool righeMultiple;

  @override
  State<_DialogoTesto> createState() => _DialogoTestoState();
}

class _DialogoTestoState extends State<_DialogoTesto> {
  late final _testo = TextEditingController(text: widget.iniziale);

  @override
  void dispose() {
    _testo.dispose();
    super.dispose();
  }

  void _conferma() => Navigator.of(context).pop(_testo.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.titolo),
    content: TextField(
      controller: _testo,
      autofocus: true,
      minLines: 1,
      maxLines: widget.righeMultiple ? 5 : 1,
      textCapitalization: TextCapitalization.sentences,
      inputFormatters: [LengthLimitingTextInputFormatter(widget.massimo)],
      decoration: InputDecoration(labelText: widget.etichetta),
      onSubmitted: widget.righeMultiple ? null : (_) => _conferma(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(Testi.of(context).annulla),
      ),
      FilledButton(onPressed: _conferma, child: Text(widget.conferma)),
    ],
  );
}
