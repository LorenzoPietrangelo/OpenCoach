import 'dart:convert';
import 'dart:io';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../piattaforma/desktop.dart';
import '../servizi.dart';
import 'chat.dart';
import 'peso.dart';
import 'schede.dart';
import 'storico.dart';
import 'telefono.dart';

/// Dettaglio di un atleta. Finché un atleta nuovo non collega il telefono si
/// vede solo l'invito; poi schede, storico, peso e la chat, che contiene
/// anche i questionari. Invito e telefono stanno allora nel menu.
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
    final daLeggere = _nucleo.messaggi.nonLetti(atletaId) + _nucleo.questionari.nonLette(atletaId);
    final senzaTelefono = !atleta.archiviato && _nucleo.dispositivi.attivo(atletaId) == null;
    // Chi ha già avuto un telefono, o ha già dei dati, continua a vederli anche
    // se il telefono ora manca.
    final nuovo =
        senzaTelefono &&
        _nucleo.dispositivi.elenco(atletaId).isEmpty &&
        _nucleo.schede.elenco(atletaId).isEmpty &&
        _nucleo.questionari.inviati(atletaId).isEmpty &&
        _nucleo.messaggi.conversazione(atletaId).isEmpty;
    final intestazione = Padding(
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
          _MenuAtleta(atleta: atleta, coach: coach, desktop: desktop, aggiornamenti: aggiornamenti, nuovo: nuovo),
        ],
      ),
    );
    if (nuovo) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          intestazione,
          Expanded(child: PannelloCollegamento(atleta: atleta, coach: coach, aggiornamenti: aggiornamenti)),
        ],
      );
    }
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          intestazione,
          if (senzaTelefono)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Row(
                children: [
                  Expanded(child: Text(t.nessunTelefonoSpiegazione)),
                  const SizedBox(width: 16),
                  FilledButton.tonalIcon(
                    onPressed: () => nuovoInvito(context, atleta, coach, aggiornamenti),
                    icon: const Icon(Icons.add_link),
                    label: Text(t.nuovoInvito),
                  ),
                ],
              ),
            ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: t.schedaSchede),
              Tab(text: t.schedaStorico),
              Tab(text: t.schedaPeso),
              Tab(
                child: Badge(
                  isLabelVisible: daLeggere > 0,
                  label: Text('$daLeggere'),
                  offset: const Offset(14, -6),
                  child: Text(t.schedaChat),
                ),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                PannelloSchede(atleta: atleta, coach: coach, aggiornamenti: aggiornamenti),
                PannelloStorico(atleta: atleta, coach: coach, aggiornamenti: aggiornamenti),
                PannelloPeso(atleta: atleta, coach: coach, aggiornamenti: aggiornamenti),
                PannelloChat(atleta: atleta, coach: coach, desktop: desktop, aggiornamenti: aggiornamenti),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _AzioneAtleta { invito, scollega, rinomina, note, esportaJson, esportaCsv, archivia, elimina }

class _MenuAtleta extends StatelessWidget {
  const _MenuAtleta({
    required this.atleta,
    required this.coach,
    required this.desktop,
    required this.aggiornamenti,
    required this.nuovo,
  });

  final Atleta atleta;
  final Coach coach;
  final Desktop desktop;
  final Aggiornamenti aggiornamenti;

  /// L'invito è già in vista: nel menu non serve.
  final bool nuovo;

  NucleoCoach get _nucleo => coach.nucleo;

  Future<void> _scegli(BuildContext context, _AzioneAtleta azione) async {
    final t = Testi.of(context);
    switch (azione) {
      case _AzioneAtleta.invito:
        await nuovoInvito(context, atleta, coach, aggiornamenti);
      case _AzioneAtleta.scollega:
        final dispositivo = _nucleo.dispositivi.attivo(atleta.id);
        if (dispositivo != null) {
          await scollegaTelefono(context, atleta, dispositivo, coach, aggiornamenti);
        }
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
        if (!atleta.archiviato && !nuovo) PopupMenuItem(value: _AzioneAtleta.invito, child: Text(t.nuovoInvito)),
        if (_nucleo.dispositivi.attivo(atleta.id) != null)
          PopupMenuItem(value: _AzioneAtleta.scollega, child: Text(t.scollegaTelefono)),
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
