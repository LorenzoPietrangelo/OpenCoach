import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../l10n/testi.dart';

/// Il video di un esercizio, dalla libreria del coach (§8.1).
///
/// Un video di YouTube si guarda dentro l'app, ma il player si carica solo
/// quando l'atleta lo chiede: fino ad allora l'app non si collega a YouTube.
/// Il video non passa da Tor. Gli altri link si aprono nell'app o nel
/// browser del telefono.
class VideoEsercizio extends StatefulWidget {
  const VideoEsercizio({super.key, required this.link, required this.visibile});

  final Uri link;

  /// Falso quando l'esercizio si chiude: il video va in pausa.
  final bool visibile;

  @override
  State<VideoEsercizio> createState() => _VideoEsercizioState();
}

class _VideoEsercizioState extends State<VideoEsercizio> {
  late final _idYoutube = YoutubePlayerController.convertUrlToId(
    widget.link.toString(),
  );
  YoutubePlayerController? _player;

  @override
  void didUpdateWidget(VideoEsercizio vecchio) {
    super.didUpdateWidget(vecchio);
    if (!widget.visibile && vecchio.visibile) unawaited(_player?.pauseVideo());
  }

  @override
  void dispose() {
    unawaited(_player?.close());
    super.dispose();
  }

  void _guarda() {
    final id = _idYoutube;
    if (id == null) {
      unawaited(_apriFuori());
      return;
    }
    setState(
      () => _player = YoutubePlayerController.fromVideoId(
        videoId: id,
        autoPlay: true,
        params: const YoutubePlayerParams(
          showFullscreenButton: true,
          strictRelatedVideos: true,
          interfaceLanguage: 'it',
          captionLanguage: 'it',
        ),
      ),
    );
  }

  Future<void> _apriFuori() async {
    final aperto = await launchUrl(widget.link, mode: LaunchMode.externalApplication);
    if (!aperto && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Testi.of(context).videoNonApribile)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final player = _player;
    if (player == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: OutlinedButton.icon(
          onPressed: _guarda,
          icon: Icon(_idYoutube == null ? Icons.open_in_new : Icons.play_circle_outline),
          label: Text(testi.guardaIlVideo),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: YoutubePlayer(controller: player, aspectRatio: 16 / 9),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  testi.videoFuoriDaTor,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(onPressed: _apriFuori, child: Text(testi.apriSuYoutube)),
            ],
          ),
        ],
      ),
    );
  }
}
