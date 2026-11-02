import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:protocollo/protocollo.dart';

import '../l10n/testi.dart';
import 'avvisi.dart';
import 'formati.dart';

/// La chat con il coach (§8.7). I messaggi partono alla sync successiva;
/// con la chat aperta l'app sincronizza ogni [intervallo], così le risposte
/// del coach arrivano senza aspettare la sync automatica. I video delle
/// serie si allegano dall'allenamento.
class SchermataChat extends StatefulWidget {
  const SchermataChat({super.key, required this.nucleo, required this.coachId});

  final NucleoAtleta nucleo;
  final int coachId;

  static const intervallo = Duration(seconds: 15);

  @override
  State<SchermataChat> createState() => _SchermataChatState();
}

class _SchermataChatState extends State<SchermataChat> {
  final _testo = TextEditingController();
  late final StreamSubscription<int> _cambiamenti;
  Timer? _prossima;
  var _messaggi = <MessaggioChat>[];
  CoachCollegato? _coach;

  NucleoAtleta get _nucleo => widget.nucleo;

  @override
  void initState() {
    super.initState();
    _leggi();
    _cambiamenti = _nucleo.cambiamenti.listen((id) {
      if (id == widget.coachId && mounted) setState(_leggi);
    });
    unawaited(_sincronizza());
  }

  @override
  void dispose() {
    _prossima?.cancel();
    unawaited(_cambiamenti.cancel());
    _testo.dispose();
    super.dispose();
  }

  void _leggi() {
    _coach = _nucleo.collegamenti.cerca(widget.coachId);
    _messaggi = _nucleo.chat.elenco(widget.coachId);
    // Con la chat aperta, quello che arriva è letto.
    if (_messaggi.any((m) => m.dalCoach && !m.letto)) {
      scheduleMicrotask(() => _nucleo.chat.segnaLetti(widget.coachId));
    }
  }

  Future<void> _sincronizza() async {
    if (_coach?.stato != StatoCollegamento.attivo) return;
    await _nucleo.pianificatore.sincronizzaOra(widget.coachId);
    if (!mounted) return;
    _prossima = _nucleo.contesto.orologio.timer(SchermataChat.intervallo, () {
      if (mounted) unawaited(_sincronizza());
    });
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
    return Scaffold(
      appBar: AppBar(title: Text(coach == null ? testi.chat : testi.chatCon(coach.nomeCoach))),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (coach?.chatSupportata == false)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(testi.chatCoachVecchio)),
            ),
          Expanded(
            child: _messaggi.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [Text(testi.chatVuota, textAlign: TextAlign.center)],
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: _messaggi.length,
                    itemBuilder: (context, i) => _Fumetto(
                      messaggio: _messaggi[_messaggi.length - 1 - i],
                      nucleo: _nucleo,
                    ),
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
