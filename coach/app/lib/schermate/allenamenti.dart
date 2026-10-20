import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../servizi.dart';

/// Allenamenti registrati dall'atleta, in sola lettura (§9.3).
class PannelloAllenamenti extends StatelessWidget {
  const PannelloAllenamenti({
    super.key,
    required this.atleta,
    required this.coach,
    required this.aggiornamenti,
  });

  final Atleta atleta;
  final Coach coach;
  final Aggiornamenti aggiornamenti;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: aggiornamenti,
    builder: (context, _) => _elenco(context),
  );

  Widget _elenco(BuildContext context) {
    final t = Testi.of(context);
    final allenamenti = coach.nucleo.allenamenti.elenco(atleta.id);
    if (allenamenti.isEmpty) {
      return Padding(padding: const EdgeInsets.all(24), child: Text(t.nessunAllenamento));
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        for (final a in allenamenti)
          Card(
            child: ListTile(
              leading: const Icon(Icons.fitness_center),
              title: Text(_titolo(t, a)),
              subtitle: Text(
                [
                  dataOra(a.eseguitoIl),
                  if (a.contenuto['durata_min'] is int) t.minuti(a.contenuto['durata_min'] as int),
                  if (a.contenuto['rpe'] is num) t.rpeSeduta(_numero(a.contenuto['rpe'])),
                  if (a.revisioneNonAttuale) t.suRevisioneSuperata,
                ].join(' · '),
              ),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => _DialogoAllenamento(
                  allenamento: a,
                  prescritta: coach.nucleo.allenamenti.sedutaPrescritta(a),
                  titolo: _titolo(t, a),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _titolo(Testi t, Allenamento a) {
    final nome = coach.nucleo.allenamenti.sedutaPrescritta(a)?['nome'];
    if (nome is String && nome.isNotEmpty) return nome;
    return a.contenuto['scheda_id'] == null ? t.allenamentoLibero : t.sedutaNonTrovata;
  }
}

String _numero(Object? valore) {
  if (valore is! num) return '';
  final testo = valore == valore.roundToDouble() ? '${valore.round()}' : '$valore';
  return testo.replaceAll('.', ',');
}

/// Seduta eseguita, esercizio per esercizio, accanto alla prescrizione della
/// revisione che l'atleta seguiva.
class _DialogoAllenamento extends StatelessWidget {
  const _DialogoAllenamento({
    required this.allenamento,
    required this.prescritta,
    required this.titolo,
  });

  final Allenamento allenamento;
  final Map<String, Object?>? prescritta;
  final String titolo;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final l = allenamento.contenuto;
    final prescrizioni = <String, List<Object?>>{
      for (final e in (prescritta?['esercizi'] as List<Object?>? ?? const []).whereType<Map<String, Object?>>())
        if (e['id'] is String) e['id'] as String: (e['prescrizione'] as List<Object?>?) ?? const [],
    };
    final esercizi = (l['esercizi'] as List<Object?>? ?? const []).whereType<Map<String, Object?>>();
    final stile = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(titolo),
      content: SizedBox(
        width: 560,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(dataOra(allenamento.eseguitoIl)),
            if (allenamento.revisioneNonAttuale)
              Text(t.suRevisioneSuperataSpiegazione, style: stile.bodySmall),
            if (l['note'] is String && (l['note'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l['note'] as String),
            ],
            for (final e in esercizi) ...[
              const SizedBox(height: 16),
              Text(e['nome'] as String? ?? '', style: stile.titleSmall),
              if (prescrizioni[e['esercizio_id']] case final righe? when righe.isNotEmpty)
                Text(
                  t.prescritto(righe.whereType<Map<String, Object?>>().map(_rigaPrescrizione).join('; ')),
                  style: stile.bodySmall,
                ),
              if (e['esercizio_id'] == null) Text(t.esercizioAggiunto, style: stile.bodySmall),
              for (final (i, s) in (e['serie'] as List<Object?>? ?? const [])
                  .whereType<Map<String, Object?>>()
                  .indexed)
                Text(_serie(t, i + 1, s)),
              if (e['note'] is String && (e['note'] as String).isNotEmpty)
                Text(e['note'] as String, style: stile.bodySmall),
            ],
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t.chiudi))],
    );
  }

  String _rigaPrescrizione(Map<String, Object?> r) => [
    if (r['serie'] != null || r['ripetizioni'] != null) '${r['serie'] ?? '?'} × ${r['ripetizioni'] ?? '?'}',
    if (r['carico'] is String) r['carico'] as String,
    if (r['recupero_s'] is int) '${r['recupero_s']} s',
  ].join(', ');

  String _serie(Testi t, int numero, Map<String, Object?> s) {
    final parti = [
      if (s['ripetizioni'] is int) t.ripetizioniEseguite(s['ripetizioni'] as int),
      if (s['carico_kg'] is num) '${_numero(s['carico_kg'])} kg',
      if (s['durata_s'] is int) '${s['durata_s']} s',
      if (s['rpe'] is num) 'RPE ${_numero(s['rpe'])}',
    ];
    final esito = s['completata'] == true ? '' : ' (${t.nonCompletata})';
    return '${t.serieNumero(numero)}: ${parti.join(', ')}$esito';
  }
}
