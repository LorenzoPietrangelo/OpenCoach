import 'dart:async';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../comuni.dart';
import '../l10n/testi.dart';
import '../piattaforma/desktop.dart';
import '../servizi.dart';
import 'atleti.dart';
import 'impostazioni.dart';
import 'libreria.dart';
import 'questionari.dart';
import 'stato.dart';

/// Chiede conferma e chiude il programma: gli atleti non potranno più
/// sincronizzare finché non viene riaperto (§9.1).
Future<void> chiediUscita(BuildContext context, Coach coach, Desktop desktop) async {
  final t = Testi.of(context);
  final esci = await conferma(
    context,
    titolo: t.esciTitolo,
    testo: t.esciTesto,
    azione: t.esci,
    pericolosa: true,
  );
  if (!esci) return;
  await coach.chiudi();
  await desktop.esci();
}

/// Schermata principale: atleti, stato del servizio, impostazioni.
class Principale extends StatefulWidget {
  const Principale({
    super.key,
    required this.coach,
    required this.desktop,
    required this.aggiornamenti,
    required this.ripristina,
  });

  final Coach coach;
  final Desktop desktop;
  final Aggiornamenti aggiornamenti;
  final Ripristino ripristina;

  @override
  State<Principale> createState() => _PrincipaleState();
}

class _PrincipaleState extends State<Principale> {
  var _sezione = 0;
  late final StreamSubscription<EventoCoach> _eventi;
  late final StreamSubscription<StatoTor> _stati;
  late final _preferenze = Preferenze(widget.coach.nucleo.contesto.archivio);

  @override
  void initState() {
    super.initState();
    _eventi = widget.coach.nucleo.eventi.listen(_notifica);
    _stati = widget.coach.cambiamentiStatoTor.listen((_) => _aggiornaIcona());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _aggiornaIcona();
      unawaited(widget.desktop.impedisciSospensione(_preferenze.impedisciSospensione));
    });
  }

  @override
  void dispose() {
    unawaited(_eventi.cancel());
    unawaited(_stati.cancel());
    super.dispose();
  }

  void _aggiornaIcona() {
    if (!mounted) return;
    final t = Testi.of(context);
    unawaited(
      widget.desktop.aggiornaStato(
        '${t.nomeApp}: ${descriviStatoTor(t, widget.coach.statoTor)}',
      ),
    );
    setState(() {});
  }

  /// Notifiche sul desktop (§9.3). L'invito usato da un secondo telefono si
  /// segnala sempre: il link può essere stato intercettato.
  void _notifica(EventoCoach evento) {
    if (!mounted) return;
    final t = Testi.of(context);
    final nome = widget.coach.nucleo.atleti.cerca(evento.atletaId)?.nome ?? '';
    final (String, String)? testo = switch (evento) {
      InvitoContestato() => (t.notificaInvitoContestatoTitolo, t.notificaInvitoContestato(nome)),
      _ when !_preferenze.notifiche => null,
      LogRicevuto(eliminato: false) => (t.nomeApp, t.notificaLogRicevuto(nome)),
      QuestionarioRisposto(:final titolo) => (t.nomeApp, t.notificaQuestionarioRisposto(nome, titolo)),
      DispositivoAbbinato(:final nomeDispositivo) => (
        t.nomeApp,
        t.notificaAbbinato(nome, nomeDispositivo),
      ),
      _ => null,
    };
    if (testo != null) unawaited(widget.desktop.notifica(testo.$1, testo.$2));
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final avvisi = <Widget>[
      if (widget.coach.statoTor.versioneObsoleta)
        _Avviso(testo: t.avvisoTorObsoleto, icona: Icons.system_update),
      if (widget.coach.backup.serveUnBackup)
        _Avviso(
          testo: t.avvisoBackup,
          icona: Icons.backup_outlined,
          azione: t.vaiAlBackup,
          premuto: () => setState(() => _sezione = 4),
        ),
    ];
    final corpo = switch (_sezione) {
      0 => SchermataAtleti(
        coach: widget.coach,
        desktop: widget.desktop,
        aggiornamenti: widget.aggiornamenti,
      ),
      1 => SchermataLibreria(coach: widget.coach, aggiornamenti: widget.aggiornamenti),
      2 => SchermataQuestionari(coach: widget.coach, aggiornamenti: widget.aggiornamenti),
      3 => SchermataStato(coach: widget.coach, aggiornamenti: widget.aggiornamenti),
      _ => SchermataImpostazioni(
        coach: widget.coach,
        desktop: widget.desktop,
        aggiornamenti: widget.aggiornamenti,
        ripristina: widget.ripristina,
        esci: () => chiediUscita(context, widget.coach, widget.desktop),
      ),
    };
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _sezione,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _sezione = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _IconaStato(stato: widget.coach.statoTor),
            ),
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.people_outline),
                selectedIcon: const Icon(Icons.people),
                label: Text(t.sezioneAtleti),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.video_library_outlined),
                selectedIcon: const Icon(Icons.video_library),
                label: Text(t.sezioneLibreria),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.assignment_outlined),
                selectedIcon: const Icon(Icons.assignment),
                label: Text(t.sezioneQuestionariMenu),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.wifi_tethering_outlined),
                selectedIcon: const Icon(Icons.wifi_tethering),
                label: Text(t.sezioneStato),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: Text(t.sezioneImpostazioni),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                ...avvisi,
                Expanded(child: corpo),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconaStato extends StatelessWidget {
  const _IconaStato({required this.stato});

  final StatoTor stato;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    final (icona, colore) = switch (stato.fase) {
      FaseTor.raggiungibile => (Icons.cloud_done, Colors.green.shade700),
      FaseTor.nonRaggiungibile => (Icons.cloud_off, schema.error),
      _ => (Icons.cloud_sync, schema.outline),
    };
    return Tooltip(
      message: descriviStatoTor(Testi.of(context), stato),
      child: Icon(icona, color: colore, size: 32),
    );
  }
}

class _Avviso extends StatelessWidget {
  const _Avviso({
    required this.testo,
    required this.icona,
    this.azione,
    this.premuto,
  });

  final String testo;
  final IconData icona;
  final String? azione;
  final VoidCallback? premuto;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    leading: Icon(icona),
    content: Text(testo),
    actions: [
      if (azione != null)
        TextButton(onPressed: premuto, child: Text(azione!))
      else
        const SizedBox.shrink(),
    ],
  );
}
