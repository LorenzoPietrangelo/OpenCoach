import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';

import '../l10n/testi.dart';
import 'aggiungi_coach.dart';

/// Coach collegati, ciascuno con l'ultima sync riuscita, i log in attesa e
/// l'eventuale problema (§7.5). Trascinando si sincronizza subito (§7.4).
class ElencoCoach extends StatefulWidget {
  const ElencoCoach({super.key, required this.nucleo});

  final NucleoAtleta nucleo;

  @override
  State<ElencoCoach> createState() => _ElencoCoachState();
}

class _ElencoCoachState extends State<ElencoCoach> {
  late List<CoachCollegato> _coach;
  late final StreamSubscription<int> _cambiamenti;

  @override
  void initState() {
    super.initState();
    _coach = widget.nucleo.collegamenti.elenco();
    _cambiamenti = widget.nucleo.cambiamenti.listen((_) => _aggiorna());
  }

  @override
  void dispose() {
    unawaited(_cambiamenti.cancel());
    super.dispose();
  }

  void _aggiorna() {
    if (mounted) setState(() => _coach = widget.nucleo.collegamenti.elenco());
  }

  Future<void> _sincronizza() async {
    await widget.nucleo.pianificatore.sincronizzaTuttiOra();
    _aggiorna();
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(testi.nomeApp)),
      body: RefreshIndicator(
        onRefresh: _sincronizza,
        child: ListView(
          children: [
            if (_coach.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(testi.nessunCoach, textAlign: TextAlign.center),
              ),
            for (final coach in _coach) _VoceCoach(coach),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AggiungiCoach(nucleo: widget.nucleo),
          ),
        ),
        icon: const Icon(Icons.add),
        label: Text(testi.aggiungiCoach),
      ),
    );
  }
}

class _VoceCoach extends StatelessWidget {
  const _VoceCoach(this.coach);

  final CoachCollegato coach;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final ultima = coach.ultimaSync;
    final righe = [
      if (ultima == null)
        testi.maiSincronizzato
      else
        testi.ultimaSync(_quando(context, ultima)),
      testi.logInAttesa(coach.logInAttesa),
      // I messaggi dei problemi vengono dal nucleo (§7.5).
      ?coach.problema?.messaggio,
    ];
    return ListTile(
      title: Text(coach.nomeCoach),
      subtitle: Text(righe.join('\n')),
      isThreeLine: righe.length > 2,
      leading: Icon(
        coach.problema == null ? Icons.sync : Icons.sync_problem,
        color: coach.problema == null
            ? null
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  String _quando(BuildContext context, DateTime istante) {
    final locale = MaterialLocalizations.of(context);
    final ora = istante.toLocal();
    return '${locale.formatShortDate(ora)} '
        '${locale.formatTimeOfDay(TimeOfDay.fromDateTime(ora))}';
  }
}
