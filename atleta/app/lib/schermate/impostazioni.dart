import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/testi.dart';
import '../piattaforma/sync_in_background.dart';

/// Impostazioni (§10.2). Per ora la frequenza della sync in background, che
/// si sceglie solo su Android (§7.4).
class Impostazioni extends StatefulWidget {
  const Impostazioni({super.key, this.background});

  /// Null dove la sync in background non si può impostare: l'interfaccia
  /// dice che la sync avviene ad app aperta.
  final SyncInBackground? background;

  @override
  State<Impostazioni> createState() => _ImpostazioniState();
}

class _ImpostazioniState extends State<Impostazioni> {
  /// Disattivata, 30 minuti, 1, 3 o 6 ore (§7.4).
  static const _scelte = [0, 30, 60, 180, 360];

  int? _minuti;

  /// Il telefono non lascia lavorare l'app in background.
  var _limitata = false;

  @override
  void initState() {
    super.initState();
    unawaited(_leggi());
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

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final background = widget.background;
    return Scaffold(
      appBar: AppBar(title: Text(testi.impostazioni)),
      body: ListView(
        children: [
          ListTile(
            title: Text(
              testi.syncInBackground,
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
        ],
      ),
    );
  }

  String _etichetta(Testi testi, int minuti) => switch (minuti) {
    0 => testi.syncDisattivata,
    30 => testi.ogni30Minuti,
    60 => testi.ogniOra,
    180 => testi.ogni3Ore,
    _ => testi.ogni6Ore,
  };
}
