import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';

import '../l10n/testi.dart';
import '../piattaforma/inviti_in_arrivo.dart';
import '../piattaforma/sync_in_background.dart';
import 'aggiungi_coach.dart';
import 'impostazioni.dart';
import 'pagina_coach.dart';
import 'stato_sync.dart';

/// Coach collegati, ciascuno con le schede da vedere, l'ultima sync
/// riuscita, i log in attesa e l'eventuale problema (§7.5). Trascinando si
/// sincronizza subito (§7.4).
class ElencoCoach extends StatefulWidget {
  const ElencoCoach({
    super.key,
    required this.nucleo,
    this.background,
    this.inviti,
  });

  final NucleoAtleta nucleo;
  final SyncInBackground? background;

  /// I link d'invito aperti da un'altra app: ognuno apre l'abbinamento.
  final InvitiInArrivo? inviti;

  @override
  State<ElencoCoach> createState() => _ElencoCoachState();
}

class _ElencoCoachState extends State<ElencoCoach> {
  late List<CoachCollegato> _coach;

  /// Schede con una revisione non ancora aperta, per coach (§10.2).
  late Map<int, int> _daVedere;
  late final StreamSubscription<int> _cambiamenti;

  /// La schermata d'abbinamento aperta da qui: finché c'è, i link d'invito li
  /// apre lei.
  var _abbinamento = false;

  @override
  void initState() {
    super.initState();
    _leggi();
    _cambiamenti = widget.nucleo.cambiamenti.listen((_) => _aggiorna());
    widget.inviti?.addListener(_invitoArrivato);
    // Il link che ha aperto l'app arriva prima di questa schermata.
    WidgetsBinding.instance.addPostFrameCallback((_) => _invitoArrivato());
  }

  @override
  void dispose() {
    widget.inviti?.removeListener(_invitoArrivato);
    unawaited(_cambiamenti.cancel());
    super.dispose();
  }

  /// Un link d'invito apre l'abbinamento sopra la schermata in cui si trova
  /// l'atleta. Un allenamento in corso resta sotto.
  void _invitoArrivato() {
    if (mounted && !_abbinamento && widget.inviti?.inAttesa != null) {
      unawaited(_aggiungiCoach());
    }
  }

  Future<void> _aggiungiCoach() async {
    _abbinamento = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AggiungiCoach(nucleo: widget.nucleo, inviti: widget.inviti),
      ),
    );
    _abbinamento = false;
    // Un link arrivato mentre la schermata si chiudeva.
    _invitoArrivato();
  }

  void _leggi() {
    _coach = widget.nucleo.collegamenti.elenco();
    _daVedere = {
      for (final coach in _coach)
        coach.id: widget.nucleo.schede
            .elenco(coach.id)
            .where((scheda) => scheda.daVedere)
            .length,
    };
  }

  void _aggiorna() {
    if (mounted) setState(_leggi);
  }

  Future<void> _sincronizza() async {
    await widget.nucleo.pianificatore.sincronizzaTuttiOra();
    _aggiorna();
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(testi.nomeApp),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: testi.impostazioni,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Impostazioni(
                  nucleo: widget.nucleo,
                  background: widget.background,
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _sincronizza,
        child: ListView(
          children: [
            if (_coach.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(testi.nessunCoach, textAlign: TextAlign.center),
              ),
            for (final coach in _coach)
              _VoceCoach(
                coach,
                daVedere: _daVedere[coach.id] ?? 0,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PaginaCoach(nucleo: widget.nucleo, coachId: coach.id),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _aggiungiCoach,
        icon: const Icon(Icons.add),
        label: Text(testi.aggiungiCoach),
      ),
    );
  }
}

class _VoceCoach extends StatelessWidget {
  const _VoceCoach(this.coach, {required this.daVedere, required this.onTap});

  final CoachCollegato coach;
  final int daVedere;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final righe = [
      if (daVedere > 0) testi.schedeDaVedere(daVedere),
      ...righeStatoSync(context, coach),
    ];
    return ListTile(
      title: Text(coach.nomeCoach),
      subtitle: Text(righe.join('\n')),
      isThreeLine: righe.length > 2,
      leading: Badge(
        isLabelVisible: daVedere > 0,
        label: Text('$daVedere'),
        child: Icon(
          coach.problema == null ? Icons.sync : Icons.sync_problem,
          color: coach.problema == null
              ? null
              : Theme.of(context).colorScheme.error,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
