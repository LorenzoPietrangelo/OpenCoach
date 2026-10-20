import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';

import '../l10n/testi.dart';
import 'avvisi.dart';
import 'allenamento.dart';
import 'contenuto_scheda.dart';
import 'formati.dart';
import 'stato_sync.dart';

/// Nome di un allenamento dello storico: la sua seduta, se la scheda è
/// ancora sul telefono.
String titoloLog(
  Testi testi,
  LogAllenamento log,
  Map<String, String> nomiSedute,
) {
  final contenuto = log.contenuto;
  final nome = nomiSedute[contenuto?['seduta_id']];
  if (nome != null) return nome;
  return contenuto?['scheda_id'] == null
      ? testi.allenamentoLibero
      : testi.allenamento;
}

/// Nomi degli esercizi di un log, nell'ordine in cui sono stati eseguiti.
List<String> nomiEsercizi(LogAllenamento log) => [
  if (log.contenuto?['esercizi'] case final List<Object?> esercizi)
    for (final esercizio in esercizi)
      if (esercizio case {'nome': final String nome}) nome,
];

/// Un allenamento dello storico (§10.2), con il suo stato rispetto al coach
/// (§7.3): si modifica e si elimina, e se il coach l'ha rifiutato si rimette
/// in coda. Ogni modifica incrementa `rev` e rimette il log in coda.
class DettaglioLog extends StatefulWidget {
  const DettaglioLog({
    super.key,
    required this.nucleo,
    required this.coachId,
    required this.logId,
  });

  final NucleoAtleta nucleo;
  final int coachId;
  final String logId;

  @override
  State<DettaglioLog> createState() => _DettaglioLogState();
}

class _DettaglioLogState extends State<DettaglioLog> {
  late final StreamSubscription<int> _cambiamenti;
  LogAllenamento? _log;
  CoachCollegato? _coach;

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
    _log = _nucleo.diario.cerca(widget.coachId, widget.logId);
    _coach = _nucleo.collegamenti.cerca(widget.coachId);
  }

  Future<void> _modifica(
    LogAllenamento log,
    String titolo,
    Seduta? seduta,
  ) async {
    final testi = Testi.of(context);
    final messaggi = ScaffoldMessenger.of(context);
    final salvato = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SchermataAllenamento(
          nucleo: _nucleo,
          allenamento: AllenamentoInCorso.daLog(log),
          titolo: titolo,
          seduta: seduta,
          logId: log.id,
        ),
      ),
    );
    if (salvato == true) {
      messaggi.avvisa(testi.modificheSalvate);
    }
  }

  Future<void> _elimina() async {
    final testi = Testi.of(context);
    final conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(testi.eliminareAllenamento),
        content: Text(testi.spiegazioneElimina),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(testi.annulla),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(testi.elimina),
          ),
        ],
      ),
    );
    if (conferma != true || !mounted) return;
    try {
      _nucleo.diario.elimina(widget.coachId, widget.logId);
    } on OperazioneNonAmmessa catch (e) {
      ScaffoldMessenger.of(context).avvisa(e.messaggio);
      return;
    }
    Navigator.of(context).pop();
  }

  void _ritenta() {
    final messaggi = ScaffoldMessenger.of(context);
    try {
      _nucleo.diario.ritenta(widget.coachId, widget.logId);
    } on OperazioneNonAmmessa catch (e) {
      messaggi.avvisa(e.messaggio);
      return;
    }
    messaggi.avvisa(Testi.of(context).allenamentoInCoda);
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final log = _log;
    if (log == null || log.eliminato) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(testi.allenamentoEliminato)),
      );
    }
    final lettura = AllenamentoInCorso.daLog(log);
    final schedaId = lettura.schedaId;
    final scheda = schedaId == null
        ? null
        : _nucleo.schede.cerca(widget.coachId, schedaId);
    final seduta = scheda?.seduta(lettura.sedutaId);
    final titolo = seduta?.nome ?? titoloLog(testi, log, const {});
    final attivo = _coach?.stato == StatoCollegamento.attivo;
    final rpe = lettura.rpe;
    final durata = lettura.durataMin;
    return Scaffold(
      appBar: AppBar(
        title: Text(titolo),
        actions: [
          if (attivo) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: testi.modifica,
              // La prescrizione si mostra solo se è quella della revisione
              // usata nell'allenamento.
              onPressed: () => _modifica(
                log,
                titolo,
                scheda?.revisione == lettura.schedaRevisione ? seduta : null,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: testi.elimina,
              onPressed: _elimina,
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatoLog(log, ritenta: attivo ? _ritenta : null),
          const SizedBox(height: 12),
          Text(giornoEOra(context, lettura.inizio), style: tema.titleMedium),
          if (durata != null) Text(testi.durataDi(durata)),
          if (rpe != null) Text(testi.rpeDellaSeduta(numero(rpe))),
          if (lettura.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(lettura.note),
            ),
          for (final esercizio in lettura.esercizi)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(esercizio.nome, style: tema.titleSmall),
                    if (esercizio.note.isNotEmpty)
                      Text(
                        esercizio.note,
                        style: tema.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    for (final (indice, serie) in esercizio.serie.indexed)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              serie.completata
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 18,
                              semanticLabel: serie.completata
                                  ? testi.fatta
                                  : testi.nonFatta,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${indice + 1}. ${_testoSerie(testi, serie)}',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _testoSerie(Testi testi, SerieInCorso serie) {
    final ripetizioni = serie.ripetizioni;
    final durataS = serie.durataS;
    final carico = serie.caricoKg;
    final rpe = serie.rpe;
    final parti = [
      if (ripetizioni != null) testi.ripetizioniN(ripetizioni),
      if (durataS != null) _durataSerie(testi, durataS),
      if (carico != null) testi.chiliN(numero(carico)),
      if (rpe != null) testi.rpeN(numero(rpe)),
    ];
    return parti.isEmpty ? testi.nessunValore : parti.join(' · ');
  }

  /// «45 s», «40 min» o «1:30».
  String _durataSerie(Testi testi, int secondi) => secondi < 60
      ? testi.secondiN(secondi)
      : secondi % 60 == 0
      ? testi.minuti(secondi ~/ 60)
      : durata(Duration(seconds: secondi));
}

/// Stato del log rispetto al coach (§7.3). Un log rifiutato non si ritenta
/// da solo: l'atleta lo rimette in coda.
class _StatoLog extends StatelessWidget {
  const _StatoLog(this.log, {required this.ritenta});

  final LogAllenamento log;

  /// Null se il collegamento è chiuso.
  final VoidCallback? ritenta;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final colori = Theme.of(context).colorScheme;
    final rifiutato = log.rifiuto != null;
    final ritenta = this.ritenta;
    final colore = rifiutato ? colori.onErrorContainer : null;
    return Card(
      margin: EdgeInsets.zero,
      color: rifiutato ? colori.errorContainer : colori.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                Icon(iconaStatoLog(log), color: colore),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    statoLog(testi, log),
                    style: TextStyle(color: colore),
                  ),
                ),
              ],
            ),
            if (rifiutato && ritenta != null)
              TextButton(onPressed: ritenta, child: Text(testi.rimettiInCoda)),
          ],
        ),
      ),
    );
  }
}
