import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';

import 'l10n/testi.dart';
import 'piattaforma/desktop.dart';
import 'schermate/benvenuto.dart';
import 'schermate/principale.dart';
import 'servizi.dart';

/// Ferma il programma, ripristina il backup e lo riavvia (§9.4).
typedef Ripristino =
    Future<EsitoRipristino> Function(String file, String passphrase);

/// L'interfaccia del programma del coach.
class AppCoach extends StatefulWidget {
  const AppCoach({
    super.key,
    required this.coach,
    required this.desktop,
    required this.ripristina,
    this.navigatore,
  });

  final Coach coach;
  final Desktop desktop;
  final Ripristino ripristina;

  /// Per aprire finestre di dialogo da fuori, per esempio dall'area di
  /// notifica.
  final GlobalKey<NavigatorState>? navigatore;

  @override
  State<AppCoach> createState() => _AppCoachState();
}

class _AppCoachState extends State<AppCoach> {
  late final _aggiornamenti = Aggiornamenti(widget.coach.nucleo);

  @override
  void dispose() {
    _aggiornamenti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: widget.navigatore,
    onGenerateTitle: (context) => Testi.of(context).nomeApp,
    localizationsDelegates: Testi.localizationsDelegates,
    supportedLocales: Testi.supportedLocales,
    locale: const Locale('it'),
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: widget.coach.nucleo.nomeCoach.isEmpty
        ? Benvenuto(
            coach: widget.coach,
            desktop: widget.desktop,
            fatto: () => setState(() {}),
          )
        : Principale(
            coach: widget.coach,
            desktop: widget.desktop,
            aggiornamenti: _aggiornamenti,
            ripristina: widget.ripristina,
          ),
  );
}
