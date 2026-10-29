import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:protocollo/protocollo.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../servizi.dart';

/// Libreria degli esercizi (§9.3): nome, note e link al video. Le schede la
/// seguono per nome, e alla pubblicazione ogni esercizio prende il suo video.
class SchermataLibreria extends StatelessWidget {
  const SchermataLibreria({
    super.key,
    required this.coach,
    required this.aggiornamenti,
  });

  final Coach coach;
  final Aggiornamenti aggiornamenti;

  NucleoCoach get _nucleo => coach.nucleo;

  Future<void> _modifica(BuildContext context, [EsercizioLibreria? esercizio]) async {
    final salvato = await modificaEsercizioLibreria(
      context,
      _nucleo,
      esercizio: esercizio,
    );
    if (salvato && context.mounted) {
      aggiornamenti.segnala();
      await proponiAggiornamentoVideo(context, _nucleo, aggiornamenti);
    }
  }

  Future<void> _elimina(BuildContext context, EsercizioLibreria esercizio) async {
    final t = Testi.of(context);
    final sicuro = await conferma(
      context,
      titolo: t.eliminaEsercizioTitolo(esercizio.nome),
      testo: t.eliminaEsercizioTesto,
      azione: t.elimina,
      pericolosa: true,
    );
    if (!sicuro || !context.mounted) return;
    _nucleo.libreria.elimina(esercizio.id);
    aggiornamenti.segnala();
    await proponiAggiornamentoVideo(context, _nucleo, aggiornamenti);
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return ListenableBuilder(
      listenable: aggiornamenti,
      builder: (context, _) {
        final esercizi = _nucleo.libreria.elenco();
        final daAggiornare = _nucleo.schede.conVideoDaAggiornare().length;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t.sezioneLibreria, style: Theme.of(context).textTheme.headlineSmall),
                ),
                FilledButton.icon(
                  onPressed: () => _modifica(context),
                  icon: const Icon(Icons.add),
                  label: Text(t.nuovoEsercizio),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(t.libreriaSpiegazione),
            if (daAggiornare > 0)
              Card(
                margin: const EdgeInsets.only(top: 16),
                child: ListTile(
                  leading: const Icon(Icons.sync_problem),
                  title: Text(t.videoDaAggiornare(daAggiornare)),
                  trailing: TextButton(
                    onPressed: () => aggiornaVideo(context, _nucleo, aggiornamenti),
                    child: Text(t.aggiornaVideo),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (esercizi.isEmpty) Text(t.libreriaVuota),
            for (final esercizio in esercizi)
              Card(
                child: ListTile(
                  leading: Icon(
                    esercizio.video == null ? Icons.fitness_center : Icons.smart_display_outlined,
                  ),
                  title: Text(esercizio.nome),
                  subtitle: Text(
                    [
                      if (esercizio.video != null) esercizio.video!,
                      if (esercizio.note.isNotEmpty) esercizio.note,
                    ].join('\n'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _modifica(context, esercizio),
                  trailing: IconButton(
                    tooltip: t.elimina,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _elimina(context, esercizio),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Crea o modifica un esercizio della libreria; vero se il coach ha salvato.
/// [nome] precompila il nome di un esercizio nuovo.
Future<bool> modificaEsercizioLibreria(
  BuildContext context,
  NucleoCoach nucleo, {
  EsercizioLibreria? esercizio,
  String nome = '',
}) async {
  final salvato = await showDialog<bool>(
    context: context,
    builder: (_) => _DialogoEsercizio(nucleo: nucleo, esercizio: esercizio, nome: nome),
  );
  return salvato ?? false;
}

/// Dopo un cambiamento della libreria, propone di mandare i video nuovi alle
/// schede pubblicate che li usano.
Future<void> proponiAggiornamentoVideo(
  BuildContext context,
  NucleoCoach nucleo,
  Aggiornamenti aggiornamenti,
) async {
  final t = Testi.of(context);
  final schede = nucleo.schede.conVideoDaAggiornare().length;
  if (schede == 0) return;
  final aggiorna = await conferma(
    context,
    titolo: t.aggiornaVideoTitolo,
    testo: '${t.videoDaAggiornare(schede)} ${t.aggiornaVideoTesto}',
    azione: t.aggiornaVideo,
  );
  if (aggiorna && context.mounted) aggiornaVideo(context, nucleo, aggiornamenti);
}

/// Ripubblica le schede con i video della libreria, senza le bozze.
void aggiornaVideo(BuildContext context, NucleoCoach nucleo, Aggiornamenti aggiornamenti) {
  var aggiornate = 0;
  for (final scheda in nucleo.schede.conVideoDaAggiornare()) {
    if (nucleo.schede.aggiornaVideo(scheda.id) != null) aggiornate++;
  }
  aggiornamenti.segnala();
  avviso(context, Testi.of(context).videoAggiornati(aggiornate));
}

/// Il link come lo scrive il coach, con https:// aggiunto se manca; null se
/// non è un link https valido.
String? normalizzaLinkVideo(String testo) {
  var link = testo.trim();
  if (!link.contains('://')) link = 'https://$link';
  return analizzaLinkVideo(link) == null ? null : link;
}

class _DialogoEsercizio extends StatefulWidget {
  const _DialogoEsercizio({required this.nucleo, required this.esercizio, required this.nome});

  final NucleoCoach nucleo;
  final EsercizioLibreria? esercizio;
  final String nome;

  @override
  State<_DialogoEsercizio> createState() => _DialogoEsercizioState();
}

class _DialogoEsercizioState extends State<_DialogoEsercizio> {
  late final _nome = TextEditingController(text: widget.esercizio?.nome ?? widget.nome);
  late final _note = TextEditingController(text: widget.esercizio?.note ?? '');
  late final _video = TextEditingController(text: widget.esercizio?.video ?? '');
  String? _erroreVideo;
  String? _errore;

  @override
  void dispose() {
    _nome.dispose();
    _note.dispose();
    _video.dispose();
    super.dispose();
  }

  void _salva() {
    final t = Testi.of(context);
    final scritto = _video.text.trim();
    final link = scritto.isEmpty ? null : normalizzaLinkVideo(scritto);
    if (scritto.isNotEmpty && link == null) {
      setState(() => _erroreVideo = t.videoNonValido);
      return;
    }
    try {
      widget.nucleo.libreria.salva(
        id: widget.esercizio?.id,
        nome: _nome.text,
        note: _note.text.trim(),
        video: link,
      );
    } on OperazioneNonValida catch (e) {
      setState(() => _errore = e.messaggio);
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return AlertDialog(
      title: Text(widget.esercizio == null ? t.nuovoEsercizio : t.modificaEsercizio),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nome,
              autofocus: widget.esercizio == null && widget.nome.isEmpty,
              decoration: InputDecoration(labelText: t.nomeEsercizio, errorText: _errore),
              onChanged: (_) => setState(() => _errore = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _video,
              decoration: InputDecoration(
                labelText: t.linkVideo,
                helperText: t.linkVideoAiuto,
                errorText: _erroreVideo,
              ),
              onChanged: (_) => setState(() => _erroreVideo = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(labelText: t.noteEsercizio, helperText: t.noteLibreriaAiuto),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.annulla)),
        FilledButton(onPressed: _salva, child: Text(t.salva)),
      ],
    );
  }
}
