import 'dart:async';
import 'dart:math';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:protocollo/protocollo.dart';

import '../l10n/testi.dart';
import '../tema.dart';
import 'avvisi.dart';
import 'formati.dart';

/// Il peso dell'atleta, un valore al giorno (§8.5): si registra quello di
/// oggi o di un altro giorno, si vede l'andamento e si sceglie se condividerlo
/// con il coach. Nelle sezioni dell'app la barra in alto è una sola: [barra] è
/// falso.
class SchermataPeso extends StatefulWidget {
  const SchermataPeso({super.key, required this.nucleo, this.barra = true});

  final NucleoAtleta nucleo;
  final bool barra;

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
      appBar: widget.barra ? AppBar(title: Text(testi.peso)) : null,
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
                      Expanded(
                        child: Text(
                          testi.pesoDi(etichettaGiorno),
                          style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
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
                          style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: testi.esempioPeso,
                            suffixText: 'kg',
                            suffixStyle: tema.titleMedium?.copyWith(color: ColoriAtleta.testoSecondario),
                            errorText: _errore,
                          ),
                          onSubmitted: (_) => _salva(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 60,
                        child: FilledButton(onPressed: _salva, child: Text(testi.salva)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (pesi.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Dato(
                    testi.ultimoPeso(giornoEMese(context, pesi.last.giorno)),
                    '${numero(pesi.last.kg)} kg',
                  ),
                ),
                if (media != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Dato(
                      testi.mediaSettimana,
                      '${media.toStringAsFixed(1).replaceAll('.', ',')} kg',
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (pesi.length >= 2)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 200, child: GraficoPeso(pesi: pesi)),
                    const SizedBox(height: 8),
                    Text(testi.legendaGraficoPeso, style: tema.bodySmall),
                  ],
                ),
              ),
            )
          else if (pesi.length == 1) ...[
            const SizedBox(height: 8),
            Text(testi.graficoPesoDaDueGiorni, style: tema.bodySmall),
          ],
          if (coach.isNotEmpty)
            BloccoPrivacy(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(testi.condividiPesoCon, style: tema.titleSmall),
                ),
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
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(testi.condividiPesoSpiegazione, style: tema.bodySmall),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Text(
                    testi.tuttiIPesi,
                    style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (pesi.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Text(testi.nessunPesoRegistrato),
                  ),
                for (final peso in pesi.reversed) ...[
                  const Divider(),
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 16, right: 4),
                    title: Text(giornoEMese(context, peso.giorno)),
                    subtitle: peso.giorno.year == _oggi.year ? null : Text('${peso.giorno.year}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${numero(peso.kg)} kg', style: tema.titleSmall),
                        IconButton(
                          tooltip: testi.elimina,
                          icon: const Icon(Icons.delete_outline),
                          color: ColoriAtleta.testoSecondario,
                          onPressed: () => _elimina(peso),
                        ),
                      ],
                    ),
                    onTap: () => setState(() => _mostra(peso.giorno)),
                  ),
                ],
              ],
            ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etichetta, style: tema.bodySmall),
            const SizedBox(height: 4),
            Text(valore, style: tema.headlineSmall),
          ],
        ),
      ),
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
        punti: const Color(0xFF7FBFB5),
        linea: schema.primary,
        griglia: schema.outlineVariant,
        testo: Theme.of(context).textTheme.bodySmall!,
        primoGiorno: giornoEMese(context, pesi.first.giorno),
        ultimoGiorno: giornoEMese(context, pesi.last.giorno),
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
    required this.primoGiorno,
    required this.ultimoGiorno,
  });

  final List<PesoDelGiorno> pesi;
  final Color punti;
  final Color linea;
  final Color griglia;
  final TextStyle testo;
  final String primoGiorno;
  final String ultimoGiorno;

  @override
  void paint(Canvas canvas, Size size) {
    final primo = pesi.first.giorno;
    final giorni = max(1, pesi.last.giorno.difference(primo).inDays);
    var minimo = pesi.map((p) => p.kg).reduce(min);
    var massimo = pesi.map((p) => p.kg).reduce(max);
    final margine = max(0.5, (massimo - minimo) * 0.1);
    minimo -= margine;
    massimo += margine;
    // A sinistra i chili, sotto i giorni: i punti non ci finiscono sopra.
    final area = Rect.fromLTRB(52, 6, size.width - 6, size.height - 24);

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
    TextPainter giorno(String testoGiorno) => TextPainter(
      text: TextSpan(text: testoGiorno, style: testo),
      textDirection: TextDirection.ltr,
    )..layout();
    giorno(primoGiorno).paint(canvas, Offset(area.left, area.bottom + 6));
    final fine = giorno(ultimoGiorno);
    fine.paint(canvas, Offset(area.right - fine.width, area.bottom + 6));
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
