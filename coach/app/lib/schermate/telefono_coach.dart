import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../servizi.dart';

/// La sezione delle impostazioni sul telefono del coach (§16.2): collegarlo,
/// vedere qual è e scollegarlo.
class SezioneTelefonoCoach extends StatelessWidget {
  const SezioneTelefonoCoach({super.key, required this.coach, required this.aggiornamenti});

  final Coach coach;
  final Aggiornamenti aggiornamenti;

  Future<void> _collega(BuildContext context) async {
    final t = Testi.of(context);
    final attivo = coach.nucleo.telefonoCoach.attivo();
    if (attivo != null) {
      final procedi = await conferma(
        context,
        titolo: t.sostituireTelefonoCoachTitolo,
        testo: t.sostituireTelefonoCoachTesto(attivo.nome),
        azione: t.continua,
      );
      if (!procedi || !context.mounted) return;
    }
    await esegui(context, () async {
      await coach.nucleo.telefonoCoach.creaInvito();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _DialogoQrTelefono(coach: coach, aggiornamenti: aggiornamenti, sostituito: attivo?.id),
      );
    });
    aggiornamenti.segnala();
  }

  Future<void> _scollega(BuildContext context, TelefonoCoach telefono) async {
    final t = Testi.of(context);
    final sicuro = await conferma(
      context,
      titolo: t.scollegaTelefonoCoachTitolo(telefono.nome),
      testo: t.scollegaTelefonoCoachTesto,
      azione: t.revoca,
      pericolosa: true,
    );
    if (!sicuro) return;
    coach.nucleo.telefonoCoach.revoca();
    aggiornamenti.segnala();
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return ListenableBuilder(
      listenable: aggiornamenti,
      builder: (context, _) {
        final telefono = coach.nucleo.telefonoCoach.attivo();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.telefonoCoachSpiegazione),
            if (telefono != null) ...[
              const SizedBox(height: 8),
              Text(t.telefonoCoachCollegato(telefono.nome), style: Theme.of(context).textTheme.titleSmall),
              Text(
                t.telefonoCoachDettagli(
                  dataOra(telefono.abbinatoIl),
                  telefono.ultimoContatto == null ? t.telefonoCoachMaiVisto : dataOra(telefono.ultimoContatto!),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _collega(context),
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(t.collegaTelefonoCoach),
                ),
                if (telefono != null)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () => _scollega(context, telefono),
                    child: Text(t.scollegaTelefonoCoach),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Il QR, senza niente da copiare: chi lo legge vede i dati di tutti gli atleti
/// (§16.2). Segue il collegamento mentre avviene. Chiudendolo senza che un
/// telefono l'abbia letto, il QR si annulla.
class _DialogoQrTelefono extends StatelessWidget {
  const _DialogoQrTelefono({required this.coach, required this.aggiornamenti, required this.sostituito});

  final Coach coach;
  final Aggiornamenti aggiornamenti;

  /// Il telefono che c'era prima: finché è lui l'attivo, il nuovo non è arrivato.
  final String? sostituito;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return ListenableBuilder(
      listenable: aggiornamenti,
      builder: (context, _) {
        final gestione = coach.nucleo.telefonoCoach;
        final invito = gestione.invitoInCorso();
        final attivo = gestione.attivo();
        final collegato = attivo != null && attivo.id != sostituito;
        final uri = invito?.uri;
        return AlertDialog(
          title: Text(t.qrTelefonoCoachTitolo),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (collegato && uri == null)
                  Text(invito != null ? t.qrTelefonoCoachInCorso : t.qrTelefonoCoachFatto(attivo.nome))
                else if (uri != null) ...[
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(
                      data: uri.toString(),
                      size: 300,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(t.qrTelefonoCoachSpiegazione),
                  const SizedBox(height: 8),
                  Text(t.qrTelefonoCoachValido(dataOra(invito!.scadeIl))),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                // Un QR che nessuno ha letto non resta valido in giro.
                if (gestione.invitoInCorso()?.uri != null) gestione.annullaInvito();
                Navigator.pop(context);
              },
              child: Text(t.chiudi),
            ),
          ],
        );
      },
    );
  }
}
