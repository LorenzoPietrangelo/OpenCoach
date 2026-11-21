import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:protocollo/protocollo.dart';

import '../l10n/testi.dart';
import '../tema.dart';
import 'avvisi.dart';
import 'questionario.dart';

/// La chat con il coach (§8.7): i messaggi e, in mezzo, i questionari che ha
/// mandato (§8.6); quelli da compilare restano anche in cima. I messaggi
/// partono alla sync successiva; mentre l'atleta guarda la chat le risposte
/// del coach arrivano subito (§7.4). I video delle serie si allegano
/// dall'allenamento.
class SchermataChat extends StatefulWidget {
  const SchermataChat({
    super.key,
    required this.nucleo,
    required this.coachId,
    this.barra = true,
    this.visibile = true,
  });

  final NucleoAtleta nucleo;
  final int coachId;

  /// Nelle sezioni dell'app la barra in alto è una sola.
  final bool barra;

  /// Falso mentre l'atleta è in un'altra sezione: quello che arriva resta da
  /// leggere.
  final bool visibile;

  @override
  State<SchermataChat> createState() => _SchermataChatState();
}

class _SchermataChatState extends State<SchermataChat> {
  final _testo = TextEditingController();
  late final StreamSubscription<int> _cambiamenti;
  var _messaggi = <MessaggioChat>[];
  var _questionari = <QuestionarioRicevuto>[];
  CoachCollegato? _coach;

  NucleoAtleta get _nucleo => widget.nucleo;

  @override
  void initState() {
    super.initState();
    _leggi();
    _cambiamenti = _nucleo.cambiamenti.listen((id) {
      if (id == widget.coachId && mounted) setState(_leggi);
    });
    _seguiSeVisibile();
  }

  @override
  void didUpdateWidget(SchermataChat vecchia) {
    super.didUpdateWidget(vecchia);
    if (widget.visibile == vecchia.visibile) return;
    _seguiSeVisibile();
    if (widget.visibile) _leggi();
  }

  void _seguiSeVisibile() {
    if (widget.visibile && _coach?.stato == StatoCollegamento.attivo) {
      _nucleo.pianificatore.segui(widget.coachId);
    } else {
      _nucleo.pianificatore.smettiDiSeguire(widget.coachId);
    }
  }

  @override
  void dispose() {
    _nucleo.pianificatore.smettiDiSeguire(widget.coachId);
    unawaited(_cambiamenti.cancel());
    _testo.dispose();
    super.dispose();
  }

  void _leggi() {
    _coach = _nucleo.collegamenti.cerca(widget.coachId);
    _messaggi = _nucleo.chat.elenco(widget.coachId);
    _questionari = _nucleo.questionari.elenco(widget.coachId);
    // Con la chat aperta, quello che arriva è letto.
    if (widget.visibile && _messaggi.any((m) => m.dalCoach && !m.letto)) {
      scheduleMicrotask(() => _nucleo.chat.segnaLetti(widget.coachId));
    }
  }

  /// Messaggi e questionari in ordine di tempo: i messaggi restano
  /// nell'ordine della chat, e ogni questionario entra dov'è arrivato.
  List<Object> get _voci {
    final questionari = _questionari.toList()..sort((a, b) => a.ricevutoIl.compareTo(b.ricevutoIl));
    final voci = <Object>[];
    var prossimo = 0;
    for (final messaggio in _messaggi) {
      while (prossimo < questionari.length && questionari[prossimo].ricevutoIl.isBefore(messaggio.inviatoIl)) {
        voci.add(questionari[prossimo++]);
      }
      voci.add(messaggio);
    }
    return voci..addAll(questionari.skip(prossimo));
  }

  Future<void> _apriQuestionario(QuestionarioRicevuto q) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SchermataQuestionario(nucleo: _nucleo, coachId: widget.coachId, questionarioId: q.id),
      ),
    );
    if (mounted) setState(_leggi);
  }

  void _invia() {
    final testo = _testo.text.trim();
    if (testo.isEmpty) return;
    try {
      _nucleo.chat.scrivi(widget.coachId, testo);
      _testo.clear();
    } on OperazioneNonAmmessa catch (e) {
      ScaffoldMessenger.of(context).avvisa(e.messaggio);
    }
  }

  /// Le voci con un separatore («Oggi», «Ieri», la data) all'inizio di ogni
  /// giorno, così sotto i fumetti basta l'ora.
  static List<Object> _conGiorni(List<Object> voci) {
    final risultato = <Object>[];
    DateTime? ultimo;
    for (final voce in voci) {
      final istante = switch (voce) {
        final QuestionarioRicevuto q => q.ricevutoIl,
        final m => (m as MessaggioChat).inviatoIl,
      }.toLocal();
      final giorno = DateUtils.dateOnly(istante);
      if (giorno != ultimo) risultato.add(_SeparatoreGiorno(giorno));
      ultimo = giorno;
      risultato.add(voce);
    }
    return risultato;
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final coach = _coach;
    final attivo = coach?.stato == StatoCollegamento.attivo;
    final voci = _conGiorni(_voci);
    final daCompilare = [
      for (final q in _questionari)
        if (q.stato == StatoQuestionario.daCompilare) q,
    ];
    return Scaffold(
      appBar: widget.barra ? AppBar(title: Text(coach == null ? testi.chat : testi.chatCon(coach.nomeCoach))) : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (coach?.chatSupportata == false)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(padding: const EdgeInsets.all(12), child: Text(testi.chatCoachVecchio)),
              ),
            ),
          // Non si perdono tra i messaggi: al massimo due, gli altri sono in
          // mezzo alla chat.
          for (final q in daCompilare.take(2)) _QuestionarioInCima(q, onTap: () => _apriQuestionario(q)),
          Expanded(
            child: voci.isEmpty
                ? const _ChatVuota()
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: voci.length,
                    itemBuilder: (context, i) => switch (voci[voci.length - 1 - i]) {
                      final Widget separatore => separatore,
                      final QuestionarioRicevuto q => _CartaQuestionario(q, onTap: () => _apriQuestionario(q)),
                      final messaggio => _Fumetto(messaggio: messaggio as MessaggioChat, nucleo: _nucleo),
                    },
                  ),
          ),
          if (attivo)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _CampoMessaggio(controller: _testo, invia: _invia),
                    ),
                    const SizedBox(width: 8),
                    // Teal solo quando c'è qualcosa da mandare.
                    ValueListenableBuilder(
                      valueListenable: _testo,
                      builder: (context, valore, _) => IconButton.filled(
                        tooltip: testi.inviaMessaggio,
                        onPressed: valore.text.trim().isEmpty ? null : _invia,
                        style: IconButton.styleFrom(
                          fixedSize: const Size.square(48),
                          backgroundColor: ColoriAtleta.primario,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: ColoriAtleta.superficieTenue,
                          disabledForegroundColor: ColoriAtleta.testoSecondario,
                        ),
                        icon: const Icon(Icons.send_rounded, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Il campo a pillola in fondo alla chat.
class _CampoMessaggio extends StatelessWidget {
  const _CampoMessaggio({required this.controller, required this.invia});

  final TextEditingController controller;
  final VoidCallback invia;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder bordo(Color colore, [double spessore = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: colore, width: spessore),
    );
    final contorno = Theme.of(context).colorScheme.outline;
    return TextField(
      controller: controller,
      minLines: 1,
      maxLines: 5,
      textCapitalization: TextCapitalization.sentences,
      inputFormatters: [LengthLimitingTextInputFormatter(LimitiChat.testo)],
      decoration: InputDecoration(
        hintText: Testi.of(context).scriviAlCoach,
        filled: true,
        fillColor: ColoriAtleta.superficie,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: bordo(contorno),
        enabledBorder: bordo(contorno),
        focusedBorder: bordo(ColoriAtleta.primario, 2),
      ),
    );
  }
}

/// Il benvenuto della chat ancora vuota.
class _ChatVuota extends StatelessWidget {
  const _ChatVuota();

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const IconaInCerchio(
                  Icons.chat_bubble_outline,
                  colore: ColoriAtleta.primario,
                  sfondo: ColoriAtleta.contenitore,
                  diametro: 56,
                ),
                const SizedBox(height: 14),
                Text(testi.chatVuota, textAlign: TextAlign.center, style: tema.bodyLarge),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: ColoriAtleta.sfondo, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.videocam_outlined, size: 20, color: ColoriAtleta.primario),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          testi.chatVuotaVideo,
                          style: tema.bodyMedium?.copyWith(color: ColoriAtleta.testoSecondario),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Oggi», «Ieri» o la data, tra i messaggi di giorni diversi.
class _SeparatoreGiorno extends StatelessWidget {
  const _SeparatoreGiorno(this.giorno);

  final DateTime giorno;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final oggi = DateUtils.dateOnly(DateTime.now());
    final testo = giorno == oggi
        ? testi.chatOggi
        : giorno == DateTime(oggi.year, oggi.month, oggi.day - 1)
        ? testi.chatIeri
        : MaterialLocalizations.of(context).formatMediumDate(giorno);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: ColoriAtleta.superficieTenue, borderRadius: BorderRadius.circular(999)),
        child: Text(
          testo,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: ColoriAtleta.testoSecondario, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _Fumetto extends StatelessWidget {
  const _Fumetto({required this.messaggio, required this.nucleo});

  final MessaggioChat messaggio;
  final NucleoAtleta nucleo;

  Future<void> _azioni(BuildContext context) async {
    final testi = Testi.of(context);
    final scelta = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (messaggio.stato == StatoMessaggio.rifiutato)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(testi.riprovaInvio),
                onTap: () => Navigator.of(context).pop(true),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(testi.nonInviare),
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
    if (scelta == null) return;
    if (scelta) {
      nucleo.chat.ritenta(messaggio.coachId, messaggio.id);
    } else {
      nucleo.chat.ritira(messaggio.coachId, messaggio.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final mio = !messaggio.dalCoach;
    final esercizio = messaggio.esercizio;
    final serie = messaggio.serie;
    final rifiutato = messaggio.stato == StatoMessaggio.rifiutato;
    final ritirabile = mio && messaggio.stato != StatoMessaggio.inviato;
    // I propri messaggi pieni in teal, quelli del coach bianchi con bordo.
    final scuro = mio && !rifiutato;
    final colore = scuro ? Colors.white : ColoriAtleta.testo;
    final stato = switch (messaggio.stato) {
      _ when !mio || rifiutato => null,
      StatoMessaggio.inInvio => (Icons.schedule, ColoriAtleta.testoSecondario, testi.inCodaPerIlCoach),
      _ => (Icons.check, ColoriAtleta.primario, testi.arrivatoAlCoach),
    };
    const grande = Radius.circular(18);
    const piccolo = Radius.circular(6);
    final forma = RoundedRectangleBorder(
      // L'angolo stretto è verso chi scrive.
      borderRadius: BorderRadius.only(
        topLeft: grande,
        topRight: grande,
        bottomLeft: mio ? grande : piccolo,
        bottomRight: mio ? piccolo : grande,
      ),
      side: switch ((scuro, rifiutato)) {
        (true, _) => BorderSide.none,
        (_, true) => const BorderSide(color: Color(0xFFF2B8B3)),
        _ => const BorderSide(color: ColoriAtleta.bordo),
      },
    );
    final stile = tema.bodyLarge?.copyWith(color: colore, fontSize: 15, height: 1.4);
    final video = messaggio.video != null;
    final locale = MaterialLocalizations.of(context);
    return Align(
      alignment: mio ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            crossAxisAlignment: mio ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Material(
                color: scuro
                    ? ColoriAtleta.primario
                    : rifiutato
                    ? ColoriAtleta.erroreContenitore
                    : ColoriAtleta.superficie,
                shape: forma,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  // Un messaggio non ancora arrivato si può ritirare.
                  onLongPress: ritirabile ? () => _azioni(context) : null,
                  onTap: rifiutato ? () => _azioni(context) : null,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(video ? 8 : 14, video ? 8 : 10, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (video)
                          _RigaVideo(
                            titolo: esercizio != null && serie != null
                                ? testi.videoSerie(esercizio, serie)
                                : testi.secondiVideo(messaggio.durataVideoS ?? 0),
                            durata: esercizio != null && serie != null
                                ? testi.secondiVideo(messaggio.durataVideoS ?? 0)
                                : null,
                            scuro: scuro,
                          ),
                        if (video && messaggio.testo.isNotEmpty) const SizedBox(height: 8),
                        // Il testo selezionabile prenderebbe la pressione lunga.
                        if (messaggio.testo.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(left: video ? 6 : 0),
                            child: ritirabile
                                ? Text(messaggio.testo, style: stile)
                                : SelectableText(messaggio.testo, style: stile),
                          ),
                        if (rifiutato) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 16, color: ColoriAtleta.errore),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  testi.messaggioNonArrivato,
                                  style: tema.bodySmall?.copyWith(
                                    color: ColoriAtleta.errore,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 3, 6, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      locale.formatTimeOfDay(TimeOfDay.fromDateTime(messaggio.inviatoIl.toLocal())),
                      style: tema.bodySmall?.copyWith(color: ColoriAtleta.testoSecondario),
                    ),
                    if (stato != null) ...[
                      const SizedBox(width: 4),
                      Icon(stato.$1, size: 14, color: stato.$2, semanticLabel: stato.$3),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Il video di una serie dentro il fumetto.
class _RigaVideo extends StatelessWidget {
  const _RigaVideo({required this.titolo, required this.durata, required this.scuro});

  final String titolo;
  final String? durata;
  final bool scuro;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final durata = this.durata;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
      decoration: BoxDecoration(
        color: scuro ? const Color(0xFF085A51) : ColoriAtleta.sfondo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconaInCerchio(
            Icons.videocam_outlined,
            colore: ColoriAtleta.primario,
            sfondo: scuro ? Colors.white : ColoriAtleta.contenitore,
            diametro: 32,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(titolo, style: tema.titleSmall?.copyWith(color: scuro ? Colors.white : ColoriAtleta.testo)),
                if (durata != null)
                  Text(
                    durata,
                    style: tema.bodySmall?.copyWith(
                      color: scuro ? const Color(0xFFCDEDE7) : ColoriAtleta.testoSecondario,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Un questionario da compilare, in cima alla chat.
class _QuestionarioInCima extends StatelessWidget {
  const _QuestionarioInCima(this.questionario, {required this.onTap});

  final QuestionarioRicevuto questionario;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: ColoriAtleta.contenitore,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                const IconaInCerchio(
                  Icons.assignment_outlined,
                  colore: ColoriAtleta.primario,
                  sfondo: ColoriAtleta.superficie,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        questionario.titolo,
                        style: tema.titleSmall?.copyWith(
                          color: ColoriAtleta.suContenitore,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        Testi.of(context).questionarioDaCompilare,
                        style: tema.bodySmall?.copyWith(color: ColoriAtleta.suContenitore),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: ColoriAtleta.suContenitore),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un questionario del coach in mezzo alla chat, con il suo stato (§8.6).
class _CartaQuestionario extends StatelessWidget {
  const _CartaQuestionario(this.questionario, {required this.onTap});

  final QuestionarioRicevuto questionario;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final q = questionario;
    final (icona, colore, sfondo) = switch (q.stato) {
      StatoQuestionario.daCompilare => (Icons.edit_note, ColoriAtleta.primario, ColoriAtleta.contenitore),
      StatoQuestionario.inInvio => (Icons.schedule_send, ColoriAtleta.attesa, ColoriAtleta.attesaContenitore),
      StatoQuestionario.inviato => (
        Icons.assignment_turned_in_outlined,
        ColoriAtleta.testoSecondario,
        ColoriAtleta.superficieTenue,
      ),
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: IconaInCerchio(icona, colore: colore, sfondo: sfondo),
        title: Text(q.titolo),
        subtitle: Text(switch (q.stato) {
          StatoQuestionario.daCompilare => q.rifiuto == null ? testi.daCompilare : testi.questionarioRifiutato,
          StatoQuestionario.inInvio => testi.inCodaPerIlCoach,
          StatoQuestionario.inviato => testi.arrivatoAlCoach,
        }),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
