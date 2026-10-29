import 'dart:math';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../servizi.dart';

/// Pesi che l'atleta condivide (§8.5): l'ultimo, la media degli ultimi
/// 7 giorni, il grafico e l'elenco. Li scrive l'atleta, il coach li legge.
class PannelloPeso extends StatelessWidget {
  const PannelloPeso({
    super.key,
    required this.atleta,
    required this.coach,
    required this.aggiornamenti,
  });

  final Atleta atleta;
  final Coach coach;
  final Aggiornamenti aggiornamenti;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return ListenableBuilder(
      listenable: aggiornamenti,
      builder: (context, _) {
        final pesi = coach.nucleo.pesi.elenco(atleta.id);
        if (pesi.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(t.nessunPeso),
          );
        }
        final ultimo = pesi.last;
        final media = mediaSettimana(pesi, ultimo.giorno);
        final prima = mediaSettimana(pesi, ultimo.giorno.subtract(const Duration(days: 7)));
        final tema = Theme.of(context).textTheme;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 40,
              runSpacing: 12,
              children: [
                _Dato(etichetta: t.ultimoPeso(soloData(ultimo.giorno)), valore: chili(ultimo.kg)),
                if (media != null) _Dato(etichetta: t.mediaSettimana, valore: chili(media)),
                if (media != null && prima != null)
                  _Dato(etichetta: t.rispettoSettimanaPrima, valore: variazione(media - prima)),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(height: 260, child: GraficoPeso(pesi: pesi)),
            const SizedBox(height: 8),
            Text(t.legendaGraficoPeso, style: tema.bodySmall),
            TitoloSezione(t.tuttiIPesi),
            for (final peso in pesi.reversed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(soloData(peso.giorno)),
                trailing: Text(chili(peso.kg), style: tema.titleSmall),
              ),
          ],
        );
      },
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

String chili(double kg) => '${kg.toStringAsFixed(1).replaceAll('.', ',')} kg';

String variazione(double kg) {
  final segno = kg > 0.05 ? '+' : kg < -0.05 ? '−' : '±';
  return '$segno${kg.abs().toStringAsFixed(1).replaceAll('.', ',')} kg';
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etichetta, required this.valore});

  final String etichetta;
  final String valore;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etichetta, style: tema.bodySmall),
        Text(valore, style: tema.headlineSmall),
      ],
    );
  }
}

/// I pesi nel tempo, con la media mobile di 7 giorni.
class GraficoPeso extends StatelessWidget {
  const GraficoPeso({super.key, required this.pesi});

  final List<PesoDelGiorno> pesi;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _PittoreGrafico(
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

class _PittoreGrafico extends CustomPainter {
  _PittoreGrafico({
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

  static const _sinistra = 64.0;
  static const _sotto = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (pesi.isEmpty) return;
    final primo = pesi.first.giorno;
    final giorni = max(1, pesi.last.giorno.difference(primo).inDays);
    var minimo = pesi.map((p) => p.kg).reduce(min);
    var massimo = pesi.map((p) => p.kg).reduce(max);
    final margine = max(0.5, (massimo - minimo) * 0.1);
    minimo -= margine;
    massimo += margine;
    final area = Rect.fromLTRB(_sinistra, 8, size.width - 8, size.height - _sotto);

    Offset posizione(DateTime giorno, double kg) => Offset(
      area.left + area.width * giorno.difference(primo).inDays / giorni,
      area.bottom - area.height * (kg - minimo) / (massimo - minimo),
    );

    final pennelloGriglia = Paint()
      ..color = griglia
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final kg = minimo + (massimo - minimo) * i / 4;
      final y = area.bottom - area.height * i / 4;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), pennelloGriglia);
      _scrivi(canvas, chili(kg), Offset(0, y - 8));
    }
    _scrivi(canvas, soloData(primo), Offset(area.left, area.bottom + 4));
    if (giorni > 1) {
      _scrivi(canvas, soloData(pesi.last.giorno), Offset(area.right - 80, area.bottom + 4));
    }

    final pennelloPunti = Paint()..color = punti;
    for (final p in pesi) {
      canvas.drawCircle(posizione(p.giorno, p.kg), 3.5, pennelloPunti);
    }

    final percorso = Path();
    for (final (i, p) in pesi.indexed) {
      final media = mediaSettimana(pesi, p.giorno)!;
      final punto = posizione(p.giorno, media);
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

  void _scrivi(Canvas canvas, String testo, Offset dove) {
    final pittore = TextPainter(
      text: TextSpan(text: testo, style: this.testo),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 80);
    pittore.paint(canvas, dove);
  }

  @override
  bool shouldRepaint(_PittoreGrafico vecchio) =>
      vecchio.pesi != pesi || vecchio.linea != linea || vecchio.testo != testo;
}
