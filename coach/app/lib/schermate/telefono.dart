import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../servizi.dart';

/// Crea un invito per l'atleta e lo mostra (§5.1, §9.3). Quello ancora aperto
/// smette di valere. Con un telefono già collegato chiede prima conferma.
Future<void> nuovoInvito(
  BuildContext context,
  Atleta atleta,
  Coach coach,
  Aggiornamenti aggiornamenti,
) async {
  final t = Testi.of(context);
  final nucleo = coach.nucleo;
  if (nucleo.dispositivi.attivo(atleta.id) != null) {
    final procedi = await conferma(
      context,
      titolo: t.sostituireTelefonoTitolo,
      testo: t.sostituireTelefonoTesto,
      azione: t.creaInvito,
    );
    if (!procedi || !context.mounted) return;
  }
  await esegui(context, () async {
    final invito = await nucleo.inviti.crea(atleta.id);
    aggiornamenti.segnala();
    if (context.mounted) await mostraInvito(context, invito);
  });
}

/// Scollega il telefono dell'atleta, dopo conferma: serve se lo perde o se
/// glielo rubano.
Future<void> scollegaTelefono(
  BuildContext context,
  Atleta atleta,
  Dispositivo dispositivo,
  Coach coach,
  Aggiornamenti aggiornamenti,
) async {
  final t = Testi.of(context);
  final sicuro = await conferma(
    context,
    titolo: t.revocaTitolo(dispositivo.nome),
    testo: t.revocaTesto(atleta.nome),
    azione: t.revoca,
    pericolosa: true,
  );
  if (!sicuro) return;
  coach.nucleo.dispositivi.revoca(dispositivo.id);
  aggiornamenti.segnala();
}

/// La pagina di un atleta nuovo, finché non collega il telefono: l'invito e
/// basta. Appena il telefono si collega lasciano il posto alle altre sezioni.
class PannelloCollegamento extends StatelessWidget {
  const PannelloCollegamento({
    super.key,
    required this.atleta,
    required this.coach,
    required this.aggiornamenti,
  });

  final Atleta atleta;
  final Coach coach;
  final Aggiornamenti aggiornamenti;

  Future<void> _crea(BuildContext context) => esegui(context, () async {
    await coach.nucleo.inviti.crea(atleta.id);
    aggiornamenti.segnala();
  });

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final invito = coach.nucleo.inviti.inCorso(atleta.id);
    final testo = invito?.uri?.toString();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(t.nessunTelefonoSpiegazione),
        const SizedBox(height: 16),
        if (invito != null && testo != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _DatiInvito(invito),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: testo));
                  if (context.mounted) avviso(context, t.linkCopiato);
                },
                icon: const Icon(Icons.copy),
                label: Text(t.copiaLink),
              ),
              OutlinedButton.icon(
                onPressed: () => _crea(context),
                icon: const Icon(Icons.refresh),
                label: Text(t.nuovoInvito),
              ),
            ],
          ),
        ] else
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _crea(context),
              icon: const Icon(Icons.add_link),
              label: Text(t.creaInvito),
            ),
          ),
      ],
    );
  }
}

/// QR e link dell'invito (§5.1): da far scansionare sullo schermo, oppure da
/// mandare come link, che va trattato come una password.
class _DatiInvito extends StatelessWidget {
  const _DatiInvito(this.invito);

  final Invito invito;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final testo = invito.uri.toString();
    return Column(
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
    );
  }
}

Future<void> mostraInvito(BuildContext context, Invito invito) {
  final t = Testi.of(context);
  final testo = invito.uri.toString();
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.invitoTitolo),
      content: SizedBox(width: 460, child: _DatiInvito(invito)),
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
