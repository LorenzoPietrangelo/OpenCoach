import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../servizi.dart';

/// Telefono dell'atleta e invito (§5.1, §9.3).
class PannelloTelefono extends StatelessWidget {
  const PannelloTelefono({
    super.key,
    required this.atleta,
    required this.coach,
    required this.aggiornamenti,
  });

  final Atleta atleta;
  final Coach coach;
  final Aggiornamenti aggiornamenti;

  NucleoCoach get _nucleo => coach.nucleo;

  Future<void> _nuovoInvito(BuildContext context) async {
    final t = Testi.of(context);
    if (_nucleo.dispositivi.attivo(atleta.id) != null) {
      final procedi = await conferma(
        context,
        titolo: t.sostituireTelefonoTitolo,
        testo: t.sostituireTelefonoTesto,
        azione: t.creaInvito,
      );
      if (!procedi || !context.mounted) return;
    }
    await esegui(context, () async {
      final invito = await _nucleo.inviti.crea(atleta.id);
      aggiornamenti.segnala();
      if (context.mounted) await mostraInvito(context, invito);
    });
  }

  Future<void> _revoca(BuildContext context, Dispositivo dispositivo) async {
    final t = Testi.of(context);
    final sicuro = await conferma(
      context,
      titolo: t.revocaTitolo(dispositivo.nome),
      testo: t.revocaTesto(atleta.nome),
      azione: t.revoca,
      pericolosa: true,
    );
    if (!sicuro) return;
    _nucleo.dispositivi.revoca(dispositivo.id);
    aggiornamenti.segnala();
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return ListenableBuilder(
      listenable: aggiornamenti,
      builder: (context, _) {
        final dispositivo = _nucleo.dispositivi.attivo(atleta.id);
        final invito = _nucleo.inviti.inCorso(atleta.id);
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TitoloSezione(t.telefono),
            if (dispositivo == null)
              Text(t.nessunTelefonoSpiegazione)
            else
              Card(
                child: ListTile(
                  leading: Icon(
                    dispositivo.piattaforma == 'ios' ? Icons.phone_iphone : Icons.phone_android,
                  ),
                  title: Text(dispositivo.nome),
                  subtitle: Text(
                    [
                      t.versioneApp(dispositivo.versioneApp),
                      t.abbinatoIl(dataOra(dispositivo.abbinatoIl)),
                      dispositivo.ultimoContatto == null
                          ? t.maiSincronizzato
                          : t.ultimoContatto(dataOra(dispositivo.ultimoContatto!)),
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  trailing: OutlinedButton(
                    onPressed: () => _revoca(context, dispositivo),
                    child: Text(t.revoca),
                  ),
                ),
              ),
            TitoloSezione(t.invito),
            if (invito == null)
              Text(t.nessunInvito)
            else if (invito.stato == StatoInvito.inAbbinamento)
              Text(t.invitoInAbbinamento)
            else
              Card(
                child: ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: Text(t.invitoAperto),
                  subtitle: Text(t.validoFinoAl(dataOra(invito.scadeIl))),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          _nucleo.inviti.annulla(invito.id);
                          aggiornamenti.segnala();
                        },
                        child: Text(t.annullaInvito),
                      ),
                      FilledButton(
                        onPressed: () => mostraInvito(context, invito),
                        child: Text(t.mostraQr),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: atleta.archiviato ? null : () => _nuovoInvito(context),
                icon: const Icon(Icons.add_link),
                label: Text(t.nuovoInvito),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// QR e link dell'invito (§5.1): da far scansionare sullo schermo, oppure da
/// mandare come link, che va trattato come una password.
Future<void> mostraInvito(BuildContext context, Invito invito) {
  final t = Testi.of(context);
  final testo = invito.uri.toString();
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.invitoTitolo),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: testo, size: 300, errorCorrectionLevel: QrErrorCorrectLevel.M),
            ),
            const SizedBox(height: 16),
            Text(t.invitoSpiegazione),
            const SizedBox(height: 8),
            Text(t.validoFinoAl(dataOra(invito.scadeIl))),
            const SizedBox(height: 8),
            SelectableText(testo, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: testo));
            if (context.mounted) avviso(context, t.linkCopiato);
          },
          child: Text(t.copiaLink),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(t.chiudi)),
      ],
    ),
  );
}
