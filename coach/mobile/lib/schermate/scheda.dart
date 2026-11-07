import 'package:flutter/material.dart';

import '../dati/modelli.dart';
import '../dati/stato_coach.dart';
import '../l10n/testi.dart';
import 'comuni.dart';

/// Note, telefono e schede dell'atleta, in sola lettura (§16.1).
class SezioneScheda extends StatelessWidget {
  const SezioneScheda({super.key, required this.stato, required this.atletaId});

  final StatoCoach stato;
  final String atletaId;

  @override
  Widget build(BuildContext context) => LettoreDati<DettaglioAtleta>(
    generazione: stato.generazione,
    carica: () => stato.fonte.atleta(atletaId),
    costruisci: (context, dettaglio, ricarica) => _Contenuto(dettaglio),
  );
}

class _Contenuto extends StatelessWidget {
  const _Contenuto(this.dettaglio);

  final DettaglioAtleta dettaglio;

  String _statoScheda(Testi t, SchedaAtleta s) {
    final ricevuta = s.ricevutaIl;
    return switch (s.stato) {
      'bozza' => t.schedaBozza,
      'archiviata' => t.schedaArchiviata,
      _ when ricevuta != null => t.schedaRicevuta(s.revisione, dataOra(ricevuta)),
      _ when s.revisione > 0 => t.schedaNonRicevuta(s.revisione),
      _ => t.schedaPubblicata(s.revisione),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context);
    final riepilogo = dettaglio.riepilogo;
    final contatto = riepilogo.ultimoContatto;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.schedaNote, style: tema.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(dettaglio.note.isEmpty ? t.schedaNoteVuote : dettaglio.note),
        const SizedBox(height: 20),
        Text(t.schedaTelefono, style: tema.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          !riepilogo.telefonoCollegato
              ? t.atletaSenzaTelefono
              : contatto == null
              ? t.schedaMaiSincronizzato
              : t.schedaUltimoContatto(dataOra(contatto)),
        ),
        Text(t.schedaAllenamenti(dettaglio.allenamentiTotali)),
        const SizedBox(height: 20),
        Text(t.schedaSchede, style: tema.textTheme.titleSmall),
        if (dettaglio.schede.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(t.schedaNessuna))
        else
          for (final scheda in dettaglio.schede)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(scheda.titolo),
              subtitle: Text(_statoScheda(t, scheda)),
            ),
        const SizedBox(height: 8),
        Text(t.schedaAiuto, style: tema.textTheme.bodySmall),
      ],
    );
  }
}
