import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';

import '../l10n/testi.dart';
import '../tema.dart';
import 'avvisi.dart';
import 'allenamento.dart';
import 'chat.dart';
import 'contenuto_scheda.dart';
import 'dettaglio_log.dart';
import 'dettaglio_scheda.dart';
import 'formati.dart';
import 'scollegamento.dart';
import 'stato_sync.dart';

/// Un coach con cui il collegamento è chiuso, dalle impostazioni: quello che
/// resta sul telefono, in sola lettura.
class PaginaCoach extends StatefulWidget {
  const PaginaCoach({super.key, required this.nucleo, required this.coachId});

  final NucleoAtleta nucleo;
  final int coachId;

  @override
  State<PaginaCoach> createState() => _PaginaCoachState();
}

class _PaginaCoachState extends State<PaginaCoach> {
  late final StreamSubscription<int> _cambiamenti;
  CoachCollegato? _coach;

  NucleoAtleta get _nucleo => widget.nucleo;

  @override
  void initState() {
    super.initState();
    _coach = _nucleo.collegamenti.cerca(widget.coachId);
    _cambiamenti = _nucleo.cambiamenti.listen((id) {
      if (id == widget.coachId && mounted) {
        setState(() => _coach = _nucleo.collegamenti.cerca(widget.coachId));
      }
    });
  }

  @override
  void dispose() {
    unawaited(_cambiamenti.cancel());
    super.dispose();
  }

  /// Dopo lo scollegamento, se l'atleta ha cancellato i dati del coach, la
  /// pagina non ha più niente da mostrare.
  Future<void> _chiudiSe(Future<bool> datiCancellati) async {
    if (await datiCancellati && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final coach = _coach;
    if (coach == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(testi.coachNonPiuPresente)),
      );
    }
    final attivo = coach.stato == StatoCollegamento.attivo;
    return Scaffold(
      appBar: AppBar(
        title: Text(coach.nomeCoach),
        actions: [
          IconButton(
            tooltip: testi.chat,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SchermataChat(nucleo: _nucleo, coachId: widget.coachId),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_outline),
          ),
          PopupMenuButton<void>(
            itemBuilder: (_) => [
              if (attivo)
                PopupMenuItem(
                  onTap: () => _chiudiSe(scollegaDalCoach(context, _nucleo, coach)),
                  child: Text(testi.scollega),
                )
              else
                PopupMenuItem(
                  onTap: () => _chiudiSe(cancellaDatiDelCoach(context, _nucleo, coach)),
                  child: Text(testi.cancellaDatiCoach),
                ),
            ],
          ),
        ],
      ),
      body: SezioneAllenamento(nucleo: _nucleo, coachId: widget.coachId),
    );
  }
}

/// La sezione Allenamento (§10.2): lo stato della sync (§7.5) con «Sincronizza
/// ora» e la scheda attiva. Storico e archivio delle schede restano chiusi
/// finché l'atleta non li apre. Da qui parte anche un allenamento libero.
class SezioneAllenamento extends StatefulWidget {
  const SezioneAllenamento({super.key, required this.nucleo, required this.coachId});

  final NucleoAtleta nucleo;
  final int coachId;

  @override
  State<SezioneAllenamento> createState() => _SezioneAllenamentoState();
}

class _SezioneAllenamentoState extends State<SezioneAllenamento> {
  late final StreamSubscription<int> _cambiamenti;
  CoachCollegato? _coach;
  var _attuali = <SchedaRicevuta>[];
  var _archiviate = <SchedaRicevuta>[];
  var _log = <LogAllenamento>[];

  /// La sync chiesta da qui non è ancora finita.
  var _sincronizzando = false;

  NucleoAtleta get _nucleo => widget.nucleo;

  @override
  void initState() {
    super.initState();
    _leggi();
    _cambiamenti = _nucleo.cambiamenti.listen((id) {
      if (id == widget.coachId && mounted) setState(_leggi);
    });
  }

  @override
  void dispose() {
    unawaited(_cambiamenti.cancel());
    super.dispose();
  }

  void _leggi() {
    final id = widget.coachId;
    _coach = _nucleo.collegamenti.cerca(id);
    _attuali = _nucleo.schede.elenco(id);
    _archiviate = _nucleo.schede.elenco(id, archiviate: true);
    _log = _nucleo.diario.elenco(id);
  }

  /// «Sincronizza ora» o trascinamento per aggiornare (§7.4).
  Future<void> _sincronizza() async {
    setState(() => _sincronizzando = true);
    try {
      await _nucleo.pianificatore.sincronizzaOra(widget.coachId);
    } finally {
      if (mounted) setState(() => _sincronizzando = false);
    }
  }

  Future<void> _allenamentoLibero() async {
    final testi = Testi.of(context);
    final messaggi = ScaffoldMessenger.of(context);
    final salvato = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SchermataAllenamento(
          nucleo: _nucleo,
          allenamento: AllenamentoInCorso.libero(
            inizio: _nucleo.contesto.orologio.adesso(),
            coachId: widget.coachId,
          ),
        ),
      ),
    );
    if (salvato == true) messaggi.avvisa(testi.allenamentoSalvato);
  }

  Future<void> _apriScheda(SchedaRicevuta scheda) => apriScheda(context, _nucleo, scheda);

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final coach = _coach;
    if (coach == null) return Center(child: Text(testi.coachNonPiuPresente));
    final attivo = coach.stato == StatoCollegamento.attivo;
    final nomi = nomiSedute([..._attuali, ..._archiviate]);
    final elenco = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        if (_attuali.isEmpty && _archiviate.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(testi.nessunaScheda, textAlign: TextAlign.center),
          ),
        if (_attuali.isNotEmpty) TitoloSezione(testi.schede),
        for (final scheda in _attuali)
          _VoceScheda(scheda, onTap: () => _apriScheda(scheda)),
        const SizedBox(height: 12),
        _Gruppo(
          child: ExpansionTile(
            key: const PageStorageKey('storico'),
            title: Text(
              _log.isEmpty ? testi.storico : '${testi.storico} (${_log.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            children: [
              if (_log.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(testi.nessunAllenamento, textAlign: TextAlign.center),
                ),
              for (final log in _log) ...[
                const Divider(),
                _VoceLog(
                  log,
                  titolo: titoloLog(testi, log, nomi),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DettaglioLog(nucleo: _nucleo, coachId: widget.coachId, logId: log.id),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_archiviate.isNotEmpty)
          _Gruppo(
            child: ExpansionTile(
              key: const PageStorageKey('archivio'),
              title: Text(
                '${testi.archivio} (${_archiviate.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              children: [
                for (final scheda in _archiviate)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: _VoceScheda(scheda, onTap: () => _apriScheda(scheda)),
                  ),
              ],
            ),
          ),
      ],
    );
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: _StatoSync(
              coach: coach,
              inCorso: _sincronizzando || _nucleo.sync.inCorso(coach.id),
              sincronizza: attivo ? _sincronizza : null,
            ),
          ),
          Expanded(
            child: attivo
                ? RefreshIndicator(onRefresh: _sincronizza, child: elenco)
                : elenco,
          ),
        ],
      ),
      floatingActionButton: attivo
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _allenamentoLibero,
              icon: const Icon(Icons.add),
              label: Text(testi.allenamentoLibero),
            )
          : null,
    );
  }
}

/// Una card che contiene una sezione apribile (Storico, Archivio).
class _Gruppo extends StatelessWidget {
  const _Gruppo({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(clipBehavior: Clip.antiAlias, child: child);
}

/// Stato della sync con il coach (§7.5) e «Sincronizza ora».
class _StatoSync extends StatelessWidget {
  const _StatoSync({
    required this.coach,
    required this.inCorso,
    required this.sincronizza,
  });

  final CoachCollegato coach;
  final bool inCorso;

  /// Null se il collegamento è chiuso: non si sincronizza più.
  final VoidCallback? sincronizza;

  @override
  Widget build(BuildContext context) {
    final colori = Theme.of(context).colorScheme;
    final tema = Theme.of(context).textTheme;
    final problema = coach.problema != null;
    final sincronizza = this.sincronizza;
    final righe = righeStatoSync(context, coach);
    final testo = problema ? colori.onErrorContainer : null;
    return Material(
      color: problema ? colori.errorContainer : colori.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: problema ? BorderSide.none : const BorderSide(color: ColoriAtleta.bordo),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(
          children: [
            problema
                ? IconaInCerchio(
                    Icons.error_outline,
                    colore: colori.onErrorContainer,
                    sfondo: colori.surface.withValues(alpha: 0.6),
                  )
                : const IconaInCerchio(
                    Icons.cloud_done_outlined,
                    colore: ColoriAtleta.primario,
                    sfondo: ColoriAtleta.contenitore,
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(righe.first, style: tema.titleSmall?.copyWith(color: testo)),
                  for (final riga in righe.skip(1))
                    Text(
                      riga,
                      style: tema.bodySmall?.copyWith(color: testo ?? colori.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (sincronizza != null && inCorso)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              )
            else if (sincronizza != null)
              TextButton.icon(
                onPressed: sincronizza,
                icon: const Icon(Icons.sync, size: 18),
                label: Text(Testi.of(context).sincronizzaOra),
              ),
          ],
        ),
      ),
    );
  }
}

class _VoceScheda extends StatelessWidget {
  const _VoceScheda(this.scheda, {required this.onTap});

  final SchedaRicevuta scheda;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final colori = Theme.of(context).colorScheme;
    final tema = Theme.of(context).textTheme;
    final dal = scheda.validaDal;
    final al = scheda.validaAl;
    final righe = [
      if (dal != null && al != null)
        testi.validaDalAl(giornoEMese(context, dal), giornoEMese(context, al))
      else if (dal != null)
        testi.validaDal(giornoEMese(context, dal)),
      testi.numeroSedute(scheda.sedute.length),
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: scheda.daVedere
            ? BorderSide(color: colori.primary, width: 1.5)
            : const BorderSide(color: ColoriAtleta.bordo),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: ColoriAtleta.superficieTenue,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            scheda.archiviata ? Icons.inventory_2_outlined : Icons.fitness_center,
            color: scheda.archiviata ? colori.onSurfaceVariant : colori.primary,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Revisione nuova, non ancora aperta (§10.2).
            if (scheda.daVedere)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: colori.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  testi.daVedere,
                  style: tema.labelMedium?.copyWith(color: colori.onPrimary),
                ),
              ),
            Text(
              scheda.titolo,
              style: scheda.daVedere
                  ? tema.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 17)
                  : tema.titleMedium,
            ),
          ],
        ),
        subtitle: Text(righe.join(' · ')),
        trailing: Icon(Icons.chevron_right, color: colori.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}

class _VoceLog extends StatelessWidget {
  const _VoceLog(this.log, {required this.titolo, required this.onTap});

  final LogAllenamento log;
  final String titolo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final eseguito = log.eseguitoIl;
    final durata = log.contenuto?['durata_min'];
    final quando = [
      if (eseguito != null) giornoEOra(context, eseguito),
      if (durata is int) testi.minuti(durata),
    ].join(' · ');
    // Gli allenamenti liberi si riconoscono dagli esercizi.
    final esercizi = log.contenuto?['scheda_id'] == null
        ? nomiEsercizi(log)
        : const <String>[];
    final (colore, sfondo) = log.rifiuto != null
        ? (ColoriAtleta.errore, ColoriAtleta.erroreContenitore)
        : log.inAttesa
        ? (ColoriAtleta.attesa, ColoriAtleta.attesaContenitore)
        : (ColoriAtleta.primario, ColoriAtleta.contenitore);
    final inviato = log.rifiuto == null && !log.inAttesa;
    return ListTile(
      leading: IconaInCerchio(iconaStatoLog(log), colore: colore, sfondo: sfondo),
      title: Text(
        [titolo, if (esercizi.isNotEmpty) esercizi.join(', ')].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tema.titleSmall,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(quando),
          Text(
            statoLog(testi, log),
            style: inviato ? null : TextStyle(color: colore, fontWeight: FontWeight.w500),
          ),
        ],
      ),
      isThreeLine: true,
      onTap: onTap,
    );
  }
}
