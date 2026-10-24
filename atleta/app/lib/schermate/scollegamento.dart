import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';

import '../l10n/testi.dart';
import 'avvisi.dart';

/// Scollega il telefono dal coach (§10.2), dalle impostazioni o dalla pagina
/// del coach: il nucleo avvisa il coach con `DELETE /v1/dispositivo`, se
/// risponde in pochi secondi. Poi, dopo conferma, cancella schede e log di
/// quel coach. Vero se i dati sono stati cancellati.
Future<bool> scollegaDalCoach(
  BuildContext context,
  NucleoAtleta nucleo,
  CoachCollegato coach,
) async {
  final testi = Testi.of(context);
  final messaggi = ScaffoldMessenger.of(context);
  final navigatore = Navigator.of(context, rootNavigator: true);
  final conferma = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(testi.scollegartiDa(coach.nomeCoach)),
      content: Text(
        [
          testi.spiegazioneScollega,
          if (coach.logInAttesa > 0) testi.logNonInviati(coach.logInAttesa),
        ].join('\n\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(testi.annulla),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(testi.scollega),
        ),
      ],
    ),
  );
  if (conferma != true || !context.mounted) return false;
  // Per avvisare il coach può servire avviare Tor: qualche secondo.
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 24),
              Expanded(child: Text(testi.scollegamentoInCorso)),
            ],
          ),
        ),
      ),
    ),
  );
  final bool avvisato;
  try {
    avvisato = await nucleo.collegamenti.scollega(coach.id);
  } on Exception {
    messaggi.avvisa(testi.scollegamentoNonRiuscito);
    return false;
  } finally {
    navigatore.pop();
  }
  if (!context.mounted) return false;
  return cancellaDatiDelCoach(
    context,
    nucleo,
    coach,
    spiegazione: avvisato ? testi.coachAvvisato : testi.coachNonAvvisato,
  );
}

/// Cancella dal telefono schede e log di un coach con cui il collegamento è
/// chiuso (§10.2, §11.3), dopo conferma. Vero se li ha cancellati.
Future<bool> cancellaDatiDelCoach(
  BuildContext context,
  NucleoAtleta nucleo,
  CoachCollegato coach, {
  String? spiegazione,
}) async {
  final testi = Testi.of(context);
  final cancella = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(testi.cancellareDatiDi(coach.nomeCoach)),
      content: Text(
        [?spiegazione, testi.spiegazioneCancellaDati].join('\n\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(testi.conserva),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(testi.cancella),
        ),
      ],
    ),
  );
  if (cancella != true) return false;
  await nucleo.collegamenti.cancellaDati(coach.id);
  return true;
}
