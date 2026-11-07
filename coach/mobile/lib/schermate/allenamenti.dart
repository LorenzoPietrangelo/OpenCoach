import 'package:flutter/material.dart';

import '../dati/fonte_dati.dart';
import '../dati/modelli.dart';
import '../dati/stato_coach.dart';
import '../l10n/testi.dart';
import 'comuni.dart';

/// Gli allenamenti ricevuti dall'atleta, dal più recente (§8.2).
class SezioneAllenamenti extends StatelessWidget {
  const SezioneAllenamenti({super.key, required this.stato, required this.atletaId});

  final StatoCoach stato;
  final String atletaId;

  @override
  Widget build(BuildContext context) => LettoreDati<Pagina<AllenamentoAtleta>>(
    generazione: stato.generazione,
    carica: () => stato.fonte.allenamenti(atletaId),
    costruisci: (context, pagina, ricarica) => _Elenco(stato: stato, atletaId: atletaId, prima: pagina),
  );
}

class _Elenco extends StatefulWidget {
  const _Elenco({required this.stato, required this.atletaId, required this.prima});

  final StatoCoach stato;
  final String atletaId;
  final Pagina<AllenamentoAtleta> prima;

  @override
  State<_Elenco> createState() => _ElencoState();
}

class _ElencoState extends State<_Elenco> {
  var _precedenti = const <AllenamentoAtleta>[];
  bool? _altri;
  var _carico = false;

  @override
  void didUpdateWidget(_Elenco vecchio) {
    super.didUpdateWidget(vecchio);
    if (!identical(vecchio.prima, widget.prima)) {
      _precedenti = const [];
      _altri = null;
    }
  }

  Future<void> _altriAllenamenti() async {
    final ultimo = _precedenti.lastOrNull ?? widget.prima.elementi.lastOrNull;
    if (ultimo == null) return;
    setState(() => _carico = true);
    try {
      final pagina = await widget.stato.fonte.allenamenti(widget.atletaId, prima: ultimo.id);
      if (!mounted) return;
      setState(() {
        _precedenti = [..._precedenti, ...pagina.elementi];
        _altri = pagina.altri;
      });
    } on ErroreCoach {
      // Il riquadro del problema spiega già: il pulsante resta.
    } finally {
      if (mounted) setState(() => _carico = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tutti = [...widget.prima.elementi, ..._precedenti];
    if (tutti.isEmpty) return ListaVuota(t.allenamentiVuoto);
    final altri = _altri ?? widget.prima.altri;
    return ListView.separated(
      itemCount: tutti.length + (altri ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == tutti.length) {
          return Center(
            child: TextButton(onPressed: _carico ? null : _altriAllenamenti, child: Text(t.allenamentiAltri)),
          );
        }
        return _RigaAllenamento(tutti[i]);
      },
    );
  }
}

class _RigaAllenamento extends StatelessWidget {
  const _RigaAllenamento(this.allenamento);

  final AllenamentoAtleta allenamento;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final (fatte, totali) = allenamento.serieFatte;
    final quando = allenamento.eseguitoIl;
    final durata = allenamento.durataMin;
    final rpe = allenamento.rpe;
    return ExpansionTile(
      title: Text(quando == null ? t.sconosciuto : dataOra(quando)),
      subtitle: Text(
        [
          t.allenamentoSerie(fatte, totali),
          if (durata != null) t.allenamentoDurata(numeroLeggibile(durata)),
          if (rpe != null) t.allenamentoSforzo(numeroLeggibile(rpe)),
        ].join(' · '),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (allenamento.note.isNotEmpty) ...[Text(allenamento.note), const SizedBox(height: 8)],
        for (final esercizio in allenamento.esercizi) _Esercizio(esercizio),
      ],
    );
  }
}

class _Esercizio extends StatelessWidget {
  const _Esercizio(this.esercizio);

  final EsercizioEseguito esercizio;

  String _serie(Testi t, SerieEseguita s) {
    if (!s.completata) return t.serieNonFatta;
    final kg = s.caricoKg;
    final ripetizioni = s.ripetizioni;
    final durata = s.durataS;
    final rpe = s.rpe;
    return [
      if (kg != null && ripetizioni != null)
        '${numeroLeggibile(kg)} kg × ${numeroLeggibile(ripetizioni)}'
      else if (ripetizioni != null)
        '× ${numeroLeggibile(ripetizioni)}'
      else if (kg != null)
        '${numeroLeggibile(kg)} kg',
      if (durata != null) '${numeroLeggibile(durata)} s',
      if (rpe != null) t.allenamentoSforzo(numeroLeggibile(rpe)),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(esercizio.nome, style: tema.textTheme.titleSmall),
          if (esercizio.note.isNotEmpty) Text(esercizio.note, style: tema.textTheme.bodySmall),
          for (final (i, serie) in esercizio.serie.indexed)
            Text(
              '${t.serieNumero(i + 1)}: ${_serie(t, serie)}',
              style: serie.completata ? null : TextStyle(color: tema.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
