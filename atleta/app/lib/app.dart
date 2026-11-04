import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';

import 'l10n/testi.dart';
import 'piattaforma/inviti_in_arrivo.dart';
import 'piattaforma/sync_in_background.dart';
import 'schermate/principale.dart';

/// L'app dell'atleta sopra il nucleo: le sync automatiche seguono il primo
/// piano e il background (§7.4).
class AppAtleta extends StatefulWidget {
  const AppAtleta({
    super.key,
    required this.nucleo,
    this.background,
    this.inviti,
  });

  final NucleoAtleta nucleo;

  /// La sync in background con WorkManager; null dove non c'è (iOS, test).
  final SyncInBackground? background;

  /// I link d'invito aperti da un'altra app; null nei test che non li usano.
  final InvitiInArrivo? inviti;

  @override
  State<AppAtleta> createState() => _AppAtletaState();
}

class _AppAtletaState extends State<AppAtleta> {
  late final AppLifecycleListener _ciclo;

  PianificatoreSync get _pianificatore => widget.nucleo.pianificatore;

  @override
  void initState() {
    super.initState();
    // All'apertura e al ritorno in primo piano parte una sync; in background
    // si fermano le sync automatiche e poi Tor. Una sync in corso prosegue
    // come lavoro accelerato.
    _inPrimoPiano();
    _ciclo = AppLifecycleListener(
      onShow: _inPrimoPiano,
      onHide: () {
        unawaited(widget.background?.proseguiSeInCorso());
        unawaited(widget.background?.controlliRavvicinatiSeConversazione());
        unawaited(_pianificatore.vaiInBackground());
      },
    );
  }

  void _inPrimoPiano() {
    _pianificatore.entraInPrimoPiano();
    unawaited(widget.background?.chiediPermessoNotifiche());
    unawaited(widget.background?.annullaControlliRavvicinati());
  }

  @override
  void dispose() {
    _ciclo.dispose();
    _pianificatore.ferma();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => Testi.of(context).nomeApp,
    localizationsDelegates: Testi.localizationsDelegates,
    supportedLocales: Testi.supportedLocales,
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: SchermataPrincipale(
      nucleo: widget.nucleo,
      background: widget.background,
      inviti: widget.inviti,
    ),
  );
}
