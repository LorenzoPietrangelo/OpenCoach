import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';

import '../l10n/testi.dart';
import 'avvisi.dart';
import 'allenamento.dart';
import 'contenuto_scheda.dart';
import 'formati.dart';

/// Apre una scheda toccata nell'elenco. Se si può eseguire parte subito
/// l'allenamento: con più sedute l'atleta sceglie prima quale, e da lì può
/// anche vedere tutta la scheda. Una scheda archiviata, del collegamento
/// chiuso o senza sedute si apre in sola lettura ([DettaglioScheda]).
Future<void> apriScheda(
  BuildContext context,
  NucleoAtleta nucleo,
  SchedaRicevuta scheda,
) async {
  final coach = nucleo.collegamenti.cerca(scheda.coachId);
  final eseguibile = coach?.stato == StatoCollegamento.attivo &&
      !scheda.archiviata &&
      scheda.sedute.isNotEmpty;
  Future<void> riepilogo() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DettaglioScheda(
        nucleo: nucleo,
        coachId: scheda.coachId,
        schedaId: scheda.id,
      ),
    ),
  );
  if (!eseguibile) return riepilogo();
  final seduta = scheda.sedute.length == 1
      ? scheda.sedute.single
      : await _scegliSeduta(context, scheda, riepilogo);
  if (seduta == null || !context.mounted) return;
  // L'atleta sta aprendo l'ultima revisione: l'avviso sparisce (§10.2).
  if (scheda.daVedere) nucleo.schede.segnaVista(scheda.coachId, scheda.id);
  await iniziaSeduta(context, nucleo, scheda, seduta);
}

/// La seduta da fare oggi; null se l'atleta rinuncia o apre tutta la scheda.
Future<Seduta?> _scegliSeduta(
  BuildContext context,
  SchedaRicevuta scheda,
  Future<void> Function() riepilogo,
) async {
  final testi = Testi.of(context);
  final scelta = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              scheda.titolo,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Text(testi.qualeSeduta),
          ),
          for (final seduta in scheda.sedute)
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(seduta.nome),
              subtitle: Text(
                seduta.esercizi.map((e) => e.nome).join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context).pop(seduta),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(testi.vediTuttaLaScheda),
            onTap: () => Navigator.of(context).pop(riepilogo),
          ),
        ],
      ),
    ),
  );
  if (scelta is Future<void> Function()) {
    if (context.mounted) await scelta();
    return null;
  }
  return scelta as Seduta?;
}

/// Avvia l'allenamento di una seduta della scheda (§10.2).
Future<void> iniziaSeduta(
  BuildContext context,
  NucleoAtleta nucleo,
  SchedaRicevuta scheda,
  Seduta seduta,
) async {
  final testi = Testi.of(context);
  final messaggi = ScaffoldMessenger.of(context);
  final salvato = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => SchermataAllenamento(
        nucleo: nucleo,
        allenamento: AllenamentoInCorso.daSeduta(
          scheda,
          seduta.id,
          inizio: nucleo.contesto.orologio.adesso(),
        ),
        titolo: seduta.nome,
        seduta: seduta,
        noteScheda: scheda.note,
      ),
    ),
  );
  if (salvato == true) messaggi.avvisa(testi.allenamentoSalvato);
}

/// Una scheda (§8.1, §10.2): validità, note, sedute ed esercizi con la
/// prescrizione. Aprendola l'atleta vede l'ultima revisione, e l'avviso di
/// revisione nuova sparisce. Da una seduta parte l'allenamento, salvo che la
/// scheda sia archiviata o il collegamento chiuso: allora è in sola lettura.
class DettaglioScheda extends StatefulWidget {
  const DettaglioScheda({
    super.key,
    required this.nucleo,
    required this.coachId,
    required this.schedaId,
  });

  final NucleoAtleta nucleo;
  final int coachId;
  final String schedaId;

  @override
  State<DettaglioScheda> createState() => _DettaglioSchedaState();
}

class _DettaglioSchedaState extends State<DettaglioScheda> {
  late final StreamSubscription<int> _cambiamenti;
  SchedaRicevuta? _scheda;
  CoachCollegato? _coach;

  /// L'atleta non aveva ancora visto questa revisione.
  var _nuova = false;

  @override
  void initState() {
    super.initState();
    _leggi();
    _cambiamenti = widget.nucleo.cambiamenti.listen((id) {
      if (id == widget.coachId && mounted) setState(_leggi);
    });
  }

  @override
  void dispose() {
    unawaited(_cambiamenti.cancel());
    super.dispose();
  }

  /// Rilegge la scheda; se è arrivata una revisione che l'atleta non ha
  /// visto, ora la sta vedendo.
  void _leggi() {
    _coach = widget.nucleo.collegamenti.cerca(widget.coachId);
    final scheda = _scheda = widget.nucleo.schede.cerca(
      widget.coachId,
      widget.schedaId,
    );
    if (scheda != null && scheda.daVedere) {
      _nuova = true;
      widget.nucleo.schede.segnaVista(widget.coachId, scheda.id);
    }
  }

  Future<void> _inizia(SchedaRicevuta scheda, Seduta seduta) =>
      iniziaSeduta(context, widget.nucleo, scheda, seduta);

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final scheda = _scheda;
    if (scheda == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(testi.schedaNonPiuPresente)),
      );
    }
    final attivo = _coach?.stato == StatoCollegamento.attivo;
    final eseguibile = attivo && !scheda.archiviata;
    final dal = scheda.validaDal;
    final al = scheda.validaAl;
    return Scaffold(
      appBar: AppBar(title: Text(scheda.titolo)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (dal != null && al != null)
            Text(
              testi.validaDalAl(
                giornoEMese(context, dal),
                giornoEMese(context, al),
              ),
              style: tema.titleSmall,
            )
          else if (dal != null)
            Text(
              testi.validaDal(giornoEMese(context, dal)),
              style: tema.titleSmall,
            ),
          Text(
            testi.revisioneRicevuta(
              scheda.revisione,
              giornoEMese(context, scheda.ricevutaIl.toLocal()),
            ),
            style: tema.bodySmall,
          ),
          if (_nuova)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                testi.revisioneNuova,
                style: tema.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          if (scheda.archiviata || !attivo)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                scheda.archiviata
                    ? testi.schedaArchiviata
                    : testi.collegamentoChiuso,
                style: tema.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          if (scheda.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(scheda.note),
            ),
          const SizedBox(height: 8),
          for (final seduta in scheda.sedute)
            _CartaSeduta(
              seduta,
              inizia: eseguibile ? () => _inizia(scheda, seduta) : null,
            ),
        ],
      ),
    );
  }
}

class _CartaSeduta extends StatelessWidget {
  const _CartaSeduta(this.seduta, {required this.inizia});

  final Seduta seduta;

  /// Null se la seduta non si può eseguire.
  final VoidCallback? inizia;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final inizia = this.inizia;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(seduta.nome, style: tema.titleMedium),
            if (seduta.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(seduta.note, style: tema.bodyMedium),
              ),
            for (final esercizio in seduta.esercizi)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(esercizio.nome, style: tema.titleSmall),
                    for (final riga in esercizio.prescrizione)
                      Text(
                        testoPrescrizione(
                          testi,
                          serie: riga.serie,
                          ripetizioni: riga.ripetizioni,
                          carico: riga.carico,
                          recupero: riga.recupero,
                          rir: riga.rir,
                        ),
                      ),
                    if (esercizio.note.isNotEmpty)
                      Text(
                        esercizio.note,
                        style: tema.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
            if (inizia != null)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.icon(
                    onPressed: inizia,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(testi.inizia),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
