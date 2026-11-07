import 'package:flutter/material.dart';

import '../dati/fonte_dati.dart';
import '../l10n/testi.dart';

String _due(int n) => n.toString().padLeft(2, '0');

/// `21/10/2026`.
String soloData(DateTime giorno) => '${_due(giorno.day)}/${_due(giorno.month)}/${giorno.year}';

/// `21/10/2026 18:30`.
String dataOra(DateTime quando) => '${soloData(quando)} ${_due(quando.hour)}:${_due(quando.minute)}';

/// `18:30` se è di oggi, altrimenti `21/10`: per gli elenchi e la chat.
String quandoBreve(DateTime quando, {DateTime? adesso}) {
  final ora = adesso ?? DateTime.now();
  return quando.year == ora.year && quando.month == ora.month && quando.day == ora.day
      ? '${_due(quando.hour)}:${_due(quando.minute)}'
      : '${_due(quando.day)}/${_due(quando.month)}';
}

/// Un numero senza zeri inutili e con la virgola: `72,5`, `80`.
String numeroLeggibile(num valore) {
  final testo = valore == valore.roundToDouble() ? valore.toInt().toString() : valore.toStringAsFixed(1);
  return testo.replaceAll('.', ',');
}

/// Il problema spiegato al coach; null se non c'è.
String? testoProblema(Testi t, ProblemaCoach? problema) => switch (problema) {
  null => null,
  ProblemaCoach.irraggiungibile => t.problemaIrraggiungibile,
  ProblemaCoach.torNonParte => t.problemaTor,
  ProblemaCoach.chiaveRifiutata => t.problemaChiave,
  ProblemaCoach.versioneDiversa => t.problemaVersione,
  ProblemaCoach.occupato => t.problemaOccupato,
  ProblemaCoach.revocato || ProblemaCoach.rifiutata || ProblemaCoach.inatteso => t.problemaInatteso,
};

/// Dati letti dal PC con il loro stato: [carica] li legge, e si rilegge quando
/// [generazione] cambia. Con dati già presenti un errore non li toglie: restano
/// quelli di prima, e il coach lo sa dal riquadro del problema.
class LettoreDati<T> extends StatefulWidget {
  const LettoreDati({
    super.key,
    required this.generazione,
    required this.carica,
    required this.costruisci,
  });

  final int generazione;
  final Future<T> Function() carica;
  final Widget Function(BuildContext context, T dati, Future<void> Function() ricarica) costruisci;

  @override
  State<LettoreDati<T>> createState() => _LettoreDatiState<T>();
}

class _LettoreDatiState<T> extends State<LettoreDati<T>> {
  T? _dati;
  var _haDati = false;
  var _errore = false;

  @override
  void initState() {
    super.initState();
    _ricarica();
  }

  @override
  void didUpdateWidget(LettoreDati<T> vecchio) {
    super.didUpdateWidget(vecchio);
    if (vecchio.generazione != widget.generazione) _ricarica();
  }

  Future<void> _ricarica() async {
    try {
      final dati = await widget.carica();
      if (!mounted) return;
      setState(() {
        _dati = dati;
        _haDati = true;
        _errore = false;
      });
    } on ErroreCoach {
      if (mounted) setState(() => _errore = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_haDati) return widget.costruisci(context, _dati as T, _ricarica);
    if (!_errore) return const Center(child: CircularProgressIndicator());
    final t = Testi.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.problemaDati, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                setState(() => _errore = false);
                _ricarica();
              },
              child: Text(t.riprova),
            ),
          ],
        ),
      ),
    );
  }
}

/// Testo centrato per una lista senza elementi.
class ListaVuota extends StatelessWidget {
  const ListaVuota(this.testo, {super.key});

  final String testo;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        testo,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}
