import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';

import '../l10n/testi.dart';
import '../piattaforma/inviti_in_arrivo.dart';
import '../piattaforma/sync_in_background.dart';
import 'aggiungi_coach.dart';
import 'chat.dart';
import 'impostazioni.dart';
import 'pagina_coach.dart';
import 'peso.dart';
import 'stato_sync.dart';

/// La schermata da cui parte l'app (§10.2). L'atleta ha un solo coach alla
/// volta: senza coach si collega, con il coach trova le sezioni Allenamento,
/// Chat e Peso. Chi aveva più coach da una versione precedente ne sceglie uno.
class SchermataPrincipale extends StatefulWidget {
  const SchermataPrincipale({
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
  State<SchermataPrincipale> createState() => _SchermataPrincipaleState();
}

class _SchermataPrincipaleState extends State<SchermataPrincipale> {
  late List<CoachCollegato> _attivi;
  late final StreamSubscription<int> _cambiamenti;

  /// La schermata d'abbinamento aperta da qui: finché c'è, i link d'invito li
  /// apre lei.
  var _abbinamento = false;

  @override
  void initState() {
    super.initState();
    _attivi = widget.nucleo.collegamenti.attivi();
    _cambiamenti = widget.nucleo.cambiamenti.listen((_) {
      if (!mounted) return;
      final primoCoach = _attivi.isEmpty;
      setState(() => _attivi = widget.nucleo.collegamenti.attivi());
      // Con il primo coach collegato il consiglio sulla batteria diventa utile.
      if (primoCoach && _attivi.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_consigliaBatteria()));
      }
    });
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
  /// l'atleta. Un allenamento in corso resta sotto. Senza coach l'abbinamento
  /// è già la schermata principale, e il link lo prende lei.
  void _invitoArrivato() {
    if (mounted && _attivi.isNotEmpty && !_abbinamento && widget.inviti?.inAttesa != null) {
      unawaited(_cambiaCoach());
    }
  }

  /// Il QR o il link di un altro coach: dopo il collegamento quello attuale
  /// viene scollegato.
  Future<void> _cambiaCoach() async {
    _abbinamento = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AggiungiCoach(nucleo: widget.nucleo, inviti: widget.inviti),
      ),
    );
    _abbinamento = false;
    // Un link arrivato mentre la schermata si chiudeva.
    _invitoArrivato();
  }

  Future<void> _apriImpostazioni() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Impostazioni(
        nucleo: widget.nucleo,
        background: widget.background,
        cambiaCoach: _cambiaCoach,
      ),
    ),
  );

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
    } else if (scelta == false) {
      await background.rimandaConsiglioBatteria(adesso.add(_rinvioConsiglio));
    }
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    if (_attivi.isEmpty) {
      return AggiungiCoach(
        nucleo: widget.nucleo,
        inviti: widget.inviti,
        azioni: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: testi.impostazioni,
            onPressed: _apriImpostazioni,
          ),
        ],
      );
    }
    if (_attivi.length > 1) return _ScegliCoach(nucleo: widget.nucleo, coach: _attivi);
    return _Sezioni(
      key: ValueKey(_attivi.single.id),
      nucleo: widget.nucleo,
      coachId: _attivi.single.id,
      apriImpostazioni: _apriImpostazioni,
    );
  }
}

/// Allenamento, Chat e Peso, con il coach collegato.
class _Sezioni extends StatefulWidget {
  const _Sezioni({
    super.key,
    required this.nucleo,
    required this.coachId,
    required this.apriImpostazioni,
  });

  final NucleoAtleta nucleo;
  final int coachId;
  final VoidCallback apriImpostazioni;

  @override
  State<_Sezioni> createState() => _SezioniState();
}

class _SezioniState extends State<_Sezioni> {
  late final StreamSubscription<int> _cambiamenti;
  var _sezione = 0;

  NucleoAtleta get _nucleo => widget.nucleo;

  @override
  void initState() {
    super.initState();
    _cambiamenti = _nucleo.cambiamenti.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_cambiamenti.cancel());
    super.dispose();
  }

  void _scegli(int sezione) {
    // La tastiera di una sezione nascosta non deve restare aperta.
    FocusScope.of(context).unfocus();
    setState(() => _sezione = sezione);
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final id = widget.coachId;
    final nome = _nucleo.collegamenti.cerca(id)?.nomeCoach ?? '';
    final daVedere = _nucleo.schede.elenco(id).where((s) => s.daVedere).length;
    final perLaChat = _nucleo.chat.nonLetti(id) + _nucleo.questionari.daCompilare(id);
    return PopScope(
      canPop: _sezione == 0,
      onPopInvokedWithResult: (uscita, _) {
        if (!uscita) _scegli(0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (_sezione) {
            0 => nome,
            1 => testi.chatCon(nome),
            _ => testi.peso,
          }),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: testi.impostazioni,
              onPressed: widget.apriImpostazioni,
            ),
          ],
        ),
        body: IndexedStack(
          index: _sezione,
          children: [
            SezioneAllenamento(nucleo: _nucleo, coachId: id),
            SchermataChat(nucleo: _nucleo, coachId: id, barra: false, visibile: _sezione == 1),
            SchermataPeso(nucleo: _nucleo, barra: false),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _sezione,
          onDestinationSelected: _scegli,
          destinations: [
            NavigationDestination(
              icon: Badge(
                isLabelVisible: daVedere > 0,
                label: Text('$daVedere'),
                child: const Icon(Icons.fitness_center),
              ),
              label: testi.allenamento,
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: perLaChat > 0,
                label: Text('$perLaChat'),
                child: const Icon(Icons.chat_bubble_outline),
              ),
              label: testi.chat,
            ),
            NavigationDestination(
              icon: const Icon(Icons.monitor_weight_outlined),
              label: testi.peso,
            ),
          ],
        ),
      ),
    );
  }
}

/// Chi aveva più coach da una versione precedente sceglie quale tenere: dagli
/// altri si scollega, e quello che ha fatto con loro resta sul telefono.
class _ScegliCoach extends StatefulWidget {
  const _ScegliCoach({required this.nucleo, required this.coach});

  final NucleoAtleta nucleo;
  final List<CoachCollegato> coach;

  @override
  State<_ScegliCoach> createState() => _ScegliCoachState();
}

class _ScegliCoachState extends State<_ScegliCoach> {
  var _inCorso = false;

  Future<void> _tieni(CoachCollegato scelto) async {
    final testi = Testi.of(context);
    final conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(testi.tenereCoach(scelto.nomeCoach)),
        content: Text(testi.spiegazioneTenereCoach),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(testi.annulla),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(testi.conferma),
          ),
        ],
      ),
    );
    if (conferma != true || !mounted) return;
    setState(() => _inCorso = true);
    try {
      for (final altro in widget.coach) {
        if (altro.id != scelto.id) await widget.nucleo.collegamenti.scollega(altro.id);
      }
    } on Exception {
      // Resta qui: l'atleta riprova.
    } finally {
      if (mounted) setState(() => _inCorso = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(testi.scegliCoachTitolo)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(testi.scegliCoachSpiegazione),
          ),
          if (_inCorso) const LinearProgressIndicator(),
          for (final coach in widget.coach)
            ListTile(
              title: Text(coach.nomeCoach),
              subtitle: Text(righeStatoSync(context, coach).join('\n')),
              trailing: const Icon(Icons.chevron_right),
              enabled: !_inCorso,
              onTap: () => _tieni(coach),
            ),
        ],
      ),
    );
  }
}
