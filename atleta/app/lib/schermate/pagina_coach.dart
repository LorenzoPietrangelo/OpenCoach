import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';

import '../l10n/testi.dart';
import 'avvisi.dart';
import 'allenamento.dart';
import 'contenuto_scheda.dart';
import 'dettaglio_log.dart';
import 'dettaglio_scheda.dart';
import 'formati.dart';
import 'scollegamento.dart';
import 'stato_sync.dart';

/// Un coach (§10.2): lo stato della sync (§7.5) con «Sincronizza ora», le
/// sue schede con l'archivio e lo storico degli allenamenti. Da qui parte
/// anche un allenamento libero.
class PaginaCoach extends StatefulWidget {
  const PaginaCoach({super.key, required this.nucleo, required this.coachId});

  final NucleoAtleta nucleo;
  final int coachId;

  @override
  State<PaginaCoach> createState() => _PaginaCoachState();
}

class _PaginaCoachState extends State<PaginaCoach>
    with SingleTickerProviderStateMixin {
  late final _tab = TabController(length: 2, vsync: this);
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
    _tab.dispose();
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
    if (salvato != true) return;
    _tab.animateTo(1);
    messaggi.avvisa(testi.allenamentoSalvato);
  }

  /// Dopo lo scollegamento, se l'atleta ha cancellato i dati del coach, la
  /// pagina non ha più niente da mostrare.
  Future<void> _chiudiSe(Future<bool> datiCancellati) async {
    if (await datiCancellati && mounted) Navigator.of(context).pop();
  }

  Future<void> _apriScheda(SchedaRicevuta scheda) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DettaglioScheda(
        nucleo: _nucleo,
        coachId: widget.coachId,
        schedaId: scheda.id,
      ),
    ),
  );

  Future<void> _apriLog(LogAllenamento log) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          DettaglioLog(nucleo: _nucleo, coachId: widget.coachId, logId: log.id),
    ),
  );

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
    final daVedere = _attuali.where((s) => s.daVedere).length;
    Widget aggiornabile(Widget elenco) => attivo
        ? RefreshIndicator(onRefresh: _sincronizza, child: elenco)
        : elenco;
    return Scaffold(
      appBar: AppBar(
        title: Text(coach.nomeCoach),
        actions: [
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
      body: Column(
        children: [
          _StatoSync(
            coach: coach,
            inCorso: _sincronizzando || _nucleo.sync.inCorso(coach.id),
            sincronizza: attivo ? _sincronizza : null,
          ),
          TabBar(
            controller: _tab,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(testi.schede),
                    if (daVedere > 0) ...[
                      const SizedBox(width: 8),
                      Badge(label: Text('$daVedere')),
                    ],
                  ],
                ),
              ),
              Tab(text: testi.storico),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                aggiornabile(_elencoSchede(testi)),
                aggiornabile(_storico(testi)),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: attivo
          ? FloatingActionButton.extended(
              onPressed: _allenamentoLibero,
              icon: const Icon(Icons.add),
              label: Text(testi.allenamentoLibero),
            )
          : null,
    );
  }

  /// Le schede in corso, poi l'«Archivio» (§8.1).
  Widget _elencoSchede(Testi testi) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.only(bottom: 88),
    children: [
      if (_attuali.isEmpty && _archiviate.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(testi.nessunaScheda, textAlign: TextAlign.center),
        ),
      for (final scheda in _attuali)
        _VoceScheda(scheda, onTap: () => _apriScheda(scheda)),
      if (_archiviate.isNotEmpty) ...[
        ListTile(
          title: Text(
            testi.archivio,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final scheda in _archiviate)
          _VoceScheda(scheda, onTap: () => _apriScheda(scheda)),
      ],
    ],
  );

  /// I log, dal più recente, con lo stato rispetto al coach (§7.3).
  Widget _storico(Testi testi) {
    final nomi = nomiSedute([..._attuali, ..._archiviate]);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        if (_log.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(testi.nessunAllenamento, textAlign: TextAlign.center),
          ),
        for (final log in _log)
          _VoceLog(
            log,
            titolo: titoloLog(testi, log, nomi),
            onTap: () => _apriLog(log),
          ),
      ],
    );
  }
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
    final problema = coach.problema != null;
    final sincronizza = this.sincronizza;
    return Material(
      color: problema ? colori.errorContainer : colori.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                righeStatoSync(context, coach).join('\n'),
                style: TextStyle(
                  color: problema ? colori.onErrorContainer : null,
                ),
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
              TextButton(
                onPressed: sincronizza,
                child: Text(Testi.of(context).sincronizzaOra),
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
    final dal = scheda.validaDal;
    final al = scheda.validaAl;
    final righe = [
      if (dal != null && al != null)
        testi.validaDalAl(giornoEMese(context, dal), giornoEMese(context, al))
      else if (dal != null)
        testi.validaDal(giornoEMese(context, dal)),
      testi.numeroSedute(scheda.sedute.length),
    ];
    return ListTile(
      leading: Icon(
        scheda.archiviata ? Icons.inventory_2_outlined : Icons.fitness_center,
      ),
      title: Text(
        scheda.titolo,
        style: scheda.daVedere
            ? const TextStyle(fontWeight: FontWeight.bold)
            : null,
      ),
      subtitle: Text(righe.join(' · ')),
      // Revisione nuova, non ancora aperta (§10.2).
      trailing: scheda.daVedere
          ? Badge(
              label: Text(testi.daVedere),
              backgroundColor: colori.primary,
              textColor: colori.onPrimary,
            )
          : null,
      onTap: onTap,
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
    return ListTile(
      leading: Icon(
        iconaStatoLog(log),
        color: log.rifiuto == null ? null : Theme.of(context).colorScheme.error,
      ),
      title: Text(
        [titolo, if (esercizi.isNotEmpty) esercizi.join(', ')].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$quando\n${statoLog(testi, log)}'),
      isThreeLine: true,
      onTap: onTap,
    );
  }
}
