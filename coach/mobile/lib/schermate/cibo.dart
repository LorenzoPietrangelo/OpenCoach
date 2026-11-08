import 'package:flutter/material.dart';
import 'package:protocollo/protocollo.dart';

import '../dati/modelli.dart';
import '../dati/stato_coach.dart';
import '../l10n/testi.dart';
import 'comuni.dart';

/// Il cibo che l'atleta condivide (§8.8), in sola lettura: l'obiettivo si
/// fissa dal programma sul PC (§16.1).
class SezioneCibo extends StatelessWidget {
  const SezioneCibo({super.key, required this.stato, required this.atletaId});

  final StatoCoach stato;
  final String atletaId;

  @override
  Widget build(BuildContext context) => LettoreDati<CiboAtleta>(
    generazione: stato.generazione,
    carica: () => stato.fonte.cibo(atletaId),
    costruisci: (context, cibo, ricarica) => _Contenuto(stato: stato, atletaId: atletaId, primo: cibo),
  );
}

/// `1.850 kcal · P 140 g · C 190 g · G 58 g`.
String testoValori(ValoriCibo v) => [
  '${migliaia(v.kcal.round())} kcal',
  'P ${(v.proteine ?? 0).round()} g',
  'C ${(v.carboidrati ?? 0).round()} g',
  'G ${(v.grassi ?? 0).round()} g',
].join(' · ');

String testoObiettivo(ObiettivoCibo o) => [
  '${migliaia(o.kcal)} kcal',
  if (o.proteineG != null) 'P ${o.proteineG} g',
  if (o.carboidratiG != null) 'C ${o.carboidratiG} g',
  if (o.grassiG != null) 'G ${o.grassiG} g',
].join(' · ');

String migliaia(int n) {
  final cifre = n.abs().toString();
  final gruppi = <String>[];
  for (var fine = cifre.length; fine > 0; fine -= 3) {
    gruppi.insert(0, cifre.substring(fine - 3 < 0 ? 0 : fine - 3, fine));
  }
  return '${n < 0 ? '−' : ''}${gruppi.join('.')}';
}

class _Contenuto extends StatefulWidget {
  const _Contenuto({required this.stato, required this.atletaId, required this.primo});

  final StatoCoach stato;
  final String atletaId;
  final CiboAtleta primo;

  @override
  State<_Contenuto> createState() => _ContenutoState();
}

class _ContenutoState extends State<_Contenuto> {
  late var _giornate = widget.primo.giornate;
  late var _altri = widget.primo.altri;
  var _carica = false;

  @override
  void didUpdateWidget(_Contenuto vecchio) {
    super.didUpdateWidget(vecchio);
    if (!identical(vecchio.primo, widget.primo)) {
      _giornate = widget.primo.giornate;
      _altri = widget.primo.altri;
    }
  }

  Future<void> _altriGiorni() async {
    setState(() => _carica = true);
    try {
      final pagina = await widget.stato.fonte.cibo(widget.atletaId, prima: formattaData(_giornate.last.giorno));
      if (!mounted) return;
      setState(() {
        _giornate = [..._giornate, ...pagina.giornate];
        _altri = pagina.altri;
      });
    } on Exception {
      // Il riquadro del problema lo dice; si può riprovare.
    } finally {
      if (mounted) setState(() => _carica = false);
    }
  }

  String _pasto(Testi t, String pasto) => switch (pasto) {
    'colazione' => t.pastoColazione,
    'pranzo' => t.pastoPranzo,
    'cena' => t.pastoCena,
    _ => t.pastoSpuntini,
  };

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final obiettivo = widget.primo.obiettivo;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          obiettivo == null ? t.ciboSenzaObiettivo : t.ciboObiettivo(testoObiettivo(obiettivo)),
          style: tema.titleSmall,
        ),
        const SizedBox(height: 8),
        if (_giornate.isEmpty) Padding(padding: const EdgeInsets.only(top: 24), child: Text(t.ciboVuoto)),
        for (final g in _giornate)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(soloData(g.giorno)),
            subtitle: Text(testoValori(g.totali)),
            children: [
              for (final pasto in pastiCibo)
                if (g.delPasto(pasto) case final voci when voci.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_pasto(t, pasto), style: tema.titleSmall),
                    ),
                  ),
                  for (final v in voci)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(v.nome),
                      subtitle: Text('${numeroLeggibile(v.grammi)} g · ${testoValori(v.valori)}'),
                    ),
                ],
            ],
          ),
        if (_altri)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: _carica
                  ? const CircularProgressIndicator()
                  : TextButton(onPressed: _altriGiorni, child: Text(t.ciboAltri)),
            ),
          ),
      ],
    );
  }
}
