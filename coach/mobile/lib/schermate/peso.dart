import 'dart:math';

import 'package:flutter/material.dart';

import '../dati/modelli.dart';
import '../dati/stato_coach.dart';
import '../l10n/testi.dart';
import 'comuni.dart';

/// Il peso che l'atleta condivide (§8.5): gli stessi numeri del programma sul
/// PC, l'ultimo, la media di 7 giorni e il confronto con i 7 prima.
class SezionePeso extends StatelessWidget {
  const SezionePeso({super.key, required this.stato, required this.atletaId});

  final StatoCoach stato;
  final String atletaId;

  @override
  Widget build(BuildContext context) => LettoreDati<List<PesoGiorno>>(
    generazione: stato.generazione,
    carica: () => stato.fonte.pesi(atletaId),
    costruisci: (context, pesi, ricarica) => _Contenuto(pesi),
  );
}

/// Media dei pesi dei 7 giorni fino a [fine], o null se non ce ne sono.
double? mediaSetteGiorni(List<PesoGiorno> pesi, DateTime fine) {
  final inizio = fine.subtract(const Duration(days: 6));
  final dentro = pesi.where((p) => !p.giorno.isBefore(inizio) && !p.giorno.isAfter(fine)).toList();
  if (dentro.isEmpty) return null;
  return dentro.map((p) => p.kg).reduce((a, b) => a + b) / dentro.length;
}

class _Contenuto extends StatelessWidget {
  const _Contenuto(this.pesi);

  final List<PesoGiorno> pesi;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    if (pesi.isEmpty) return ListaVuota(t.pesoVuoto);
    final ultimo = pesi.last;
    final media = mediaSetteGiorni(pesi, ultimo.giorno);
    final precedente = mediaSetteGiorni(pesi, ultimo.giorno.subtract(const Duration(days: 7)));
    final differenza = media != null && precedente != null ? media - precedente : null;
    final recenti = pesi.length > 60 ? pesi.sublist(pesi.length - 60) : pesi;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _Numero(t.pesoUltimo, t.pesoValore(numeroLeggibile(ultimo.kg))),
            if (media != null) _Numero(t.pesoMedia, t.pesoValore(numeroLeggibile(media))),
            if (differenza != null)
              _Numero(
                t.pesoDifferenza,
                t.pesoValore('${differenza > 0 ? '+' : ''}${numeroLeggibile(differenza)}'),
              ),
          ],
        ),
        if (recenti.length >= 2) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: CustomPaint(
              painter: _GraficoPeso(recenti, Theme.of(context).colorScheme.primary),
              size: Size.infinite,
            ),
          ),
        ],
        const SizedBox(height: 16),
        for (final peso in pesi.reversed.take(60))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(soloData(peso.giorno)),
            trailing: Text(t.pesoValore(numeroLeggibile(peso.kg))),
          ),
      ],
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero(this.etichetta, this.valore);

  final String etichetta;
  final String valore;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etichetta, style: tema.textTheme.labelMedium),
        Text(valore, style: tema.textTheme.titleLarge),
      ],
    );
  }
}

class _GraficoPeso extends CustomPainter {
  const _GraficoPeso(this.pesi, this.colore);

  final List<PesoGiorno> pesi;
  final Color colore;

  @override
  void paint(Canvas canvas, Size size) {
    final valori = pesi.map((p) => p.kg);
    final minimo = valori.reduce(min);
    final massimo = valori.reduce(max);
    final ampiezza = max(massimo - minimo, 0.5);
    final inizio = pesi.first.giorno;
    final giorni = max(pesi.last.giorno.difference(inizio).inDays, 1);
    final percorso = Path();
    for (final (i, p) in pesi.indexed) {
      final x = size.width * p.giorno.difference(inizio).inDays / giorni;
      final y = size.height * (1 - (p.kg - minimo) / ampiezza) * 0.9 + size.height * 0.05;
      if (i == 0) {
        percorso.moveTo(x, y);
      } else {
        percorso.lineTo(x, y);
      }
    }
    canvas.drawPath(
      percorso,
      Paint()
        ..color = colore
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_GraficoPeso vecchio) => !identical(vecchio.pesi, pesi) || vecchio.colore != colore;
}
