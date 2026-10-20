import 'package:flutter/material.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../piattaforma/desktop.dart';
import '../servizi.dart';

/// Primo avvio (§9.1): nome mostrato agli atleti e avvio automatico. Il
/// backup si configura dalle impostazioni; il programma lo ricorda.
class Benvenuto extends StatefulWidget {
  const Benvenuto({
    super.key,
    required this.coach,
    required this.desktop,
    required this.fatto,
  });

  final Coach coach;
  final Desktop desktop;
  final VoidCallback fatto;

  @override
  State<Benvenuto> createState() => _BenvenutoState();
}

class _BenvenutoState extends State<Benvenuto> {
  final _nome = TextEditingController();
  var _avvioAutomatico = true;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  Future<void> _inizia() async {
    final riuscito = await esegui(context, () async {
      widget.coach.nucleo.nomeCoach = _nome.text;
      await widget.desktop.impostaAvvioAutomatico(_avvioAutomatico);
    });
    if (riuscito) widget.fatto();
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(32),
            children: [
              Text(t.benvenutoTitolo, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              Text(t.benvenutoSpiegazione),
              const SizedBox(height: 24),
              TextField(
                controller: _nome,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: t.nomeCoach,
                  helperText: t.nomeCoachAiuto,
                ),
                onSubmitted: (_) => _inizia(),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.avvioAutomatico),
                subtitle: Text(t.avvioAutomaticoAiuto),
                value: _avvioAutomatico,
                onChanged: (v) => setState(() => _avvioAutomatico = v),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: _inizia, child: Text(t.inizia)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
