import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:protocollo/protocollo.dart';

import '../l10n/testi.dart';
import 'formati.dart';

/// Righe dello stato della sync con un coach (§7.5): sempre l'ultima sync
/// riuscita e gli allenamenti in attesa di invio, poi quelli rifiutati e il
/// problema dell'ultimo tentativo, se ci sono.
List<String> righeStatoSync(BuildContext context, CoachCollegato coach) {
  final testi = Testi.of(context);
  final ultima = coach.ultimaSync;
  return [
    if (ultima == null)
      testi.maiSincronizzato
    else
      testi.ultimaSync(quando(context, ultima)),
    testi.logInAttesa(coach.logInAttesa),
    if (coach.logRifiutati > 0) testi.logRifiutati(coach.logRifiutati),
    // I messaggi dei problemi vengono dal nucleo (§7.5).
    ?coach.problema?.messaggio,
  ];
}

/// Come sta un allenamento dello storico rispetto al coach (§7.3): in
/// attesa di invio, inviato o rifiutato.
String statoLog(Testi testi, LogAllenamento log) => switch (log.rifiuto) {
  final String motivo => testi.logRifiutato(motivoRifiuto(testi, motivo)),
  null when log.inAttesa => testi.inAttesaDiInvio,
  null => testi.inviatoAlCoach,
};

IconData iconaStatoLog(LogAllenamento log) => log.rifiuto != null
    ? Icons.error_outline
    : log.inAttesa
    ? Icons.schedule
    : Icons.cloud_done_outlined;

/// Perché il coach ha rifiutato un log (§6.3, `log_rifiutati`).
String motivoRifiuto(Testi testi, String codice) => switch (codice) {
  RifiutoLog.nonValido => testi.rifiutoNonValido,
  RifiutoLog.troppoGrande => testi.rifiutoTroppoGrande,
  RifiutoLog.altroAtleta => testi.rifiutoAltroAtleta,
  _ => testi.rifiutoAltro(codice),
};
