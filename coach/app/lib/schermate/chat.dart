import 'dart:async';
import 'dart:io';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:protocollo/protocollo.dart';
import 'package:video_player/video_player.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../piattaforma/desktop.dart';
import '../servizi.dart';

/// Chat con l'atleta (§8.7). I messaggi del coach partono alla sync
/// successiva dell'atleta; i video che l'atleta allega alle serie si
/// guardano con il lettore del sistema.
class PannelloChat extends StatefulWidget {
  const PannelloChat({
    super.key,
    required this.atleta,
    required this.coach,
    required this.desktop,
    required this.aggiornamenti,
  });

  final Atleta atleta;
  final Coach coach;
  final Desktop desktop;
  final Aggiornamenti aggiornamenti;

  @override
  State<PannelloChat> createState() => _PannelloChatState();
}

class _PannelloChatState extends State<PannelloChat> {
  final _testo = TextEditingController();

  GestioneMessaggi get _messaggi => widget.coach.nucleo.messaggi;

  @override
  void dispose() {
    _testo.dispose();
    super.dispose();
  }

  void _invia() {
    final testo = _testo.text.trim();
    if (testo.isEmpty) return;
    _messaggi.invia(widget.atleta.id, testo);
    _testo.clear();
    widget.aggiornamenti.segnala();
  }

  /// Con il pannello aperto, i messaggi arrivati sono letti.
  void _segnaLetti() {
    if (_messaggi.nonLetti(widget.atleta.id) == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messaggi.segnaLetti(widget.atleta.id);
      widget.aggiornamenti.segnala();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return ListenableBuilder(
      listenable: widget.aggiornamenti,
      builder: (context, _) {
        _segnaLetti();
        final conversazione = _messaggi.conversazione(widget.atleta.id);
        final dispositivo = widget.coach.nucleo.dispositivi.attivo(widget.atleta.id);
        final appVecchia = dispositivo != null && confrontaVersioni(dispositivo.versioneApp, '1.3.0') < 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (appVecchia)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Text(t.chatAppVecchia(dispositivo.versioneApp)),
              ),
            Expanded(
              child: conversazione.isEmpty
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(t.chatVuota))
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(24),
                      itemCount: conversazione.length,
                      itemBuilder: (context, i) => _Fumetto(
                        messaggio: conversazione[conversazione.length - 1 - i],
                        atletaId: widget.atleta.id,
                        coach: widget.coach,
                        desktop: widget.desktop,
                        aggiornamenti: widget.aggiornamenti,
                      ),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: CallbackShortcuts(
                      // Invio manda, Maiusc+Invio va a capo.
                      bindings: {const SingleActivator(LogicalKeyboardKey.enter): _invia},
                      child: TextField(
                        controller: _testo,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: LimitiChat.testo,
                        decoration: InputDecoration(hintText: t.scriviMessaggio, counterText: ''),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: t.inviaMessaggio,
                    onPressed: _invia,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Fumetto extends StatelessWidget {
  const _Fumetto({
    required this.messaggio,
    required this.atletaId,
    required this.coach,
    required this.desktop,
    required this.aggiornamenti,
  });

  final Messaggio messaggio;
  final String atletaId;
  final Coach coach;
  final Desktop desktop;
  final Aggiornamenti aggiornamenti;

  @override
  Widget build(BuildContext context) {
    final colori = Theme.of(context).colorScheme;
    final tema = Theme.of(context).textTheme;
    final mio = messaggio.dalCoach;
    return Align(
      alignment: mio ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: mio ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: mio ? colori.primaryContainer : colori.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (messaggio.video != null) _Video(messaggio: messaggio, atletaId: atletaId, coach: coach, desktop: desktop, aggiornamenti: aggiornamenti),
                      if (messaggio.testo.isNotEmpty) SelectableText(messaggio.testo),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(dataOra(messaggio.inviatoIl), style: tema.bodySmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Video extends StatelessWidget {
  const _Video({
    required this.messaggio,
    required this.atletaId,
    required this.coach,
    required this.desktop,
    required this.aggiornamenti,
  });

  final Messaggio messaggio;
  final String atletaId;
  final Coach coach;
  final Desktop desktop;
  final Aggiornamenti aggiornamenti;

  Future<void> _guarda(BuildContext context, String percorso) {
    final t = Testi.of(context);
    final riferimento = messaggio.riferimento;
    return showDialog<void>(
      context: context,
      builder: (_) => LettoreVideo(
        percorso: percorso,
        titolo: riferimento == null
            ? t.videoDurata(messaggio.durataVideoS ?? 0)
            : t.videoSerie(riferimento['esercizio']! as String, riferimento['serie']! as int),
        desktop: desktop,
      ),
    );
  }

  Future<void> _elimina(BuildContext context) async {
    final t = Testi.of(context);
    final confermato = await conferma(
      context,
      titolo: t.eliminaVideo,
      testo: t.eliminaVideoDomanda,
      azione: t.elimina,
      pericolosa: true,
    );
    if (!confermato) return;
    coach.nucleo.messaggi.eliminaVideo(atletaId, messaggio.id);
    aggiornamenti.segnala();
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final file = coach.nucleo.messaggi.fileVideo(atletaId, messaggio);
    final riferimento = messaggio.riferimento;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (riferimento != null)
            Text(
              t.videoSerie(riferimento['esercizio']! as String, riferimento['serie']! as int),
              style: tema.titleSmall,
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_outlined, size: 20),
              const SizedBox(width: 6),
              Text(
                messaggio.videoEliminato
                    ? t.videoEliminato
                    : file == null
                    ? t.videoNonDisponibile
                    : t.videoDurata(messaggio.durataVideoS ?? 0),
              ),
              if (file != null) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _guarda(context, file.path),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(t.guardaVideo),
                ),
                IconButton(
                  tooltip: t.eliminaVideo,
                  onPressed: () => _elimina(context),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Il video di una serie dentro il programma, con il lettore di Windows
/// (Media Foundation): rallentatore per guardare la tecnica, ripetizione
/// continua, spazio per fermare e riprendere. Se il video non si apre qui
/// si può aprire con un altro programma.
class LettoreVideo extends StatefulWidget {
  const LettoreVideo({super.key, required this.percorso, required this.titolo, required this.desktop});

  final String percorso;
  final String titolo;
  final Desktop desktop;

  @override
  State<LettoreVideo> createState() => _LettoreVideoState();
}

class _LettoreVideoState extends State<LettoreVideo> {
  late final _lettore = VideoPlayerController.file(File(widget.percorso));
  var _velocita = 1.0;
  Object? _errore;

  @override
  void initState() {
    super.initState();
    unawaited(_apri());
  }

  Future<void> _apri() async {
    try {
      await _lettore.initialize();
      await _lettore.setLooping(true);
      await _lettore.play();
    } catch (e) {
      _errore = e;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_lettore.dispose());
    super.dispose();
  }

  void _pausaOPlay() => unawaited(_lettore.value.isPlaying ? _lettore.pause() : _lettore.play());

  Future<void> _apriFuori() async {
    try {
      await widget.desktop.apriFile(widget.percorso);
    } catch (e) {
      if (mounted) avviso(context, Testi.of(context).videoNonAperto('$e'));
    }
  }

  String _tempo(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final schermo = MediaQuery.sizeOf(context);
    final pronto = _lettore.value.isInitialized;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.space): _pausaOPlay},
      child: Focus(
        autofocus: true,
        child: Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: schermo.width * 0.9, maxHeight: schermo.height * 0.9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(child: Text(widget.titolo, style: Theme.of(context).textTheme.titleMedium)),
                      IconButton(
                        tooltip: t.apriConAltroProgramma,
                        onPressed: _apriFuori,
                        icon: const Icon(Icons.open_in_new),
                      ),
                      IconButton(
                        tooltip: t.chiudi,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                if (_errore != null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(t.videoNonRiproducibile('$_errore')),
                  )
                else if (!pronto)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  Flexible(
                    child: GestureDetector(
                      onTap: _pausaOPlay,
                      child: ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: AspectRatio(aspectRatio: _lettore.value.aspectRatio, child: VideoPlayer(_lettore)),
                        ),
                      ),
                    ),
                  ),
                  VideoProgressIndicator(
                    _lettore,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  ValueListenableBuilder(
                    valueListenable: _lettore,
                    builder: (context, valore, _) => Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: valore.isPlaying ? t.pausa : t.riproduci,
                            onPressed: _pausaOPlay,
                            icon: Icon(valore.isPlaying ? Icons.pause : Icons.play_arrow),
                          ),
                          Text('${_tempo(valore.position)} / ${_tempo(valore.duration)}'),
                          const Spacer(),
                          SegmentedButton<double>(
                            showSelectedIcon: false,
                            segments: [
                              for (final v in const [0.25, 0.5, 1.0])
                                ButtonSegment(value: v, label: Text(v == 1 ? '1×' : '${v.toString().replaceAll('.', ',')}×')),
                            ],
                            selected: {_velocita},
                            onSelectionChanged: (scelta) {
                              setState(() => _velocita = scelta.single);
                              unawaited(_lettore.setPlaybackSpeed(_velocita));
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
