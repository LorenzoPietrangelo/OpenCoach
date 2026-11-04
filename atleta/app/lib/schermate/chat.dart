import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:protocollo/protocollo.dart';

import '../l10n/testi.dart';
import 'avvisi.dart';
import 'formati.dart';
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
        builder: (_) => SchermataQuestionario(
          nucleo: _nucleo,
          coachId: widget.coachId,
          questionarioId: q.id,
        ),
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

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final coach = _coach;
    final attivo = coach?.stato == StatoCollegamento.attivo;
    final voci = _voci;
    final daCompilare = [
      for (final q in _questionari)
        if (q.stato == StatoQuestionario.daCompilare) q,
    ];
    return Scaffold(
      appBar: widget.barra
          ? AppBar(title: Text(coach == null ? testi.chat : testi.chatCon(coach.nomeCoach)))
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (coach?.chatSupportata == false)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(testi.chatCoachVecchio)),
            ),
          // Non si perdono tra i messaggi: al massimo due, gli altri sono in
          // mezzo alla chat.
          for (final q in daCompilare.take(2))
            Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.edit_note),
                title: Text(q.titolo),
                subtitle: Text(testi.questionarioDaCompilare),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _apriQuestionario(q),
              ),
            ),
          Expanded(
            child: voci.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [Text(testi.chatVuota, textAlign: TextAlign.center)],
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: voci.length,
                    itemBuilder: (context, i) => switch (voci[voci.length - 1 - i]) {
                      final QuestionarioRicevuto q => _CartaQuestionario(q, onTap: () => _apriQuestionario(q)),
                      final messaggio => _Fumetto(
                        messaggio: messaggio as MessaggioChat,
                        nucleo: _nucleo,
                      ),
                    },
                  ),
          ),
          if (attivo)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _testo,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: [LengthLimitingTextInputFormatter(LimitiChat.testo)],
                        decoration: InputDecoration(
                          hintText: testi.scriviAlCoach,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: testi.inviaMessaggio,
                      onPressed: _invia,
                      icon: const Icon(Icons.send),
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
    final colori = Theme.of(context).colorScheme;
    final tema = Theme.of(context).textTheme;
    final mio = !messaggio.dalCoach;
    final esercizio = messaggio.esercizio;
    final serie = messaggio.serie;
    final stato = switch (messaggio.stato) {
      _ when !mio => null,
      StatoMessaggio.inInvio => (Icons.schedule, testi.inCodaPerIlCoach),
      StatoMessaggio.inviato => (Icons.done, testi.arrivatoAlCoach),
      StatoMessaggio.rifiutato => (Icons.error_outline, testi.messaggioNonArrivato),
    };
    final rifiutato = messaggio.stato == StatoMessaggio.rifiutato;
    final ritirabile = mio && messaggio.stato != StatoMessaggio.inviato;
    return Align(
      alignment: mio ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            crossAxisAlignment: mio ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Material(
                color: rifiutato
                    ? colori.errorContainer
                    : mio
                    ? colori.primaryContainer
                    : colori.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  // Un messaggio non ancora arrivato si può ritirare.
                  onLongPress: ritirabile ? () => _azioni(context) : null,
                  onTap: rifiutato ? () => _azioni(context) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (messaggio.video != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.videocam_outlined, size: 20),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  [
                                    if (esercizio != null && serie != null) testi.videoSerie(esercizio, serie),
                                    testi.secondiVideo(messaggio.durataVideoS ?? 0),
                                  ].join(' · '),
                                  style: tema.titleSmall,
                                ),
                              ),
                            ],
                          ),
                        // Il testo selezionabile prenderebbe la pressione lunga.
                        if (messaggio.testo.isNotEmpty)
                          ritirabile ? Text(messaggio.testo) : SelectableText(messaggio.testo),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(quando(context, messaggio.inviatoIl), style: tema.bodySmall),
                    if (stato != null) ...[
                      const SizedBox(width: 4),
                      Icon(stato.$1, size: 14, semanticLabel: stato.$2),
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

/// Un questionario del coach in mezzo alla chat, con il suo stato (§8.6).
class _CartaQuestionario extends StatelessWidget {
  const _CartaQuestionario(this.questionario, {required this.onTap});

  final QuestionarioRicevuto questionario;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final q = questionario;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(switch (q.stato) {
          StatoQuestionario.daCompilare => Icons.edit_note,
          StatoQuestionario.inInvio => Icons.schedule_send,
          StatoQuestionario.inviato => Icons.assignment_turned_in_outlined,
        }),
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
