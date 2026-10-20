import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../servizi.dart';

/// Testo che descrive lo stato del servizio, per l'icona e la schermata.
String descriviStatoTor(Testi t, StatoTor stato) => switch (stato.fase) {
  FaseTor.avvio => t.statoAvvio(stato.avanzamento),
  FaseTor.nessunaChiave => t.statoNessunaChiave,
  FaseTor.pubblicazione => t.statoPubblicazione,
  FaseTor.raggiungibile => t.statoRaggiungibile,
  FaseTor.nonRaggiungibile => t.statoNonRaggiungibile(stato.motivo ?? ''),
};

/// Stato del servizio, indirizzo, telefoni collegati e backup (§9.1).
class SchermataStato extends StatelessWidget {
  const SchermataStato({super.key, required this.coach, required this.aggiornamenti});

  final Coach coach;
  final Aggiornamenti aggiornamenti;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return StreamBuilder<StatoTor>(
      stream: coach.cambiamentiStatoTor,
      builder: (context, _) => ListenableBuilder(
        listenable: aggiornamenti,
        builder: (context, _) {
          final stato = coach.statoTor;
          final atleti = coach.nucleo.atleti.elenco();
          final telefoni = atleti.where((r) => r.dispositivo != null).toList();
          final inviti = atleti.where((r) => r.invito != null).length;
          final contatti = telefoni.map((r) => r.dispositivo!.ultimoContatto).whereType<DateTime>().toList()
            ..sort();
          final ultimoBackup = coach.backup.ultimoBackup;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(t.sezioneStato, style: Theme.of(context).textTheme.titleLarge),
              TitoloSezione(t.servizio),
              Text(descriviStatoTor(t, stato), style: Theme.of(context).textTheme.titleMedium),
              if (stato.fase == FaseTor.avvio) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: stato.avanzamento / 100),
              ],
              const SizedBox(height: 8),
              Text(switch (stato.fase) {
                FaseTor.raggiungibile => t.spiegazioneRaggiungibile,
                FaseTor.nessunaChiave => t.spiegazioneNessunaChiave,
                _ => t.spiegazioneNonPronto,
              }),
              if (stato.versioneObsoleta) ...[
                const SizedBox(height: 8),
                Text(t.avvisoTorObsoleto, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              TitoloSezione(t.indirizzo),
              Row(
                children: [
                  Expanded(child: SelectableText('${coach.indirizzo}.onion')),
                  IconButton(
                    tooltip: t.copia,
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: '${coach.indirizzo}.onion'));
                      if (context.mounted) avviso(context, t.indirizzoCopiato);
                    },
                  ),
                ],
              ),
              Text(t.indirizzoSpiegazione, style: Theme.of(context).textTheme.bodySmall),
              TitoloSezione(t.sezioneAtleti),
              Text(t.riepilogoAtleti(atleti.length, telefoni.length, inviti)),
              if (contatti.isNotEmpty) Text(t.ultimoContattoDiTutti(dataOra(contatti.last))),
              TitoloSezione(t.backup),
              Text(ultimoBackup == null ? t.backupMai : t.backupUltimo(dataOra(ultimoBackup))),
            ],
          );
        },
      ),
    );
  }
}
