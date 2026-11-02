import 'dart:convert';
import 'dart:io';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../piattaforma/desktop.dart';
import '../servizi.dart';
import 'allenamenti.dart';
import 'chat.dart';
import 'peso.dart';
import 'questionari.dart';
import 'schede.dart';
import 'telefono.dart';

/// Dettaglio di un atleta: telefono e invito, schede, allenamenti, peso,
/// questionari.
class DettaglioAtleta extends StatelessWidget {
  const DettaglioAtleta({
    super.key,
    required this.atletaId,
    required this.coach,
    required this.desktop,
    required this.aggiornamenti,
  });

  final String atletaId;
  final Coach coach;
  final Desktop desktop;
  final Aggiornamenti aggiornamenti;

  NucleoCoach get _nucleo => coach.nucleo;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final atleta = _nucleo.atleti.cerca(atletaId);
    if (atleta == null) return const SizedBox.shrink();
    return DefaultTabController(
      length: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(atleta.nome, style: Theme.of(context).textTheme.headlineSmall),
                      if (atleta.note.isNotEmpty)
                        Text(
                          atleta.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (atleta.archiviato) Text(t.atletaArchiviato),
                    ],
                  ),
                ),
                _MenuAtleta(atleta: atleta, coach: coach, desktop: desktop, aggiornamenti: aggiornamenti),
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: t.schedaTelefono),
              Tab(text: t.schedaSchede),
              Tab(text: t.schedaAllenamenti),
              Tab(text: t.schedaPeso),
              Tab(
                child: Badge(
                  isLabelVisible: _nucleo.questionari.nonLette(atletaId) > 0,
                  label: Text('${_nucleo.questionari.nonLette(atletaId)}'),
                  offset: const Offset(14, -6),
                  child: Text(t.schedaQuestionari),
                ),
              ),
              Tab(
                child: Badge(
                  isLabelVisible: _nucleo.messaggi.nonLetti(atletaId) > 0,
                  label: Text('${_nucleo.messaggi.nonLetti(atletaId)}'),
                  offset: const Offset(14, -6),
                  child: Text(t.schedaChat),
                ),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                PannelloTelefono(atleta: atleta, coach: coach, aggiornamenti: aggiornamenti),
                PannelloSchede(atleta: atleta, coach: coach, aggiornamenti: aggiornamenti),
                PannelloAllenamenti(atleta: atleta, coach: coach, aggiornamenti: aggiornamenti),
                PannelloPeso(atleta: atleta, coach: coach, aggiornamenti: aggiornamenti),
                PannelloQuestionari(atleta: atleta, coach: coach, aggiornamenti: aggiornamenti),
                PannelloChat(atleta: atleta, coach: coach, desktop: desktop, aggiornamenti: aggiornamenti),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _AzioneAtleta { rinomina, note, esportaJson, esportaCsv, archivia, elimina }

class _MenuAtleta extends StatelessWidget {
  const _MenuAtleta({
    required this.atleta,
    required this.coach,
    required this.desktop,
    required this.aggiornamenti,
  });

  final Atleta atleta;
  final Coach coach;
  final Desktop desktop;
  final Aggiornamenti aggiornamenti;

  NucleoCoach get _nucleo => coach.nucleo;

  Future<void> _scegli(BuildContext context, _AzioneAtleta azione) async {
    final t = Testi.of(context);
    switch (azione) {
      case _AzioneAtleta.rinomina:
        final nome = await chiediTesto(
          context,
          titolo: t.rinomina,
          etichetta: t.nomeAtleta,
          iniziale: atleta.nome,
        );
        if (nome != null && context.mounted) {
          await esegui(context, () async => _nucleo.atleti.modifica(atleta.id, nome: nome));
        }
      case _AzioneAtleta.note:
        final note = await chiediTesto(
          context,
          titolo: t.notePrivate,
          etichetta: t.notePrivateAiuto,
          iniziale: atleta.note,
          righe: 5,
        );
        if (note != null) _nucleo.atleti.modifica(atleta.id, note: note);
      case _AzioneAtleta.esportaJson:
        await _esporta(context, 'json', () {
          final dati = _nucleo.esportazioni.json(atleta.id);
          return const JsonEncoder.withIndent('  ').convert(dati);
        });
      case _AzioneAtleta.esportaCsv:
        await _esporta(context, 'csv', () => _nucleo.esportazioni.csv(atleta.id));
      case _AzioneAtleta.archivia:
        if (atleta.archiviato) {
          _nucleo.atleti.riattiva(atleta.id);
        } else {
          _nucleo.atleti.archivia(atleta.id);
        }
      case _AzioneAtleta.elimina:
        final sicuro = await conferma(
          context,
          titolo: t.eliminaAtletaTitolo(atleta.nome),
          testo: t.eliminaAtletaTesto,
          azione: t.elimina,
          pericolosa: true,
        );
        if (sicuro) _nucleo.atleti.elimina(atleta.id);
    }
    aggiornamenti.segnala();
  }

  Future<void> _esporta(
    BuildContext context,
    String estensione,
    String Function() contenuto,
  ) async {
    final t = Testi.of(context);
    final nome = atleta.nome.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
    final percorso = await desktop.scegliDoveSalvare('$nome.$estensione', estensione);
    if (percorso == null) return;
    await File(percorso).writeAsString(contenuto());
    if (context.mounted) avviso(context, t.esportato(percorso));
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return PopupMenuButton<_AzioneAtleta>(
      tooltip: t.altreAzioni,
      onSelected: (azione) => _scegli(context, azione),
      itemBuilder: (context) => [
        PopupMenuItem(value: _AzioneAtleta.rinomina, child: Text(t.rinomina)),
        PopupMenuItem(value: _AzioneAtleta.note, child: Text(t.notePrivate)),
        PopupMenuItem(value: _AzioneAtleta.esportaJson, child: Text(t.esportaJson)),
        PopupMenuItem(value: _AzioneAtleta.esportaCsv, child: Text(t.esportaCsv)),
        PopupMenuItem(
          value: _AzioneAtleta.archivia,
          child: Text(atleta.archiviato ? t.riattiva : t.archivia),
        ),
        PopupMenuItem(value: _AzioneAtleta.elimina, child: Text(t.elimina)),
      ],
    );
  }
}
