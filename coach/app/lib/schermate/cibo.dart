import 'dart:math';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:protocollo/protocollo.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../servizi.dart';

/// Il cibo dell'atleta (§8.8): l'obiettivo che fissa il coach e quello che
/// l'atleta mangia, se lo condivide. Il coach legge, non scrive diete.
class PannelloCibo extends StatefulWidget {
  const PannelloCibo({
    super.key,
    required this.atleta,
    required this.coach,
    required this.aggiornamenti,
  });

  final Atleta atleta;
  final Coach coach;
  final Aggiornamenti aggiornamenti;

  @override
  State<PannelloCibo> createState() => _PannelloCiboState();
}

class _PannelloCiboState extends State<PannelloCibo> {
  GestioneCibo get _cibo => widget.coach.nucleo.cibo;

  Future<void> _modificaObiettivo(ObiettivoCibo? attuale) async {
    final esito = await showDialog<_EsitoObiettivo>(
      context: context,
      builder: (context) => _DialogoObiettivo(attuale: attuale),
    );
    if (esito == null) return;
    _cibo.fissaObiettivo(widget.atleta.id, esito.obiettivo);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.aggiornamenti,
      builder: (context, _) {
        final obiettivo = _cibo.obiettivo(widget.atleta.id);
        final giornate = _cibo.elenco(widget.atleta.id);
        final recenti = giornate.length > 7 ? giornate.sublist(giornate.length - 7) : giornate;
        final media = recenti.isEmpty
            ? null
            : recenti.fold(ValoriCibo.zero, (s, g) => s + g.totali).per(1 / recenti.length);
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.obiettivoCibo, style: tema.titleMedium),
                          const SizedBox(height: 4),
                          Text(obiettivo == null ? t.nessunObiettivoCibo : testoObiettivo(t, obiettivo)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton.tonal(
                      onPressed: () => _modificaObiettivo(obiettivo),
                      child: Text(obiettivo == null ? t.fissaObiettivo : t.modificaObiettivo),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (giornate.isEmpty)
              Text(t.nessunCibo)
            else ...[
              Text(t.mediaCiboSettimana, style: tema.bodySmall),
              Text(testoValori(media!), style: tema.headlineSmall),
              const SizedBox(height: 24),
              SizedBox(
                height: 220,
                child: GraficoCalorie(giornate: giornate, obiettivo: obiettivo?.kcal),
              ),
              const SizedBox(height: 8),
              Text(t.legendaGraficoCibo, style: tema.bodySmall),
              TitoloSezione(t.giorniCibo),
              for (final g in giornate.reversed) _Giorno(giornata: g),
            ],
          ],
        );
      },
    );
  }
}

/// `2200 kcal · P 140 g · C 250 g · G 70 g`, con i soli macronutrienti fissati.
String testoObiettivo(Testi t, ObiettivoCibo o) => [
  '${migliaia(o.kcal)} kcal',
  if (o.proteineG != null) 'P ${o.proteineG} g',
  if (o.carboidratiG != null) 'C ${o.carboidratiG} g',
  if (o.grassiG != null) 'G ${o.grassiG} g',
].join(' · ');

/// `1.850 kcal · P 140 g · C 190 g · G 58 g`.
String testoValori(ValoriCibo v) => [
  '${migliaia(v.kcal.round())} kcal',
  'P ${(v.proteine ?? 0).round()} g',
  'C ${(v.carboidrati ?? 0).round()} g',
  'G ${(v.grassi ?? 0).round()} g',
].join(' · ');

/// `1.850`: il punto separa le migliaia, come in italiano.
String migliaia(int n) {
  final cifre = n.abs().toString();
  final parti = <String>[];
  for (var fine = cifre.length; fine > 0; fine -= 3) {
    parti.insert(0, cifre.substring(max(0, fine - 3), fine));
  }
  return '${n < 0 ? '−' : ''}${parti.join('.')}';
}

String nomePasto(Testi t, String pasto) => switch (pasto) {
  'colazione' => t.pastoColazione,
  'pranzo' => t.pastoPranzo,
  'cena' => t.pastoCena,
  _ => t.pastoSpuntini,
};

/// Un giorno: i totali e, aprendolo, i pasti con le voci.
class _Giorno extends StatelessWidget {
  const _Giorno({required this.giornata});

  final GiornataCibo giornata;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(soloData(giornata.giorno)),
      subtitle: Text(testoValori(giornata.totali)),
      children: [
        for (final pasto in pastiCibo)
          if (giornata.delPasto(pasto) case final voci when voci.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(nomePasto(t, pasto), style: tema.titleSmall),
              ),
            ),
            for (final v in voci)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text([v.nome, if (v.marca != null) v.marca!].join(' · ')),
                subtitle: Text(
                  '${grammi(v.grammi)} · '
                  '${v.fonte == FonteCibo.openFoodFacts ? t.fonteOpenFoodFacts : t.fonteAtleta}',
                ),
                trailing: Text(testoValori(v.valori), style: tema.bodySmall),
              ),
          ],
      ],
    );
  }
}

/// `80 g`, `12,5 g`.
String grammi(double g) =>
    '${g == g.roundToDouble() ? g.round() : g.toStringAsFixed(1).replaceAll('.', ',')} g';

class _EsitoObiettivo {
  const _EsitoObiettivo(this.obiettivo);

  final ObiettivoCibo? obiettivo;
}

class _DialogoObiettivo extends StatefulWidget {
  const _DialogoObiettivo({required this.attuale});

  final ObiettivoCibo? attuale;

  @override
  State<_DialogoObiettivo> createState() => _DialogoObiettivoState();
}

class _DialogoObiettivoState extends State<_DialogoObiettivo> {
  late final _kcal = TextEditingController(text: widget.attuale?.kcal.toString() ?? '');
  late final _proteine = TextEditingController(text: widget.attuale?.proteineG?.toString() ?? '');
  late final _carboidrati = TextEditingController(
    text: widget.attuale?.carboidratiG?.toString() ?? '',
  );
  late final _grassi = TextEditingController(text: widget.attuale?.grassiG?.toString() ?? '');
  var _errore = false;

  @override
  void dispose() {
    for (final c in [_kcal, _proteine, _carboidrati, _grassi]) {
      c.dispose();
    }
    super.dispose();
  }

  void _salva() {
    int? intero(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
    final kcal = intero(_kcal);
    final obiettivo = kcal == null
        ? null
        : ObiettivoCibo(
            kcal: kcal,
            proteineG: intero(_proteine),
            carboidratiG: intero(_carboidrati),
            grassiG: intero(_grassi),
          );
    final illeggibile = [_proteine, _carboidrati, _grassi].any(
      (c) => c.text.trim().isNotEmpty && intero(c) == null,
    );
    if (obiettivo == null || illeggibile || validaObiettivoCibo(obiettivo.toJson()).isNotEmpty) {
      setState(() => _errore = true);
      return;
    }
    Navigator.pop(context, _EsitoObiettivo(obiettivo));
  }

  Widget _campo(TextEditingController c, String etichetta, String unita) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => setState(() => _errore = false),
      onSubmitted: (_) => _salva(),
      decoration: InputDecoration(
        labelText: etichetta,
        suffixText: unita,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return AlertDialog(
      title: Text(t.obiettivoCibo),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.obiettivoSpiegazione),
            const SizedBox(height: 16),
            _campo(_kcal, t.calorie, 'kcal'),
            _campo(_proteine, t.proteine, 'g'),
            _campo(_carboidrati, t.carboidrati, 'g'),
            _campo(_grassi, t.grassi, 'g'),
            if (_errore)
              Text(t.obiettivoNonValido, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        if (widget.attuale != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const _EsitoObiettivo(null)),
            child: Text(t.togliObiettivo),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.annulla)),
        FilledButton(onPressed: _salva, child: Text(t.salva)),
      ],
    );
  }
}

/// Le calorie di ogni giorno delle ultime 4 settimane, con la linea
/// dell'obiettivo.
class GraficoCalorie extends StatelessWidget {
  const GraficoCalorie({super.key, required this.giornate, required this.obiettivo});

  final List<GiornataCibo> giornate;
  final int? obiettivo;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _PittoreCalorie(
        giornate: giornate,
        obiettivo: obiettivo,
        barre: schema.primary,
        linea: schema.tertiary,
        griglia: schema.outlineVariant,
        testo: Theme.of(context).textTheme.bodySmall!,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PittoreCalorie extends CustomPainter {
  _PittoreCalorie({
    required this.giornate,
    required this.obiettivo,
    required this.barre,
    required this.linea,
    required this.griglia,
    required this.testo,
  });

  final List<GiornataCibo> giornate;
  final int? obiettivo;
  final Color barre;
  final Color linea;
  final Color griglia;
  final TextStyle testo;

  static const _giorni = 28;
  static const _sinistra = 56.0;
  static const _sotto = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (giornate.isEmpty) return;
    final ultimo = giornate.last.giorno;
    final primo = ultimo.subtract(const Duration(days: _giorni - 1));
    final visibili = [
      for (final g in giornate)
        if (!g.giorno.isBefore(primo)) g,
    ];
    final massimo = max(
      max(visibili.map((g) => g.totali.kcal).fold(0.0, max), (obiettivo ?? 0).toDouble()) * 1.1,
      500.0,
    );
    final area = Rect.fromLTRB(_sinistra, 8, size.width - 8, size.height - _sotto);
    double y(double kcal) => area.bottom - area.height * kcal / massimo;

    final pennelloGriglia = Paint()
      ..color = griglia
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final kcal = massimo * i / 4;
      canvas.drawLine(Offset(area.left, y(kcal)), Offset(area.right, y(kcal)), pennelloGriglia);
      _scrivi(canvas, migliaia(kcal.round()), Offset(0, y(kcal) - 8));
    }
    _scrivi(canvas, soloData(primo), Offset(area.left, area.bottom + 4));
    _scrivi(canvas, soloData(ultimo), Offset(area.right - 80, area.bottom + 4));

    final larghezza = area.width / _giorni;
    final pennelloBarre = Paint()..color = barre;
    for (final g in visibili) {
      final indice = g.giorno.difference(primo).inDays;
      final x = area.left + larghezza * indice;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x + larghezza * 0.15, y(g.totali.kcal), x + larghezza * 0.85, area.bottom),
          const Radius.circular(2),
        ),
        pennelloBarre,
      );
    }
    if (obiettivo case final kcal?) {
      canvas.drawLine(
        Offset(area.left, y(kcal.toDouble())),
        Offset(area.right, y(kcal.toDouble())),
        Paint()
          ..color = linea
          ..strokeWidth = 2,
      );
    }
  }

  void _scrivi(Canvas canvas, String testo, Offset dove) {
    final pittore = TextPainter(
      text: TextSpan(text: testo, style: this.testo),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 80);
    pittore.paint(canvas, dove);
  }

  @override
  bool shouldRepaint(_PittoreCalorie vecchio) =>
      vecchio.giornate != giornate || vecchio.obiettivo != obiettivo || vecchio.barre != barre;
}
