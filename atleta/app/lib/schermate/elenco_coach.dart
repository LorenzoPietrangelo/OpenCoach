import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';

import '../l10n/testi.dart';
import '../piattaforma/inviti_in_arrivo.dart';
import '../piattaforma/sync_in_background.dart';
import 'aggiungi_coach.dart';
import 'impostazioni.dart';
import 'formati.dart';
import 'pagina_coach.dart';
import 'peso.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _invitoArrivato();
      unawaited(_consigliaBatteria());
    });
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
    // Con il primo coach collegato il consiglio sulla batteria diventa utile.
    if (mounted) unawaited(_consigliaBatteria());
  }

  /// Il consiglio sulla batteria è già comparso da quando l'app è aperta.
  var _consiglioMostrato = false;

  /// Per quanto «Non ora» nasconde il consiglio sulla batteria.
  static const _rinvioConsiglio = Duration(days: 7);

  /// Con la batteria «Limitata» le sync in background non partono, con
  /// «Ottimizzata» possono ritardare di ore (§7.4): con un coach collegato
  /// l'app lo dice e porta alle impostazioni. Non compare con «Senza
  /// restrizioni», né per una settimana dopo «Non ora».
  Future<void> _consigliaBatteria() async {
    final background = widget.background;
    if (background == null || _consiglioMostrato) return;
    if (widget.nucleo.collegamenti.attivi().isEmpty) return;
    final StatoBatteria stato;
    final DateTime? rimandato;
    try {
      stato = await background.statoBatteria();
      rimandato = await background.consiglioBatteriaRimandato();
    } on Exception {
      // Senza il codice Android, per esempio nei test, niente consiglio.
      return;
    }
    final adesso = widget.nucleo.contesto.orologio.adesso();
    if (stato == StatoBatteria.senzaRestrizioni) return;
    if (rimandato != null && adesso.isBefore(rimandato)) return;
    // Un'altra schermata sopra, per esempio l'abbinamento: si aspetta.
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _consiglioMostrato = true;
    final testi = Testi.of(context);
    final limitata = stato == StatoBatteria.limitata;
    final scelta = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.battery_alert_outlined),
        title: Text(
          limitata ? testi.batteriaLimitataTitolo : testi.batteriaOttimizzataTitolo,
        ),
        content: Text(
          limitata ? testi.batteriaLimitataTesto : testi.batteriaOttimizzataTesto,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(testi.nonOra),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(testi.apriImpostazioniApp),
          ),
        ],
      ),
    );
    if (scelta == true) {
      await background.apriImpostazioniApp();
    } else {
      await background.rimandaConsiglioBatteria(adesso.add(_rinvioConsiglio));
    }
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
    _daCompilare = {
      for (final coach in _coach) coach.id: widget.nucleo.questionari.daCompilare(coach.id),
    };
    _nonLetti = {for (final coach in _coach) coach.id: widget.nucleo.chat.nonLetti(coach.id)};
  }

  /// Questionari ancora da compilare, per coach.
  late Map<int, int> _daCompilare;

  /// Messaggi dei coach non ancora letti.
  late Map<int, int> _nonLetti;

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
            _VocePeso(widget.nucleo, aperta: () => setState(() {})),
            const Divider(height: 1),
            if (_coach.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(testi.nessunCoach, textAlign: TextAlign.center),
              ),
            for (final coach in _coach)
              _VoceCoach(
                coach,
                daVedere: _daVedere[coach.id] ?? 0,
                daCompilare: _daCompilare[coach.id] ?? 0,
                nonLetti: _nonLetti[coach.id] ?? 0,
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

/// Il peso di oggi, o l'invito a registrarlo; apre la schermata del peso.
class _VocePeso extends StatelessWidget {
  const _VocePeso(this.nucleo, {required this.aperta});

  final NucleoAtleta nucleo;

  /// Al ritorno dalla schermata del peso, per mostrare quello nuovo.
  final VoidCallback aperta;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final oggi = nucleo.pesi.delGiorno(nucleo.contesto.orologio.adesso().toLocal());
    return ListTile(
      leading: const Icon(Icons.monitor_weight_outlined),
      title: Text(testi.peso),
      subtitle: Text(oggi == null ? testi.registraPesoOggi : testi.pesoDiOggi(numero(oggi.kg))),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => SchermataPeso(nucleo: nucleo)),
        );
        aperta();
      },
    );
  }
}

class _VoceCoach extends StatelessWidget {
  const _VoceCoach(
    this.coach, {
    required this.daVedere,
    required this.daCompilare,
    required this.nonLetti,
    required this.onTap,
  });

  final CoachCollegato coach;
  final int daVedere;
  final int daCompilare;
  final int nonLetti;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final righe = [
      if (daVedere > 0) testi.schedeDaVedere(daVedere),
      if (daCompilare > 0) testi.questionariDaCompilare(daCompilare),
      if (nonLetti > 0) testi.nuoviMessaggi(nonLetti),
      ...righeStatoSync(context, coach),
    ];
    return ListTile(
      title: Text(coach.nomeCoach),
      subtitle: Text(righe.join('\n')),
      isThreeLine: righe.length > 2,
      leading: Badge(
        isLabelVisible: daVedere + daCompilare + nonLetti > 0,
        label: Text('${daVedere + daCompilare + nonLetti}'),
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
