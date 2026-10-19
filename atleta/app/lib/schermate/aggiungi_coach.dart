import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';

import '../l10n/testi.dart';

/// Abbinamento con il link d'invito incollato a mano (§5.2, §5.3): legge
/// l'invito, chiede «Collegarti a …?» e collega il telefono. Gli errori
/// sono quelli del §5.4.
class AggiungiCoach extends StatefulWidget {
  const AggiungiCoach({super.key, required this.nucleo});

  final NucleoAtleta nucleo;

  @override
  State<AggiungiCoach> createState() => _AggiungiCoachState();
}

class _AggiungiCoachState extends State<AggiungiCoach> {
  final _invito = TextEditingController();
  var _inCorso = false;
  String? _errore;

  @override
  void dispose() {
    _invito.dispose();
    super.dispose();
  }

  Future<void> _collega() async {
    final testi = Testi.of(context);
    setState(() {
      _inCorso = true;
      _errore = null;
    });
    try {
      final invito = await widget.nucleo.leggiInvito(_invito.text);
      if (!mounted) return;
      final conferma = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(testi.collegartiA(invito.nomeCoach)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(testi.annulla),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(testi.collega),
            ),
          ],
        ),
      );
      if (conferma != true) return;
      await invito.collega();
      if (mounted) Navigator.of(context).pop();
    } on ErroreAbbinamento catch (e) {
      if (mounted) setState(() => _errore = e.messaggio);
    } finally {
      if (mounted) setState(() => _inCorso = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(testi.titoloInvito)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(testi.spiegazioneInvito),
          const SizedBox(height: 16),
          TextField(
            controller: _invito,
            enabled: !_inCorso,
            decoration: InputDecoration(
              labelText: testi.etichettaInvito,
              errorText: _errore,
              errorMaxLines: 3,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 24),
          if (_inCorso)
            Center(child: Text(testi.collegamentoInCorso))
          else
            FilledButton(onPressed: _collega, child: Text(testi.continua)),
        ],
      ),
    );
  }
}
