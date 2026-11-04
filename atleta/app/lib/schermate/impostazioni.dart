import 'dart:async';
import 'dart:convert';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:protocollo/protocollo.dart';

import '../l10n/testi.dart';
import 'avvisi.dart';
import '../piattaforma/esportazione.dart';
import '../piattaforma/sync_in_background.dart';
import 'formati.dart';
import 'pagina_coach.dart';
import 'scollegamento.dart';

/// Impostazioni (§10.2): il coach, con lo scollegamento e il cambio, e quelli
/// precedenti, con i loro dati; la frequenza della sync in background, che si
/// sceglie solo su Android (§7.4); l'esportazione dei dati in JSON (§11.3).
class Impostazioni extends StatefulWidget {
  const Impostazioni({
    super.key,
    required this.nucleo,
    this.background,
    this.esporta = esportaFile,
    this.cambiaCoach,
  });

  final NucleoAtleta nucleo;

  /// Null dove la sync in background non si può impostare: l'interfaccia
  /// dice che la sync avviene ad app aperta.
  final SyncInBackground? background;

  /// Consegna all'atleta il file esportato, dato il nome e il contenuto.
  final Future<void> Function(String nome, String contenuto) esporta;

  /// Apre il collegamento a un altro coach.
  final VoidCallback? cambiaCoach;

  @override
  State<Impostazioni> createState() => _ImpostazioniState();
}

class _ImpostazioniState extends State<Impostazioni> {
  /// Disattivata, 15 o 30 minuti, 1, 3 o 6 ore (§7.4).
  static const _scelte = [0, 15, 30, 60, 180, 360];

  late List<CoachCollegato> _coach;
  late final StreamSubscription<int> _cambiamenti;
  int? _minuti;

  /// Il telefono non lascia lavorare l'app in background.
  var _limitata = false;

  NucleoAtleta get _nucleo => widget.nucleo;

  @override
  void initState() {
    super.initState();
    _coach = _nucleo.collegamenti.elenco();
    _cambiamenti = _nucleo.cambiamenti.listen((_) {
      if (mounted) setState(() => _coach = _nucleo.collegamenti.elenco());
    });
    unawaited(_leggi());
  }

  @override
  void dispose() {
    unawaited(_cambiamenti.cancel());
    super.dispose();
  }

  Future<void> _leggi() async {
    final minuti = await widget.background?.frequenza();
    final limitata = await widget.background?.limitata() ?? false;
    if (mounted) {
      setState(() {
        _minuti = minuti;
        _limitata = limitata;
      });
    }
  }

  Future<void> _scegli(int minuti) async {
    setState(() => _minuti = minuti);
    await widget.background?.impostaFrequenza(minuti);
  }

  /// I dati dell'atleta in JSON (§10.2, §11.3): coach, schede e log, senza
  /// chiavi né token.
  Future<void> _esporta() async {
    final testi = Testi.of(context);
    final messaggi = ScaffoldMessenger.of(context);
    final oggi = formattaData(_nucleo.contesto.orologio.adesso());
    final json = const JsonEncoder.withIndent('  ').convert(_nucleo.esporta());
    try {
      await widget.esporta('open-coach-$oggi.json', json);
    } on Exception {
      messaggi.avvisa(testi.esportazioneNonRiuscita);
    }
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final titolo = Theme.of(context).textTheme.titleMedium;
    final background = widget.background;
    final cambiaCoach = widget.cambiaCoach;
    final attivi = [
      for (final c in _coach)
        if (c.stato == StatoCollegamento.attivo) c,
    ];
    final precedenti = [
      for (final c in _coach)
        if (c.stato != StatoCollegamento.attivo) c,
    ];
    Widget voce(CoachCollegato coach) => _VoceCoachCollegato(
      coach,
      scollega: () => scollegaDalCoach(context, _nucleo, coach),
      cancellaDati: () => cancellaDatiDelCoach(context, _nucleo, coach),
      vedi: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PaginaCoach(nucleo: _nucleo, coachId: coach.id),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(testi.impostazioni)),
      body: ListView(
        children: [
          ListTile(title: Text(testi.ilTuoCoach, style: titolo)),
          if (attivi.isEmpty) ListTile(subtitle: Text(testi.nessunCoachAncora)),
          for (final coach in attivi) voce(coach),
          if (attivi.isNotEmpty && cambiaCoach != null)
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(testi.cambiaCoach),
              onTap: cambiaCoach,
            ),
          if (precedenti.isNotEmpty) ...[
            const Divider(),
            ListTile(title: Text(testi.coachPrecedenti, style: titolo)),
            for (final coach in precedenti) voce(coach),
          ],
          const Divider(),
          ListTile(
            title: Text(testi.syncInBackground, style: titolo),
            subtitle: Text(
              background == null
                  ? testi.syncSoloAdAppAperta
                  : testi.spiegazioneSyncInBackground,
            ),
          ),
          if (background != null && _limitata)
            ListTile(
              leading: Icon(
                Icons.battery_alert,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(testi.syncLimitata),
              subtitle: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: background.apriImpostazioniApp,
                  child: Text(testi.apriImpostazioniApp),
                ),
              ),
            ),
          if (background != null)
            for (final minuti in _scelte)
              ListTile(
                title: Text(_etichetta(testi, minuti)),
                selected: minuti == _minuti,
                trailing: minuti == _minuti ? const Icon(Icons.check) : null,
                onTap: () => _scegli(minuti),
              ),
          const Divider(),
          ListTile(title: Text(testi.tuoiDati, style: titolo)),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: Text(testi.esportaDati),
            subtitle: Text(testi.spiegazioneEsporta),
            onTap: _esporta,
          ),
        ],
      ),
    );
  }

  String _etichetta(Testi testi, int minuti) => switch (minuti) {
    0 => testi.syncDisattivata,
    15 => testi.ogni15Minuti,
    30 => testi.ogni30Minuti,
    60 => testi.ogniOra,
    180 => testi.ogni3Ore,
    _ => testi.ogni6Ore,
  };
}

/// Un coach nelle impostazioni (§10.2): nome, indirizzo e ultima sync. Con
/// un collegamento attivo ci si scollega; con uno chiuso si cancellano i
/// dati.
class _VoceCoachCollegato extends StatelessWidget {
  const _VoceCoachCollegato(
    this.coach, {
    required this.scollega,
    required this.cancellaDati,
    required this.vedi,
  });

  final CoachCollegato coach;
  final VoidCallback scollega;
  final VoidCallback cancellaDati;

  /// Apre quello che resta sul telefono di un coach precedente.
  final VoidCallback vedi;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context);
    final ultima = coach.ultimaSync;
    final attivo = coach.stato == StatoCollegamento.attivo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(coach.nomeCoach, style: tema.textTheme.titleMedium),
          // L'indirizzo intero, a larghezza fissa: l'atleta può confrontarlo
          // con quello che mostra il programma del coach.
          SelectableText(
            '${coach.indirizzo}.onion',
            style: tema.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Courier'],
            ),
          ),
          Text(
            ultima == null
                ? testi.maiSincronizzato
                : testi.ultimaSync(quando(context, ultima)),
          ),
          // Revocato dal coach o scollegato: i messaggi vengono dal nucleo.
          if (!attivo)
            Text(
              coach.problema?.messaggio ?? ProblemaSync.scollegato.messaggio,
              style: TextStyle(color: tema.colorScheme.error),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: attivo
                ? TextButton(onPressed: scollega, child: Text(testi.scollega))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(onPressed: vedi, child: Text(testi.vediAllenamenti)),
                      TextButton(onPressed: cancellaDati, child: Text(testi.cancella)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
