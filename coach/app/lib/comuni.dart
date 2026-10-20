import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';

import 'l10n/testi.dart';

String _due(int n) => n.toString().padLeft(2, '0');

/// `21/10/2026 18:30`, nell'ora locale.
String dataOra(DateTime istante) {
  final l = istante.toLocal();
  return '${soloData(l)} ${_due(l.hour)}:${_due(l.minute)}';
}

/// `21/10/2026`.
String soloData(DateTime giorno) =>
    '${_due(giorno.day)}/${_due(giorno.month)}/${giorno.year}';

/// Chiede conferma di un'azione; vero se il coach conferma.
Future<bool> conferma(
  BuildContext context, {
  required String titolo,
  required String testo,
  required String azione,
  bool pericolosa = false,
}) async {
  final t = Testi.of(context);
  final esito = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titolo),
      content: Text(testo),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(t.annulla),
        ),
        FilledButton(
          style: pericolosa
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(azione),
        ),
      ],
    ),
  );
  return esito ?? false;
}

/// Chiede un testo; null se il coach annulla. Con [segreto] il testo non si
/// vede, come per una passphrase.
Future<String?> chiediTesto(
  BuildContext context, {
  required String titolo,
  required String etichetta,
  String iniziale = '',
  int righe = 1,
  bool segreto = false,
  String? azione,
}) => showDialog<String>(
  context: context,
  builder: (_) => _DialogoTesto(
    titolo: titolo,
    etichetta: etichetta,
    iniziale: iniziale,
    righe: righe,
    segreto: segreto,
    azione: azione,
  ),
);

/// Il dialogo possiede il suo controller e lo libera solo quando sparisce,
/// dopo l'animazione di chiusura.
class _DialogoTesto extends StatefulWidget {
  const _DialogoTesto({
    required this.titolo,
    required this.etichetta,
    required this.iniziale,
    required this.righe,
    required this.segreto,
    required this.azione,
  });

  final String titolo;
  final String etichetta;
  final String iniziale;
  final int righe;
  final bool segreto;
  final String? azione;

  @override
  State<_DialogoTesto> createState() => _DialogoTestoState();
}

class _DialogoTestoState extends State<_DialogoTesto> {
  late final _controllo = TextEditingController(text: widget.iniziale);

  @override
  void dispose() {
    _controllo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final unaRiga = widget.righe == 1;
    return AlertDialog(
      title: Text(widget.titolo),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controllo,
          autofocus: true,
          obscureText: widget.segreto,
          minLines: widget.righe,
          maxLines: unaRiga ? 1 : null,
          decoration: InputDecoration(labelText: widget.etichetta),
          onSubmitted: unaRiga ? (v) => Navigator.pop(context, v) : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.annulla)),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controllo.text),
          child: Text(widget.azione ?? t.salva),
        ),
      ],
    );
  }
}

void avviso(BuildContext context, String testo) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(testo)));
}

/// Esegue [azione] e mostra come avviso gli errori che il coach può
/// correggere ([OperazioneNonValida]).
Future<bool> esegui(BuildContext context, Future<void> Function() azione) async {
  try {
    await azione();
    return true;
  } on OperazioneNonValida catch (e) {
    if (context.mounted) avviso(context, e.messaggio);
    return false;
  }
}

/// Titolo di sezione nelle schermate.
class TitoloSezione extends StatelessWidget {
  const TitoloSezione(this.testo, {super.key});

  final String testo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
    child: Text(testo, style: Theme.of(context).textTheme.titleMedium),
  );
}
