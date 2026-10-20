import 'dart:async';
import 'dart:io';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app.dart';
import '../comuni.dart';
import '../l10n/testi.dart';
import '../piattaforma/desktop.dart';
import '../piattaforma/percorsi.dart';
import '../servizi.dart';

/// Impostazioni (§9.1, §9.4): nome, avvio, notifiche, backup, Tor e
/// identità.
class SchermataImpostazioni extends StatefulWidget {
  const SchermataImpostazioni({
    super.key,
    required this.coach,
    required this.desktop,
    required this.aggiornamenti,
    required this.ripristina,
    required this.esci,
  });

  final Coach coach;
  final Desktop desktop;
  final Aggiornamenti aggiornamenti;
  final Ripristino ripristina;
  final VoidCallback esci;

  @override
  State<SchermataImpostazioni> createState() => _SchermataImpostazioniState();
}

class _SchermataImpostazioniState extends State<SchermataImpostazioni> {
  late final _preferenze = Preferenze(widget.coach.nucleo.contesto.archivio);
  bool? _avvioAutomatico;
  var _backupConfigurato = false;
  var _inCorso = false;

  GestioneBackup get _backup => widget.coach.backup;

  @override
  void initState() {
    super.initState();
    unawaited(_carica());
  }

  Future<void> _carica() async {
    final avvio = await widget.desktop.avvioAutomatico();
    final configurato = await _backup.configurato();
    if (!mounted) return;
    setState(() {
      _avvioAutomatico = avvio;
      _backupConfigurato = configurato;
    });
  }

  Future<void> _lungo(Future<void> Function() azione) async {
    setState(() => _inCorso = true);
    try {
      await esegui(context, azione);
    } finally {
      if (mounted) setState(() => _inCorso = false);
      widget.aggiornamenti.segnala();
    }
  }

  Future<void> _rinomina() async {
    final t = Testi.of(context);
    final nome = await chiediTesto(
      context,
      titolo: t.nomeCoach,
      etichetta: t.nomeCoachAiuto,
      iniziale: widget.coach.nucleo.nomeCoach,
    );
    if (nome == null || !mounted) return;
    await esegui(context, () async => widget.coach.nucleo.nomeCoach = nome);
    setState(() {});
  }

  Future<void> _configuraBackup() async {
    final scelta = await showDialog<_SceltaBackup>(
      context: context,
      builder: (_) => _DialogoBackup(desktop: widget.desktop, cartella: _backup.cartella),
    );
    if (scelta == null) return;
    await _lungo(() async {
      await _backup.configura(
        passphrase: scelta.passphrase,
        cartella: scelta.cartella,
        intervallo: Duration(days: scelta.giorni),
      );
      _backupConfigurato = true;
    });
  }

  Future<void> _backupOra() async {
    final t = Testi.of(context);
    await _lungo(() async {
      final file = await _backup.esegui();
      if (mounted) avviso(context, t.backupCreato(file.path));
    });
  }

  Future<void> _salvaBackupIn() async {
    final t = Testi.of(context);
    final percorso = await widget.desktop.scegliDoveSalvare('opencoach.ocbackup', 'ocbackup');
    if (percorso == null || !mounted) return;
    String? passphrase;
    if (!_backupConfigurato) {
      passphrase = await _chiediPassphrase(t.passphraseNuovoBackup);
      if (passphrase == null) return;
    }
    await _lungo(() async {
      final file = await _backup.salvaIn(percorso, passphrase: passphrase);
      if (mounted) avviso(context, t.backupCreato(file.path));
    });
  }

  Future<void> _ripristina() async {
    final t = Testi.of(context);
    final file = await widget.desktop.scegliFile('ocbackup');
    if (file == null || !mounted) return;
    final passphrase = await _chiediPassphrase(t.passphraseDelBackup);
    if (passphrase == null || !mounted) return;
    final sicuro = await conferma(
      context,
      titolo: t.ripristinaTitolo,
      testo: t.ripristinaTesto(p.basename(file)),
      azione: t.ripristina,
      pericolosa: true,
    );
    if (!sicuro || !mounted) return;
    setState(() => _inCorso = true);
    try {
      await widget.ripristina(file, passphrase);
      // Il programma riparte con un'interfaccia nuova: questa non c'è più.
    } on PassphraseErrata {
      if (mounted) avviso(context, t.passphraseErrata);
    } on BackupNonValido catch (e) {
      if (mounted) avviso(context, e.messaggio);
    } finally {
      if (mounted) setState(() => _inCorso = false);
    }
  }

  Future<String?> _chiediPassphrase(String titolo) {
    final t = Testi.of(context);
    return chiediTesto(
      context,
      titolo: titolo,
      etichetta: t.passphrase,
      segreto: true,
      azione: t.continua,
    );
  }

  Future<void> _torEsterno() async {
    final t = Testi.of(context);
    final file = await widget.desktop.scegliFile(Platform.isWindows ? 'exe' : '');
    if (file == null || !mounted) return;
    scriviTorEsterno(widget.coach.cartellaDati, file);
    avviso(context, t.torEsternoImpostato);
    setState(() {});
  }

  Future<void> _reimpostaIdentita() async {
    final t = Testi.of(context);
    final primo = await conferma(
      context,
      titolo: t.reimpostaIdentitaTitolo,
      testo: t.reimpostaIdentitaTesto,
      azione: t.continua,
      pericolosa: true,
    );
    if (!primo || !mounted) return;
    final secondo = await conferma(
      context,
      titolo: t.reimpostaIdentitaConfermaTitolo,
      testo: t.reimpostaIdentitaConfermaTesto,
      azione: t.reimpostaIdentita,
      pericolosa: true,
    );
    if (!secondo) return;
    await _lungo(() async {
      await widget.coach.reimpostaIdentita();
      if (mounted) avviso(context, t.identitaReimpostata);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final ultimo = _backup.ultimoBackup;
    final torEsterno = leggiTorEsterno(widget.coach.cartellaDati);
    return AbsorbPointer(
      absorbing: _inCorso,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(child: Text(t.sezioneImpostazioni, style: Theme.of(context).textTheme.titleLarge)),
              if (_inCorso) const SizedBox(width: 24, height: 24, child: CircularProgressIndicator()),
            ],
          ),
          TitoloSezione(t.coach),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.nomeCoach),
            subtitle: Text(widget.coach.nucleo.nomeCoach),
            trailing: TextButton(onPressed: _rinomina, child: Text(t.modifica)),
          ),
          TitoloSezione(t.avvioENotifiche),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.avvioAutomatico),
            subtitle: Text(t.avvioAutomaticoAiuto),
            value: _avvioAutomatico ?? false,
            onChanged: _avvioAutomatico == null
                ? null
                : (v) async {
                    await widget.desktop.impostaAvvioAutomatico(v);
                    setState(() => _avvioAutomatico = v);
                  },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.impedisciSospensione),
            subtitle: Text(t.impedisciSospensioneAiuto),
            value: _preferenze.impedisciSospensione,
            onChanged: (v) async {
              _preferenze.impedisciSospensione = v;
              await widget.desktop.impedisciSospensione(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.notificheDesktop),
            subtitle: Text(t.notificheDesktopAiuto),
            value: _preferenze.notifiche,
            onChanged: (v) => setState(() => _preferenze.notifiche = v),
          ),
          TitoloSezione(t.backup),
          Text(
            _backupConfigurato
                ? t.backupConfigurato(_backup.cartella ?? '', t.ogniGiorni(_backup.intervallo.inDays))
                : t.backupNonConfigurato,
          ),
          Text(ultimo == null ? t.backupMai : t.backupUltimo(dataOra(ultimo))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _configuraBackup,
                child: Text(_backupConfigurato ? t.cambiaBackup : t.configuraBackup),
              ),
              OutlinedButton(onPressed: _backupConfigurato ? _backupOra : null, child: Text(t.backupOra)),
              OutlinedButton(onPressed: _salvaBackupIn, child: Text(t.salvaBackupIn)),
              OutlinedButton(onPressed: _ripristina, child: Text(t.ripristinaDaBackup)),
            ],
          ),
          const SizedBox(height: 4),
          Text(t.backupSpiegazione, style: Theme.of(context).textTheme.bodySmall),
          TitoloSezione(t.tor),
          Text(torEsterno == null ? t.torIncluso : t.torEsterno(torEsterno)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(onPressed: _torEsterno, child: Text(t.scegliTorEsterno)),
              if (torEsterno != null)
                TextButton(
                  onPressed: () {
                    scriviTorEsterno(widget.coach.cartellaDati, null);
                    avviso(context, t.torEsternoImpostato);
                    setState(() {});
                  },
                  child: Text(t.usaTorIncluso),
                ),
            ],
          ),
          TitoloSezione(t.identita),
          SelectableText('${widget.coach.indirizzo}.onion'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: _reimpostaIdentita,
              child: Text(t.reimpostaIdentita),
            ),
          ),
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: widget.esci,
              icon: const Icon(Icons.power_settings_new),
              label: Text(t.esciDaOpenCoach),
            ),
          ),
        ],
      ),
    );
  }
}

class _SceltaBackup {
  const _SceltaBackup(this.passphrase, this.cartella, this.giorni);

  final String passphrase;
  final String cartella;
  final int giorni;
}

class _DialogoBackup extends StatefulWidget {
  const _DialogoBackup({required this.desktop, required this.cartella});

  final Desktop desktop;
  final String? cartella;

  @override
  State<_DialogoBackup> createState() => _DialogoBackupState();
}

class _DialogoBackupState extends State<_DialogoBackup> {
  final _passphrase = TextEditingController();
  final _ripetuta = TextEditingController();
  late String? _cartella = widget.cartella;
  var _giorni = 7;
  String? _errore;

  @override
  void dispose() {
    _passphrase.dispose();
    _ripetuta.dispose();
    super.dispose();
  }

  void _conferma() {
    final t = Testi.of(context);
    final cartella = _cartella;
    setState(() {
      if (_passphrase.text.length < 8) {
        _errore = t.passphraseCorta;
      } else if (_passphrase.text != _ripetuta.text) {
        _errore = t.passphraseDiverse;
      } else if (cartella == null) {
        _errore = t.scegliCartellaBackup;
      } else {
        _errore = null;
      }
    });
    if (_errore == null) {
      Navigator.pop(context, _SceltaBackup(_passphrase.text, cartella!, _giorni));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return AlertDialog(
      title: Text(t.configuraBackup),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.passphraseSpiegazione),
            TextField(
              controller: _passphrase,
              obscureText: true,
              decoration: InputDecoration(labelText: t.passphrase),
            ),
            TextField(
              controller: _ripetuta,
              obscureText: true,
              decoration: InputDecoration(labelText: t.ripetiPassphrase),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text(_cartella ?? t.nessunaCartella)),
                TextButton(
                  onPressed: () async {
                    final scelta = await widget.desktop.scegliCartella();
                    if (scelta != null) setState(() => _cartella = scelta);
                  },
                  child: Text(t.scegliCartella),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _giorni,
              decoration: InputDecoration(labelText: t.frequenzaBackup),
              items: [
                for (final giorni in const [1, 7, 14, 30])
                  DropdownMenuItem(value: giorni, child: Text(t.ogniGiorni(giorni))),
              ],
              onChanged: (v) => setState(() => _giorni = v ?? 7),
            ),
            if (_errore != null) ...[
              const SizedBox(height: 12),
              Text(_errore!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.annulla)),
        FilledButton(onPressed: _conferma, child: Text(t.salva)),
      ],
    );
  }
}
