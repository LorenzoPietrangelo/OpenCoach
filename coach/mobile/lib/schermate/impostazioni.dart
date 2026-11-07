import 'dart:async';

import 'package:flutter/material.dart';

import '../dati/stato_coach.dart';
import '../l10n/testi.dart';
import '../piattaforma/background.dart';

/// Impostazioni dell'app: il PC collegato, i controlli in background e lo
/// scollegamento (§16.4).
class SchermataImpostazioni extends StatefulWidget {
  const SchermataImpostazioni({super.key, required this.stato, this.background});

  final StatoCoach stato;
  final ControlliInBackground? background;

  @override
  State<SchermataImpostazioni> createState() => _SchermataImpostazioniState();
}

class _SchermataImpostazioniState extends State<SchermataImpostazioni> {
  int? _frequenza;
  var _limitata = false;

  @override
  void initState() {
    super.initState();
    unawaited(_carica());
  }

  Future<void> _carica() async {
    final background = widget.background;
    if (background == null) return;
    final frequenza = await background.frequenza();
    final limitata = await background.limitata();
    if (!mounted) return;
    setState(() {
      _frequenza = frequenza;
      _limitata = limitata;
    });
  }

  Future<void> _scollega() async {
    final t = Testi.of(context);
    final sicuro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.scollegaTitolo),
        content: Text(t.scollegaTesto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.annulla)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.scollegaAzione),
          ),
        ],
      ),
    );
    // L'app torna da sola alla schermata di collegamento.
    if (sicuro == true) await widget.stato.scollega();
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context);
    final frequenza = _frequenza;
    final background = widget.background;
    final credenziali = widget.stato.credenziali;
    return Scaffold(
      appBar: AppBar(title: Text(t.impostazioniTitolo)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(t.impostazioniPc, style: tema.textTheme.titleSmall),
            const SizedBox(height: 4),
            if (credenziali != null) Text(t.impostazioniProgramma(credenziali.nomeCoach)),
            const SizedBox(height: 20),
            Text(t.impostazioniBlocco, style: tema.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(t.impostazioniBloccoAttivo),
            if (background != null) ...[
              const SizedBox(height: 20),
              Text(t.impostazioniControlli, style: tema.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(t.impostazioniControlliAiuto),
              if (frequenza != null)
                DropdownButton<int>(
                  value: frequenza,
                  items: [
                    for (final minuti in const [0, 15, 30, 60])
                      DropdownMenuItem(
                        value: minuti,
                        child: Text(minuti == 0 ? t.controlliDisattivati : t.controlliOgni(minuti)),
                      ),
                  ],
                  onChanged: (minuti) async {
                    if (minuti == null) return;
                    await background.impostaFrequenza(minuti, attiva: widget.stato.collegato);
                    if (mounted) setState(() => _frequenza = minuti);
                  },
                ),
              if (_limitata) ...[
                const SizedBox(height: 8),
                Text(t.batteriaLimitata, style: TextStyle(color: tema.colorScheme.error)),
                TextButton(onPressed: background.apriImpostazioniApp, child: Text(t.apriImpostazioniTelefono)),
              ],
            ],
            const SizedBox(height: 32),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: tema.colorScheme.error),
                onPressed: _scollega,
                child: Text(t.scollegaAzione),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
