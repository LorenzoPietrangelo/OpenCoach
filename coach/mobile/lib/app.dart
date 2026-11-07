import 'dart:async';

import 'package:flutter/material.dart';

import 'dati/stato_coach.dart';
import 'l10n/testi.dart';
import 'piattaforma/background.dart';
import 'piattaforma/blocco.dart';
import 'piattaforma/qr_di_prova.dart';
import 'schermate/atleti.dart';
import 'schermate/blocco.dart';
import 'schermate/collega.dart';

/// L'app del coach: chiusa dal blocco, poi il collegamento al PC o gli atleti.
class AppCoachMobile extends StatefulWidget {
  const AppCoachMobile({super.key, required this.stato, required this.blocco, this.background, this.qrDiProva});

  final StatoCoach stato;
  final BloccoApp blocco;

  /// I controlli con WorkManager; null nei test.
  final ControlliInBackground? background;
  final QrDiProva? qrDiProva;

  @override
  State<AppCoachMobile> createState() => _AppCoachMobileState();
}

class _AppCoachMobileState extends State<AppCoachMobile> {
  late final AppLifecycleListener _ciclo;
  final _navigatore = GlobalKey<NavigatorState>();
  late var _eraCollegato = widget.stato.collegato;

  @override
  void initState() {
    super.initState();
    // In primo piano i dati si tengono aggiornati; in background si spegne Tor.
    widget.stato.entraInPrimoPiano();
    widget.stato.addListener(_statoCambiato);
    _ciclo = AppLifecycleListener(
      onShow: widget.stato.entraInPrimoPiano,
      onHide: () => unawaited(widget.stato.vaiInBackground()),
    );
  }

  @override
  void dispose() {
    _ciclo.dispose();
    widget.stato.removeListener(_statoCambiato);
    super.dispose();
  }

  /// Telefono scollegato o revocato: le pagine aperte non hanno più dati.
  void _statoCambiato() {
    final collegato = widget.stato.collegato;
    if (_eraCollegato && !collegato) _navigatore.currentState?.popUntil((rotta) => rotta.isFirst);
    _eraCollegato = collegato;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigatore,
    onGenerateTitle: (context) => Testi.of(context).nomeApp,
    localizationsDelegates: Testi.localizationsDelegates,
    supportedLocales: Testi.supportedLocales,
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
    // Sopra il navigatore: il blocco copre anche le pagine aperte.
    builder: (context, navigatore) => CancelloBlocco(blocco: widget.blocco, child: navigatore!),
    home: ListenableBuilder(
      listenable: widget.stato,
      builder: (context, _) => widget.stato.collegato
          ? SchermataAtleti(stato: widget.stato, background: widget.background)
          : SchermataCollega(stato: widget.stato, qrDiProva: widget.qrDiProva),
    ),
  );
}
