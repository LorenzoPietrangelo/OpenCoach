import 'dart:async';
import 'dart:math';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:protocollo/protocollo.dart';

import '../l10n/testi.dart';
import 'avvisi.dart';
import 'formati.dart';

/// Il peso dell'atleta, un valore al giorno (§8.5): si registra quello di
/// oggi o di un altro giorno, si vede l'andamento e si sceglie con quali
/// coach condividerlo.
class SchermataPeso extends StatefulWidget {
  const SchermataPeso({super.key, required this.nucleo});

  final NucleoAtleta nucleo;

  @override
  State<SchermataPeso> createState() => _SchermataPesoState();
}

class _SchermataPesoState extends State<SchermataPeso> {
  final _kg = TextEditingController();
  late DateTime _giorno = _oggi;
  String? _errore;
  late final StreamSubscription<int> _cambiamenti;

  RegistroPesi get _pesi => widget.nucleo.pesi;

  DateTime get _oggi {
    final ora = widget.nucleo.contesto.orologio.adesso().toLocal();
    return DateTime(ora.year, ora.month, ora.day);
  }

  @override
  void initState() {
    super.initState();
    _mostra(_giorno);
    // Una sync può dire che il programma di un coach non riceve il peso.
    _cambiamenti = widget.nucleo.cambiamenti.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_cambiamenti.cancel());
    _kg.dispose();
    super.dispose();
  }

  /// Porta nel campo il peso già registrato per [giorno], se c'è.
  void _mostra(DateTime giorno) {
    _giorno = giorno;
    _errore = null;
    final registrato = _pesi.delGiorno(giorno);
    _kg.text = registrato == null ? '' : numero(registrato.kg);
  }

  Future<void> _scegliGiorno() async {
    final scelto = await showDatePicker(
      context: context,
      initialDate: _giorno,
      firstDate: DateTime(2000),
      lastDate: _oggi,
    );
    if (scelto != null) setState(() => _mostra(scelto));
  }

  void _salva() {
    final testi = Testi.of(context);
    num? kg;
    try {
      kg = leggiDecimale(_kg.text, massimo: pesoMassimoKg);
    } on FormatException {
      kg = null;
    }
    if (kg == null || kg < pesoMinimoKg) {
      setState(() => _errore = testi.pesoNonValido);
      return;
    }
    _pesi.salva(_giorno, kg.toDouble());
    FocusScope.of(context).unfocus();
    setState(() => _errore = null);
    ScaffoldMessenger.of(context).avvisa(testi.pesoSalvato);
  }

  void _elimina(PesoDelGiorno peso) {
    final testi = Testi.of(context);
    _pesi.elimina(peso.giorno);
    setState(() {
      if (_giorno == peso.giorno) _mostra(peso.giorno);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(testi.pesoEliminato(giornoEMese(context, peso.giorno))),
          action: SnackBarAction(
            label: testi.annulla,
            onPressed: () {
              _pesi.salva(peso.giorno, peso.kg);
              if (mounted) setState(() => _mostra(_giorno));
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final pesi = _pesi.elenco();
    final coach = widget.nucleo.collegamenti.attivi();
    final media = pesi.isEmpty ? null : mediaSettimana(pesi, pesi.last.giorno);
    final etichettaGiorno = _giorno == _oggi ? testi.oggi : giornoEMese(context, _giorno);
    return Scaffold(
      appBar: AppBar(title: Text(testi.peso)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(testi.pesoDi(etichettaGiorno), style: tema.titleMedium)),
                      TextButton.icon(
                        onPressed: _scegliGiorno,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(testi.cambiaGiorno),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _kg,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            hintText: testi.esempioPeso,
                            suffixText: 'kg',
                            errorText: _errore,
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _salva(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: FilledButton(onPressed: _salva, child: Text(testi.salva)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (pesi.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 32,
              runSpacing: 8,
              children: [
                _Dato(testi.ultimoPeso(giornoEMese(context, pesi.last.giorno)), '${numero(pesi.last.kg)} kg'),
                if (media != null) _Dato(testi.mediaSettimana, '${media.toStringAsFixed(1).replaceAll('.', ',')} kg'),
              ],
            ),
          ],
          if (pesi.length >= 2) ...[
            const SizedBox(height: 16),
            SizedBox(height: 200, child: GraficoPeso(pesi: pesi)),
            const SizedBox(height: 4),
            Text(testi.legendaGraficoPeso, style: tema.bodySmall),
          ],
          if (coach.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(testi.condividiPesoCon, style: tema.titleMedium),
            const SizedBox(height: 4),
            Text(testi.condividiPesoSpiegazione, style: tema.bodySmall),
            for (final c in coach)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c.nomeCoach),
                subtitle: Text(
                  c.pesiSupportati == false
                      ? testi.pesoNonSupportato
                      : c.condividePesi
                      ? testi.pesoCondiviso
                      : testi.pesoNonCondiviso,
                ),
                value: c.condividePesi,
                onChanged: (valore) => setState(() => _pesi.condividi(c.id, condividi: valore)),
              ),
          ],
          const SizedBox(height: 24),
          Text(testi.tuttiIPesi, style: tema.titleMedium),
          if (pesi.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(testi.nessunPesoRegistrato),
            ),
          for (final peso in pesi.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(giornoEMese(context, peso.giorno)),
              subtitle: peso.giorno.year == _oggi.year ? null : Text('${peso.giorno.year}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${numero(peso.kg)} kg', style: tema.titleSmall),
                  IconButton(
                    tooltip: testi.elimina,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _elimina(peso),
                  ),
                ],
              ),
              onTap: () => setState(() => _mostra(peso.giorno)),
            ),
        ],
      ),
    );
  }
}

/// Media dei pesi nei 7 giorni che finiscono il giorno [fine], o null se in
/// quei giorni non ce ne sono.
double? mediaSettimana(List<PesoDelGiorno> pesi, DateTime fine) {
  final inizio = fine.subtract(const Duration(days: 6));
  final valori = [
    for (final p in pesi)
      if (!p.giorno.isBefore(inizio) && !p.giorno.isAfter(fine)) p.kg,
  ];
  return valori.isEmpty ? null : valori.reduce((a, b) => a + b) / valori.length;
}

class _Dato extends StatelessWidget {
  const _Dato(this.etichetta, this.valore);

  final String etichetta;
  final String valore;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etichetta, style: tema.bodySmall),
        Text(valore, style: tema.titleLarge),
      ],
    );
  }
}

/// I pesi nel tempo: un punto per giorno e la media mobile di 7 giorni.
class GraficoPeso extends StatelessWidget {
  const GraficoPeso({super.key, required this.pesi});

  final List<PesoDelGiorno> pesi;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _Pittore(
        pesi: pesi,
        punti: schema.primary.withValues(alpha: 0.45),
        linea: schema.primary,
        griglia: schema.outlineVariant,
        testo: Theme.of(context).textTheme.bodySmall!,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _Pittore extends CustomPainter {
  _Pittore({
    required this.pesi,
    required this.punti,
    required this.linea,
    required this.griglia,
    required this.testo,
  });

  final List<PesoDelGiorno> pesi;
  final Color punti;
  final Color linea;
  final Color griglia;
  final TextStyle testo;

  @override
  void paint(Canvas canvas, Size size) {
    final primo = pesi.first.giorno;
    final giorni = max(1, pesi.last.giorno.difference(primo).inDays);
    var minimo = pesi.map((p) => p.kg).reduce(min);
    var massimo = pesi.map((p) => p.kg).reduce(max);
    final margine = max(0.5, (massimo - minimo) * 0.1);
    minimo -= margine;
    massimo += margine;
    final area = Rect.fromLTRB(44, 6, size.width - 6, size.height - 6);

    Offset posizione(DateTime giorno, double kg) => Offset(
      area.left + area.width * giorno.difference(primo).inDays / giorni,
      area.bottom - area.height * (kg - minimo) / (massimo - minimo),
    );

    final pennello = Paint()
      ..color = griglia
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = area.bottom - area.height * i / 3;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), pennello);
      final etichetta = TextPainter(
        text: TextSpan(
          text: (minimo + (massimo - minimo) * i / 3).toStringAsFixed(1).replaceAll('.', ','),
          style: testo,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      etichetta.paint(canvas, Offset(0, y - etichetta.height / 2));
    }
    final pennelloPunti = Paint()..color = punti;
    for (final p in pesi) {
      canvas.drawCircle(posizione(p.giorno, p.kg), 3, pennelloPunti);
    }
    final percorso = Path();
    for (final (i, p) in pesi.indexed) {
      final punto = posizione(p.giorno, mediaSettimana(pesi, p.giorno)!);
      i == 0 ? percorso.moveTo(punto.dx, punto.dy) : percorso.lineTo(punto.dx, punto.dy);
    }
    canvas.drawPath(
      percorso,
      Paint()
        ..color = linea
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Pittore vecchio) => vecchio.pesi != pesi || vecchio.linea != linea;
}
