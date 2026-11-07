import 'dart:async';

import 'package:flutter/material.dart';
import 'package:protocollo/protocollo.dart' show LimitiChat;

import '../dati/fonte_dati.dart';
import '../dati/modelli.dart';
import '../dati/stato_coach.dart';
import '../l10n/testi.dart';
import 'comuni.dart';

/// La chat con un atleta. Arriva tutta dal PC e resta solo in memoria; i
/// messaggi scritti e non ancora arrivati al PC si vedono «in attesa» (§16.4).
class SezioneChat extends StatefulWidget {
  const SezioneChat({super.key, required this.stato, required this.atletaId});

  final StatoCoach stato;
  final String atletaId;

  @override
  State<SezioneChat> createState() => _SezioneChatState();
}

class _SezioneChatState extends State<SezioneChat> with AutomaticKeepAliveClientMixin {
  final _campo = TextEditingController();
  var _messaggi = const <MessaggioChat>[];
  var _altri = false;
  var _caricata = false;
  var _errore = false;
  var _caricoPrecedenti = false;
  var _generazione = -1;

  StatoCoach get _stato => widget.stato;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _stato.addListener(_statoCambiato);
    _statoCambiato();
  }

  @override
  void dispose() {
    _stato.removeListener(_statoCambiato);
    _campo.dispose();
    super.dispose();
  }

  void _statoCambiato() {
    if (!_stato.collegato || _stato.generazione == _generazione) return;
    _generazione = _stato.generazione;
    unawaited(_leggi());
  }

  /// Rilegge gli ultimi messaggi. Tiene i più vecchi già caricati.
  Future<void> _leggi() async {
    try {
      final pagina = await _stato.fonte.messaggi(widget.atletaId);
      if (!mounted) return;
      final nuovi = {for (final m in pagina.elementi) m.id};
      final primoNuovo = pagina.elementi.firstOrNull?.inviatoIl;
      setState(() {
        _messaggi = [
          // I precedenti caricati a mano restano, se la pagina nuova non li copre.
          if (_caricata && primoNuovo != null)
            ..._messaggi.where(
              (m) => !nuovi.contains(m.id) && (m.inviatoIl?.isBefore(primoNuovo) ?? false),
            ),
          ...pagina.elementi,
        ];
        if (!_caricata) _altri = pagina.altri;
        _caricata = true;
        _errore = false;
      });
      if (pagina.elementi.any((m) => !m.dalCoach && !_letti.contains(m.id))) {
        _letti.addAll(nuovi);
        unawaited(_segnaLetti());
      }
    } on ErroreCoach {
      if (mounted) setState(() => _errore = !_caricata);
    }
  }

  /// I messaggi che il coach ha già visto qui, per segnarli una volta sola.
  final _letti = <String>{};

  Future<void> _segnaLetti() async {
    try {
      await _stato.segnaLetti(widget.atletaId);
    } on ErroreCoach {
      // Resta da leggere: ritenta alla prossima lettura.
      _letti.clear();
    }
  }

  Future<void> _precedenti() async {
    final primo = _messaggi.firstOrNull;
    if (primo == null) return;
    setState(() => _caricoPrecedenti = true);
    try {
      final pagina = await _stato.fonte.messaggi(widget.atletaId, prima: primo.id);
      if (!mounted) return;
      setState(() {
        _messaggi = [...pagina.elementi, ..._messaggi];
        _altri = pagina.altri;
      });
    } on ErroreCoach {
      // Il riquadro del problema spiega già: il pulsante resta.
    } finally {
      if (mounted) setState(() => _caricoPrecedenti = false);
    }
  }

  Future<void> _invia() async {
    final testo = _campo.text;
    if (testo.trim().isEmpty) return;
    _campo.clear();
    await _stato.scrivi(widget.atletaId, testo);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = Testi.of(context);
    return ListenableBuilder(
      listenable: _stato,
      builder: (context, _) {
        final inCoda = [
          for (final m in _stato.coda.perAtleta(widget.atletaId))
            if (!_messaggi.any((arrivato) => arrivato.id == m.id)) m.comeMessaggio(),
        ];
        final tutti = [..._messaggi, ...inCoda];
        return Column(
          children: [
            Expanded(
              child: !_caricata && inCoda.isEmpty
                  ? (_errore ? ListaVuota(t.problemaDati) : const Center(child: CircularProgressIndicator()))
                  : tutti.isEmpty
                  ? ListaVuota(t.chatVuota)
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: tutti.length + (_altri ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == tutti.length) {
                          return Center(
                            child: TextButton(
                              onPressed: _caricoPrecedenti ? null : _precedenti,
                              child: Text(t.chatPrecedenti),
                            ),
                          );
                        }
                        final messaggio = tutti[tutti.length - 1 - i];
                        return _Fumetto(
                          messaggio: messaggio,
                          togli: messaggio.statoInvio == StatoInvio.rifiutato
                              ? () => _stato.togliDallaCoda(messaggio.id)
                              : null,
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _campo,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: LimitiChat.testo,
                      buildCounter: _nessunContatore,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: t.chatScrivi, border: InputBorder.none),
                    ),
                  ),
                  IconButton(tooltip: t.chatInvia, onPressed: _invia, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static Widget? _nessunContatore(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) => null;
}

class _Fumetto extends StatelessWidget {
  const _Fumetto({required this.messaggio, this.togli});

  final MessaggioChat messaggio;

  /// Per un messaggio che il PC ha rifiutato.
  final VoidCallback? togli;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context);
    final mio = messaggio.dalCoach;
    final colore = mio ? tema.colorScheme.primaryContainer : tema.colorScheme.surfaceContainerHighest;
    final testoColore = mio ? tema.colorScheme.onPrimaryContainer : tema.colorScheme.onSurface;
    final piccolo = tema.textTheme.labelSmall?.copyWith(color: testoColore);
    final quando = messaggio.inviatoIl;
    final esercizio = messaggio.esercizio;
    final serie = messaggio.serie;
    return Align(
      alignment: mio ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: InkWell(
          onTap: togli,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: colore, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (messaggio.conVideo) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_outlined, size: 18, color: testoColore),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          messaggio.videoEliminato
                              ? t.chatVideoEliminato
                              : t.chatVideo(messaggio.durataVideoS ?? 0),
                          style: tema.textTheme.bodySmall?.copyWith(color: testoColore),
                        ),
                      ),
                    ],
                  ),
                  if (esercizio != null && serie != null)
                    Text(t.chatRiferimento(esercizio, serie), style: piccolo),
                  if (messaggio.testo.isNotEmpty) const SizedBox(height: 4),
                ],
                if (messaggio.testo.isNotEmpty) Text(messaggio.testo, style: TextStyle(color: testoColore)),
                const SizedBox(height: 2),
                Text(
                  switch (messaggio.statoInvio) {
                    StatoInvio.inAttesa => t.chatInAttesa,
                    StatoInvio.rifiutato => t.chatRifiutato,
                    StatoInvio.inviato => quando == null ? '' : quandoBreve(quando),
                  },
                  style: piccolo?.copyWith(
                    color: messaggio.statoInvio == StatoInvio.rifiutato ? tema.colorScheme.error : null,
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
