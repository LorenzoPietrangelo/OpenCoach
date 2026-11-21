import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../l10n/testi.dart';
import '../tema.dart';
import '../piattaforma/suono.dart';
import '../piattaforma/video.dart';
import 'avvisi.dart';
import 'contenuto_scheda.dart';
import 'formati.dart';
import 'video_esercizio.dart';

/// Esecuzione di un allenamento (§10.2): le serie partono dalla
/// prescrizione; l'atleta scrive ripetizioni, carico e, per gli esercizi a
/// tempo, la durata della serie: una serie compilata conta come fatta. Quando
/// la lascia parte il timer di recupero, e può scrivere note. Sforzo percepito
/// e durata dell'allenamento non si
/// chiedono più: restano solo nei log che li avevano già.
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
    this.noteScheda = '',
    this.logId,
    this.preparaVideo = preparaVideoDalTelefono,
  });

  final NucleoAtleta nucleo;
  final AllenamentoInCorso allenamento;

  /// Nome della seduta; null per un allenamento libero.
  final String? titolo;

  /// La seduta della scheda, per mostrare accanto agli esercizi la
  /// prescrizione e le note del coach.
  final Seduta? seduta;

  /// Le note del coach sulla scheda: aprendo la scheda si arriva qui
  /// direttamente, e altrimenti non si vedrebbero.
  final String noteScheda;

  /// Il log dello storico da modificare; null per un allenamento nuovo.
  final String? logId;

  /// Registra o sceglie il video di una serie (§8.7).
  final PreparaVideo preparaVideo;

  @override
  State<SchermataAllenamento> createState() => _SchermataAllenamentoState();
}

/// Valori di una serie che l'atleta scrive.
enum _Campo { ripetizioni, durata, carico }

class _SchermataAllenamentoState extends State<SchermataAllenamento> {
  late final _note = TextEditingController(text: widget.allenamento.note);
  late final _coachAttivi = widget.nucleo.collegamenti.attivi();

  /// Esercizi misurati a tempo invece che a ripetizioni.
  final _aTempo = <EsercizioInCorso>{};

  /// Esercizi aperti per registrare le serie; gli altri mostrano solo nome
  /// e prescrizione.
  final _aperti = <EsercizioInCorso>{};

  void _apriOChiudi(EsercizioInCorso esercizio) => setState(
    () => _aperti.remove(esercizio) || _aperti.add(esercizio),
  );

  /// Gli esercizi previsti già conclusi: chiusi una volta, se l'atleta li
  /// riapre restano aperti finché non li chiude lui.
  final _conclusi = <EsercizioInCorso>{};

  /// L'esercizio aperto dopo uno concluso: finita l'animazione, la lista lo
  /// porta in vista.
  EsercizioInCorso? _daMostrare;

  final _chiavi = <EsercizioInCorso, GlobalKey>{};

  GlobalKey _chiave(EsercizioInCorso esercizio) =>
      _chiavi.putIfAbsent(esercizio, () => GlobalObjectKey(esercizio));

  static bool _concluso(EsercizioInCorso esercizio) =>
      esercizio.serie.isNotEmpty && esercizio.serie.every((s) => s.completata);

  /// Lasciata una serie: se con lei l'esercizio previsto è concluso, si
  /// chiude e si apre il prossimo non ancora concluso. Gli esercizi aggiunti
  /// dall'atleta non hanno serie previste e restano aperti.
  void _forseProssimo(SerieInCorso serie) {
    final esercizio = _a.esercizi.where((e) => e.serie.contains(serie)).firstOrNull;
    if (esercizio == null || !esercizio.previsto) return;
    if (!_concluso(esercizio)) {
      _conclusi.remove(esercizio);
      return;
    }
    if (!_conclusi.add(esercizio)) return;
    final dopo = _a.esercizi.skip(_a.esercizi.indexOf(esercizio) + 1);
    final prossimo = dopo.where((e) => !_concluso(e)).firstOrNull;
    setState(() {
      _aperti.remove(esercizio);
      if (prossimo != null) {
        _aperti.add(prossimo);
        _daMostrare = prossimo;
      }
    });
  }

  void _mostraSeServe(EsercizioInCorso esercizio) {
    if (_daMostrare != esercizio) return;
    _daMostrare = null;
    final contesto = _chiave(esercizio).currentContext;
    final oggetto = contesto?.findRenderObject();
    if (contesto == null || oggetto == null) return;
    final viewport = RenderAbstractViewport.maybeOf(oggetto);
    final posizione = Scrollable.maybeOf(contesto)?.position;
    if (viewport == null || posizione == null) return;
    // Si scorre solo quanto basta: l'esercizio intero se ci sta, altrimenti
    // il suo inizio in cima. Se si vede già tutto, la lista resta ferma.
    final inCima = viewport.getOffsetToReveal(oggetto, 0).offset;
    final inFondo = viewport.getOffsetToReveal(oggetto, 1).offset;
    final meta = math
        .min(math.max(posizione.pixels, inFondo), inCima)
        .clamp(posizione.minScrollExtent, posizione.maxScrollExtent);
    if ((meta - posizione.pixels).abs() < 1) return;
    unawaited(
      posizione.animateTo(
        meta,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// Campi con un valore non valido: finché ce ne sono non si salva.
  final _nonValidi = <(SerieInCorso, _Campo)>{};

  /// Ci sono modifiche da salvare: per uscire serve una conferma.
  var _modificato = false;

  /// Video delle serie, già compressi: al salvataggio partono per il coach
  /// nella chat, ciascuno con l'esercizio e il numero della serie.
  final _video = <SerieInCorso, VideoPreparato>{};
  var _preparoVideo = false;

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
      _a.esercizi.where((e) => e.serie.any((s) => s.durataS != null || s.obiettivoDurataS != null)),
    );
    // Un allenamento già registrato si apre per correggerlo: le serie si
    // vedono subito.
    if (widget.logId != null) _aperti.addAll(_a.esercizi);
    _conclusi.addAll(_a.esercizi.where(_concluso));
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
    // I video non partiti: allenamento non salvato, serie tolte.
    for (final video in _video.values) {
      _cancella(video.percorso);
    }
    super.dispose();
  }

  void _cancella(String percorso) {
    try {
      File(percorso).deleteSync();
    } on FileSystemException {
      // Già passato alla chat, o già cancellato.
    }
  }

  /// Registra, sceglie, sostituisce o toglie il video della serie.
  Future<void> _videoSerie(int indice, SerieInCorso serie) async {
    final testi = Testi.of(context);
    final messaggi = ScaffoldMessenger.of(context);
    final presente = _video[serie];
    final scelta = await showModalBottomSheet<OrigineVideo?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(testi.videoSerieSpiegazione(indice + 1, durataMassimaVideoS)),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(testi.registraVideo),
              onTap: () => Navigator.of(context).pop(OrigineVideo.fotocamera),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: Text(testi.videoDallaGalleria),
              onTap: () => Navigator.of(context).pop(OrigineVideo.galleria),
            ),
            if (presente != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(testi.togliVideo),
                onTap: () {
                  Navigator.of(context).pop();
                  _cancella(presente.percorso);
                  _cambia(() => _video.remove(serie));
                },
              ),
          ],
        ),
      ),
    );
    if (scelta == null || !mounted) return;
    setState(() => _preparoVideo = true);
    try {
      final video = await widget.preparaVideo(scelta);
      if (video == null || !mounted) return;
      if (_video[serie] case final vecchio?) _cancella(vecchio.percorso);
      _cambia(() => _video[serie] = video);
    } on VideoTroppoLungo catch (e) {
      messaggi.avvisa(testi.videoTroppoLungo(e.massimoS));
    } catch (e) {
      messaggi.avvisa(testi.videoNonPreparato('$e'));
    } finally {
      if (mounted) setState(() => _preparoVideo = false);
    }
  }

  /// Manda alla chat i video delle serie del log appena salvato.
  void _mandaVideo(int coachId, String logId) {
    for (final esercizio in _a.esercizi) {
      for (final (indice, serie) in esercizio.serie.indexed) {
        final video = _video.remove(serie);
        if (video == null) continue;
        try {
          widget.nucleo.chat.allegaVideo(
            coachId,
            file: video.percorso,
            durataS: video.durataS,
            logId: logId,
            esercizio: esercizio.nome,
            serie: indice + 1,
          );
        } on Object catch (e) {
          widget.nucleo.contesto.registra('Video della serie non allegato: $e');
          _cancella(video.percorso);
        }
      }
    }
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
        }
      });

  /// Le serie per cui il recupero è già partito: correggerle non lo rifà.
  final _recuperate = <SerieInCorso>{};

  /// L'atleta ha lasciato una serie, passando a un'altra o chiudendo la
  /// tastiera: se l'ha compilata e il coach ha previsto un recupero, parte il
  /// timer.
  void _serieLasciata(SerieInCorso serie) {
    if (!mounted) return;
    _forseProssimo(serie);
    final recupero = serie.recupero;
    if (!serie.completata || recupero == null || recupero <= Duration.zero) return;
    if (_recuperate.add(serie)) _avviaRecupero(recupero);
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
    unawaited(suonaFineRecupero());
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
    });
  }

  // Salvataggio e uscita.

  void _salva() {
    final testi = Testi.of(context);
    final messaggi = ScaffoldMessenger.of(context);
    final coachId = _a.coachId;
    if (_nonValidi.isNotEmpty || coachId == null) {
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
      final salvato = logId == null
          ? widget.nucleo.diario.salva(coachId, _a.contenuto())
          : widget.nucleo.diario.modifica(coachId, logId, _a.contenuto());
      _mandaVideo(coachId, salvato.id);
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
          ],
          bottom: _preparoVideo
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(24),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Text(testi.preparoVideo, style: tema.labelMedium),
                        const SizedBox(width: 12),
                        const Expanded(child: LinearProgressIndicator()),
                      ],
                    ),
                  ),
                )
              : null,
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
            if (widget.noteScheda.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(widget.noteScheda, style: tema.bodyMedium),
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
            for (final (indice, esercizio) in _a.esercizi.indexed)
              _esercizio(esercizio, indice),
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
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _preparoVideo ? null : _salva,
              icon: const Icon(Icons.check),
              label: Text(testi.salvaAllenamento),
            ),
          ],
        ),
        bottomNavigationBar: _barraRecupero(),
      ),
    );
  }

  Widget _esercizio(EsercizioInCorso esercizio, int indice) {
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
    // Chiuso, l'esercizio mostra serie, ripetizioni, recupero e RIR (§8.1);
    // il carico si vede aprendolo.
    final riepilogo = previsto == null || previsto.prescrizione.isEmpty
        ? testi.numeroSerie(esercizio.serie.length)
        : [
            for (final riga in previsto.prescrizione)
              testoPrescrizione(
                testi,
                serie: riga.serie,
                ripetizioni: riga.ripetizioni,
                recupero: riga.recupero,
                rir: riga.rir,
              ),
          ].where((t) => t.isNotEmpty).join(' + ');
    final dettagli = [
      if (previsto != null)
        for (final riga in previsto.prescrizione)
          testoPrescrizione(testi, carico: riga.carico),
    ].where((t) => t.isNotEmpty);
    final colori = Theme.of(context).colorScheme;
    return Card(
      key: _chiave(esercizio),
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: aperto
            ? BorderSide(color: colori.primary, width: 1.5)
            : const BorderSide(color: ColoriAtleta.bordo),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
            leading: _NumeroEsercizio(
              indice + 1,
              concluso: _concluso(esercizio),
              aperto: aperto,
            ),
            title: Text(
              esercizio.nome,
              style: aperto
                  ? tema.titleMedium?.copyWith(fontWeight: FontWeight.w700)
                  : tema.titleMedium,
            ),
            subtitle: riepilogo.isEmpty ? null : Text(riepilogo),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  testi.serieFatte(fatte, esercizio.serie.length),
                  style: tema.labelLarge?.copyWith(
                    color: fatte > 0 ? colori.primary : colori.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  aperto ? Icons.expand_less : Icons.expand_more,
                  color: colori.onSurfaceVariant,
                ),
              ],
            ),
            onTap: () => _apriOChiudi(esercizio),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            onEnd: () => _mostraSeServe(esercizio),
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

  /// La parte che si apre toccando l'esercizio: il carico previsto,
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
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final dettaglio in dettagli) Text(dettaglio),
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
            onPressed: () => _cambia(() {
              esercizio.aggiungiSerie();
              _conclusi.remove(esercizio);
            }),
            icon: const Icon(Icons.add),
            label: Text(testi.aggiungiSerie),
          ),
        ],
      ),
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

    return Focus(
      key: ObjectKey(serie),
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (dentro) {
        if (!dentro) _serieLasciata(serie);
      },
      child: _colonne(
        fatta: serie.completata,
        numero: serie.completata
            ? Icon(
                Icons.check,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
                semanticLabel: '${indice + 1}',
              )
            : Text('${indice + 1}', style: Theme.of(context).textTheme.titleSmall),
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
        video: IconButton(
          tooltip: Testi.of(context).videoDellaSerie(indice + 1),
          visualDensity: VisualDensity.compact,
          isSelected: _video.containsKey(serie),
          icon: const Icon(Icons.videocam_outlined),
          selectedIcon: const Icon(Icons.videocam),
          onPressed: _preparoVideo ? null : () => _videoSerie(indice, serie),
        ),
      ),
    );
  }

  /// Le colonne delle serie, uguali per l'intestazione e per ogni serie.
  /// Ogni colonna ha la sua chiave: se compare o sparisce la durata, i
  /// campi delle altre colonne restano quelli.
  Widget _colonne({
    bool fatta = false,
    required Widget numero,
    Widget? ripetizioni,
    Widget? durata,
    required Widget carico,
    Widget? video,
  }) {
    Widget colonna(_Campo campo, Widget figlio) => Expanded(
      key: ValueKey(campo),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: Center(child: figlio),
      ),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: fatta ? ColoriAtleta.serieFatta : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(width: 40, child: Center(child: numero)),
          if (ripetizioni != null) colonna(_Campo.ripetizioni, ripetizioni),
          if (durata != null) colonna(_Campo.durata, durata),
          colonna(_Campo.carico, carico),
          // Il video della serie, per il coach.
          SizedBox(width: 44, child: Center(child: video)),
        ],
      ),
    );
  }

  Widget? _barraRecupero() {
    if (_fineRecupero == null && !_recuperoFinito) return null;
    final testi = Testi.of(context);
    final tema = Theme.of(context);
    const chiaro = Color(0xFF74E0CF);
    final compatto = TextButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: const Color(0xFF26403B),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      minimumSize: const Size(56, 44),
      shape: const StadiumBorder(),
      textStyle: tema.textTheme.labelLarge,
    );
    final principale = compatto.copyWith(
      foregroundColor: const WidgetStatePropertyAll(ColoriAtleta.suContenitore),
      backgroundColor: const WidgetStatePropertyAll(chiaro),
    );
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        decoration: BoxDecoration(
          color: _recuperoFinito ? ColoriAtleta.primario : ColoriAtleta.testo,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(color: Color(0x4710201D), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Row(
          children: [
            Icon(_recuperoFinito ? Icons.alarm : Icons.timer_outlined, color: chiaro),
            const SizedBox(width: 12),
            Expanded(
              child: _recuperoFinito
                  ? Text(
                      testi.recuperoFinito,
                      style: tema.textTheme.titleMedium?.copyWith(color: Colors.white),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          testi.recupero,
                          style: tema.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFFA8C9C3),
                            letterSpacing: 0.6,
                          ),
                        ),
                        Text(
                          durata(Duration(seconds: _secondiMostrati)),
                          style: tema.textTheme.headlineMedium?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
            ),
            if (!_recuperoFinito) ...[
              TextButton(
                style: compatto,
                onPressed: () => _spostaRecupero(const Duration(seconds: -15)),
                child: Text(testi.menoQuindiciSecondi),
              ),
              const SizedBox(width: 6),
              TextButton(
                style: compatto,
                onPressed: () => _spostaRecupero(const Duration(seconds: 15)),
                child: Text(testi.piuQuindiciSecondi),
              ),
              const SizedBox(width: 6),
            ],
            TextButton(
              style: principale,
              onPressed: _chiudiRecupero,
              child: Text(_recuperoFinito ? testi.chiudi : testi.salta),
            ),
          ],
        ),
      ),
    );
  }
}

/// Il numero dell'esercizio nella seduta, in un cerchio: pieno e con la
/// spunta quando tutte le serie sono registrate.
class _NumeroEsercizio extends StatelessWidget {
  const _NumeroEsercizio(this.numero, {required this.concluso, required this.aperto});

  final int numero;
  final bool concluso;
  final bool aperto;

  @override
  Widget build(BuildContext context) {
    final colori = Theme.of(context).colorScheme;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: concluso ? colori.primary : null,
        border: concluso
            ? null
            : Border.all(
                color: aperto ? colori.primary : colori.outline,
                width: aperto ? 2 : 1.5,
              ),
      ),
      child: concluso
          ? Icon(Icons.check, size: 18, color: colori.onPrimary)
          : Text(
              '$numero',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: aperto ? colori.primary : colori.onSurfaceVariant,
              ),
            ),
    );
  }
}

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
