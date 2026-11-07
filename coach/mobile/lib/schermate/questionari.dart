import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../dati/fonte_dati.dart';
import '../dati/modelli.dart';
import '../dati/stato_coach.dart';
import '../l10n/testi.dart';
import 'comuni.dart';

/// I questionari mandati all'atleta e le sue risposte, con le foto (§8.6). Si
/// mandano solo dal PC.
class SezioneQuestionari extends StatelessWidget {
  const SezioneQuestionari({super.key, required this.stato, required this.atletaId});

  final StatoCoach stato;
  final String atletaId;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return LettoreDati<List<QuestionarioAtleta>>(
      generazione: stato.generazione,
      carica: () => stato.fonte.questionari(atletaId),
      costruisci: (context, questionari, ricarica) => questionari.isEmpty
          ? ListaVuota(t.questionariVuoto)
          : ListView.separated(
              itemCount: questionari.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final q = questionari[i];
                final nuovo = q.risposto && !q.letto;
                return ListTile(
                  title: Text(q.titolo, style: nuovo ? const TextStyle(fontWeight: FontWeight.w600) : null),
                  subtitle: Text(_sottotitolo(t, q)),
                  trailing: nuovo ? Badge(label: Text(t.questionarioNuovo)) : null,
                  onTap: q.risposto
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => _Risposte(stato: stato, questionario: q)),
                        )
                      : null,
                );
              },
            ),
    );
  }

  String _sottotitolo(Testi t, QuestionarioAtleta q) {
    final risposto = q.rispostoIl;
    final inviato = q.inviatoIl;
    return switch (q.stato) {
      'annullato' => t.questionarioAnnullato,
      'risposto' when risposto != null => t.questionarioRisposto(dataOra(risposto)),
      _ => t.questionarioInAttesa(inviato == null ? t.sconosciuto : dataOra(inviato)),
    };
  }
}

class _Risposte extends StatefulWidget {
  const _Risposte({required this.stato, required this.questionario});

  final StatoCoach stato;
  final QuestionarioAtleta questionario;

  @override
  State<_Risposte> createState() => _RisposteState();
}

class _RisposteState extends State<_Risposte> {
  @override
  void initState() {
    super.initState();
    if (!widget.questionario.letto) unawaited(_segnaLetto());
  }

  Future<void> _segnaLetto() async {
    try {
      await widget.stato.fonte.segnaQuestionarioLetto(widget.questionario.id);
      widget.stato.riprova();
    } on ErroreCoach {
      // Resta nuovo: si segna la prossima volta che si apre.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context);
    final q = widget.questionario;
    return Scaffold(
      appBar: AppBar(title: Text(q.titolo)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (q.descrizione.isNotEmpty) ...[Text(q.descrizione), const SizedBox(height: 16)],
            for (final r in q.risposte) ...[
              Text(r.domanda, style: tema.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                r.risposta ?? t.questionarioNessunaRisposta,
                style: r.risposta == null ? TextStyle(color: tema.colorScheme.onSurfaceVariant) : null,
              ),
              const SizedBox(height: 14),
            ],
            if (q.foto.isNotEmpty) ...[
              Text(t.questionarioFoto, style: tema.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final id in q.foto) _Foto(stato: widget.stato, id: id),
            ],
          ],
        ),
      ),
    );
  }
}

/// Una foto: si scarica quando serve e resta solo in memoria (§16.4).
class _Foto extends StatefulWidget {
  const _Foto({required this.stato, required this.id});

  final StatoCoach stato;
  final String id;

  @override
  State<_Foto> createState() => _FotoState();
}

class _FotoState extends State<_Foto> {
  late Future<Uint8List> _byte = widget.stato.fonte.foto(widget.id);

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FutureBuilder<Uint8List>(
        future: _byte,
        builder: (context, istantanea) {
          if (istantanea.hasError) {
            return Column(
              children: [
                Text(t.questionarioFotoErrore),
                TextButton(
                  onPressed: () => setState(() => _byte = widget.stato.fonte.foto(widget.id)),
                  child: Text(t.riprova),
                ),
              ],
            );
          }
          final byte = istantanea.data;
          if (byte == null) {
            return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              byte,
              fit: BoxFit.fitWidth,
              errorBuilder: (_, _, _) => Text(t.questionarioFotoErrore),
            ),
          );
        },
      ),
    );
  }
}
