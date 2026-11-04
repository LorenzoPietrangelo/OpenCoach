import 'dart:math';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../servizi.dart';

/// Lo storico dell'atleta a colpo d'occhio (§9.3), per la scheda che sceglie il
/// coach: quanto si allena e come progredisce esercizio per esercizio. Conta
/// solo le serie fatte. I singoli allenamenti restano nelle esportazioni.
class PannelloStorico extends StatefulWidget {
  const PannelloStorico({
    super.key,
    required this.atleta,
    required this.coach,
    required this.aggiornamenti,
  });

  final Atleta atleta;
  final Coach coach;
  final Aggiornamenti aggiornamenti;

  @override
  State<PannelloStorico> createState() => _PannelloStoricoState();
}

/// Nel menu: tutti gli allenamenti, o quelli senza scheda. Gli altri valori sono
/// gli id delle schede.
const _tutte = 'tutte';
const _liberi = 'liberi';

class _PannelloStoricoState extends State<PannelloStorico> {
  /// Quello che ha scelto il coach; finché non sceglie, la scheda attiva.
  String? _vista;

  /// L'esercizio del grafico dei progressi; se non c'è più, il più frequente.
  String? _scelto;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.aggiornamenti,
    builder: (context, _) => _corpo(context),
  );

  Widget _corpo(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final allenamenti = widget.coach.nucleo.allenamenti;
    if (allenamenti.storico(widget.atleta.id).ultimo == null) {
      return Padding(padding: const EdgeInsets.all(24), child: Text(t.nessunAllenamento));
    }
    final schede = widget.coach.nucleo.schede
        .elenco(widget.atleta.id)
        .where((s) => s.stato != StatoScheda.bozza)
        .toList()
      ..sort((a, b) {
        // La scheda attiva per prima.
        final attiva = (a.stato == StatoScheda.pubblicata ? 0 : 1).compareTo(b.stato == StatoScheda.pubblicata ? 0 : 1);
        return attiva != 0 ? attiva : b.modificataIl.compareTo(a.modificataIl);
      });
    final conLiberi = allenamenti.storico(widget.atleta.id, soloLiberi: true).ultimo != null;
    final attiva = schede.where((s) => s.stato == StatoScheda.pubblicata).firstOrNull;
    final valide = {_tutte, if (conLiberi) _liberi, for (final s in schede) s.id};
    final vista = valide.contains(_vista) ? _vista! : attiva?.id ?? _tutte;
    final storico = allenamenti.storico(
      widget.atleta.id,
      schedaId: vista == _tutte || vista == _liberi ? null : vista,
      soloLiberi: vista == _liberi,
    );
    final ultimo = storico.ultimo;
    final settimane = storico.settimane;
    final esercizi = storico.esercizi;
    final esercizio = esercizi.where((e) => e.nome == _scelto).firstOrNull ?? esercizi.firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text(t.storicoDiQualeScheda, style: tema.titleMedium),
            const SizedBox(width: 16),
            Flexible(
              child: DropdownButton<String>(
                value: vista,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final s in schede)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        s.stato == StatoScheda.pubblicata
                            ? t.storicoSchedaAttiva(s.titolo)
                            : s.titolo.isEmpty
                            ? t.senzaTitolo
                            : s.titolo,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (conLiberi) DropdownMenuItem(value: _liberi, child: Text(t.storicoLiberi)),
                  DropdownMenuItem(value: _tutte, child: Text(t.storicoTutte)),
                ],
                onChanged: (scelta) => setState(() => _vista = scelta),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (ultimo == null)
          Text(t.storicoSchedaVuota)
        else ...[
        Wrap(
          spacing: 40,
          runSpacing: 12,
          children: [
            _Dato(etichetta: t.storicoTotale, valore: '${storico.totale}'),
            _Dato(etichetta: t.storicoSettimana, valore: '${settimane.last.allenamenti}'),
            _Dato(etichetta: t.storicoUltimo, valore: soloData(ultimo)),
          ],
        ),
        const SizedBox(height: 32),
        Text(t.storicoAllenamenti, style: tema.titleMedium),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: _Grafico(
            barre: true,
            soloInteri: true,
            descrizione: t.storicoAllenamenti,
            punti: [
              for (final s in settimane)
                _Punto(
                  s.allenamenti.toDouble(),
                  asse: _giornoMese(s.lunedi),
                  dettaglio: t.storicoAllenamentiDettaglio(soloData(s.lunedi), s.allenamenti),
                ),
            ],
          ),
        ),
        if (esercizio != null) ...[
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(child: Text(t.storicoProgressi, style: tema.titleMedium)),
              DropdownButton<String>(
                value: esercizio.nome,
                underline: const SizedBox.shrink(),
                items: [
                  for (final e in esercizi) DropdownMenuItem(value: e.nome, child: Text(e.nome)),
                ],
                onChanged: (nome) => setState(() => _scelto = nome),
              ),
            ],
          ),
          Text(switch (esercizio.misura) {
            MisuraEsercizio.stima1Rm => t.storicoMisuraStima,
            MisuraEsercizio.carico => t.storicoMisuraCarico,
            MisuraEsercizio.ripetizioni => t.storicoMisuraRipetizioni,
            MisuraEsercizio.durata => t.storicoMisuraDurata,
          }, style: tema.bodySmall),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: _Grafico(
              key: ValueKey(esercizio.nome),
              barre: false,
              descrizione: '${t.storicoProgressi}: ${esercizio.nome}',
              punti: _puntiEsercizio(esercizio),
            ),
          ),
        ],
        ],
      ],
    );
  }

  List<_Punto> _puntiEsercizio(EsercizioStorico esercizio) {
    final primo = esercizio.punti.first.giorno;
    final giorni = esercizio.punti.last.giorno.difference(primo).inHours / 24;
    String unita(double valore) => switch (esercizio.misura) {
      MisuraEsercizio.stima1Rm || MisuraEsercizio.carico => '${_numero(valore)} kg',
      MisuraEsercizio.ripetizioni => _numero(valore),
      MisuraEsercizio.durata => '${_numero(valore)} s',
    };
    return [
      for (final p in esercizio.punti)
        _Punto(
          p.valore,
          posizione: giorni == 0 ? 0.5 : p.giorno.difference(primo).inHours / 24 / giorni,
          asse: _giornoMese(p.giorno),
          dettaglio: '${soloData(p.giorno)}: ${unita(p.valore)}',
        ),
    ];
  }
}

String _giornoMese(DateTime giorno) => '${giorno.day}/${giorno.month}';

/// «12.400», «82,5».
String _numero(num valore) {
  final intero = valore == valore.roundToDouble();
  final testo = intero ? '${valore.round()}' : valore.toStringAsFixed(1).replaceAll('.', ',');
  return testo.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))(?<!,\d*)'), (_) => '.');
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

class _Punto {
  const _Punto(this.valore, {required this.asse, required this.dettaglio, this.posizione});

  final double valore;

  /// L'etichetta sull'asse orizzontale.
  final String asse;

  /// Il testo quando il mouse è sul punto.
  final String dettaglio;

  /// Da 0 a 1 lungo l'asse orizzontale; solo per le linee.
  final double? posizione;
}

/// Un grafico di una sola serie: barre che partono da zero, oppure una linea.
class _Grafico extends StatefulWidget {
  const _Grafico({
    super.key,
    required this.punti,
    required this.barre,
    required this.descrizione,
    this.soloInteri = false,
  });

  final List<_Punto> punti;
  final bool barre;
  final String descrizione;

  /// Sull'asse verticale ci sono conteggi, senza decimali.
  final bool soloInteri;

  @override
  State<_Grafico> createState() => _GraficoState();
}

class _GraficoState extends State<_Grafico> {
  int? _sotto;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    final testo = Theme.of(context).textTheme.bodySmall!;
    return LayoutBuilder(
      builder: (context, vincoli) {
        final geometria = _Geometria(vincoli.biggest, widget.punti, widget.barre, widget.soloInteri);
        return Semantics(
          label: widget.descrizione,
          value: widget.punti.map((p) => p.dettaglio).join('; '),
          child: MouseRegion(
            onHover: (evento) => setState(() => _sotto = geometria.piuVicino(evento.localPosition.dx)),
            onExit: (_) => setState(() => _sotto = null),
            child: CustomPaint(
              size: Size.infinite,
              painter: _Pittore(
                geometria: geometria,
                sotto: _sotto,
                marca: schema.primary,
                griglia: schema.outlineVariant,
                sfondo: schema.surface,
                testo: testo.copyWith(color: schema.onSurfaceVariant),
                sfondoDettaglio: schema.inverseSurface,
                testoDettaglio: testo.copyWith(color: schema.onInverseSurface),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Dove sta ogni punto: la usano sia il disegno sia il mouse.
class _Geometria {
  _Geometria(Size size, this.punti, this.barre, bool soloInteri)
    : area = Rect.fromLTRB(56, 12, size.width - 12, size.height - 24) {
    final valori = punti.map((p) => p.valore);
    final massimo = valori.isEmpty ? 0.0 : valori.reduce(max);
    final minimo = barre || valori.isEmpty ? 0.0 : valori.reduce(min);
    tacche = _tacche(minimo, massimo, soloInteri: soloInteri);
  }

  final List<_Punto> punti;
  final bool barre;
  final Rect area;
  late final List<double> tacche;

  double get _larghezzaFetta => area.width / punti.length;

  /// La larghezza delle barre: sottili, con lo spazio tra una e l'altra.
  double get larghezzaBarra => min(28, _larghezzaFetta - 4).clamp(2, 28).toDouble();

  double x(int i) => barre
      ? area.left + (i + 0.5) * _larghezzaFetta
      : area.left + (punti[i].posizione ?? 0.5) * area.width;

  double y(double valore) {
    final basso = tacche.first;
    final alto = tacche.last;
    return area.bottom - area.height * (valore - basso) / (alto - basso);
  }

  int? piuVicino(double dx) {
    if (punti.isEmpty) return null;
    var migliore = 0;
    for (var i = 1; i < punti.length; i++) {
      if ((x(i) - dx).abs() < (x(migliore) - dx).abs()) migliore = i;
    }
    return migliore;
  }
}

/// Tacche tonde dell'asse verticale, circa quattro.
List<double> _tacche(double minimo, double massimo, {required bool soloInteri}) {
  if (massimo <= minimo) {
    massimo = minimo == 0 ? 1 : minimo * 1.1;
    minimo = minimo == 0 ? 0 : minimo * 0.9;
  }
  final grezzo = (massimo - minimo) / 4;
  final scala = pow(10, (log(grezzo) / ln10).floor()).toDouble();
  var passo = [1.0, 2.0, 2.5, 5.0, 10.0].map((m) => m * scala).firstWhere((p) => p >= grezzo);
  if (soloInteri) passo = max(1, passo.ceilToDouble());
  final tacche = <double>[(minimo / passo).floor() * passo];
  while (tacche.last < massimo) {
    tacche.add(tacche.last + passo);
  }
  return tacche;
}

class _Pittore extends CustomPainter {
  _Pittore({
    required this.geometria,
    required this.sotto,
    required this.marca,
    required this.griglia,
    required this.sfondo,
    required this.testo,
    required this.sfondoDettaglio,
    required this.testoDettaglio,
  });

  final _Geometria geometria;
  final int? sotto;
  final Color marca;
  final Color griglia;
  final Color sfondo;
  final TextStyle testo;
  final Color sfondoDettaglio;
  final TextStyle testoDettaglio;

  /// Le etichette orizzontali non si toccano: se ce ne sono tante, una ogni
  /// tanto, tenendo l'ultima.
  static const _ogniBarre = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometria;
    if (g.punti.isEmpty) return;
    final area = g.area;
    final pennelloGriglia = Paint()
      ..color = griglia
      ..strokeWidth = 1;
    for (final tacca in g.tacche) {
      final y = g.y(tacca);
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), pennelloGriglia);
      final etichetta = _testo(_numero(tacca), testo);
      etichetta.paint(canvas, Offset(area.left - etichetta.width - 8, y - etichetta.height / 2));
    }
    g.barre ? _disegnaBarre(canvas) : _disegnaLinea(canvas);
    _disegnaAsse(canvas);
    final indice = sotto;
    if (indice != null && indice < g.punti.length) _disegnaDettaglio(canvas, size, indice);
  }

  void _disegnaBarre(Canvas canvas) {
    final g = geometria;
    for (final (i, punto) in g.punti.indexed) {
      if (punto.valore <= 0) continue;
      final larghezza = g.larghezzaBarra;
      final rettangolo = Rect.fromLTRB(
        g.x(i) - larghezza / 2,
        g.y(punto.valore),
        g.x(i) + larghezza / 2,
        g.area.bottom,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rettangolo,
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        Paint()..color = sotto == null || sotto == i ? marca : marca.withValues(alpha: 0.55),
      );
    }
  }

  void _disegnaLinea(Canvas canvas) {
    final g = geometria;
    final indice = sotto;
    if (indice != null) {
      canvas.drawLine(
        Offset(g.x(indice), g.area.top),
        Offset(g.x(indice), g.area.bottom),
        Paint()
          ..color = griglia
          ..strokeWidth = 1,
      );
    }
    final percorso = Path();
    for (final (i, punto) in g.punti.indexed) {
      final dove = Offset(g.x(i), g.y(punto.valore));
      i == 0 ? percorso.moveTo(dove.dx, dove.dy) : percorso.lineTo(dove.dx, dove.dy);
    }
    canvas.drawPath(
      percorso,
      Paint()
        ..color = marca
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    for (final (i, punto) in g.punti.indexed) {
      final dove = Offset(g.x(i), g.y(punto.valore));
      canvas.drawCircle(dove, i == indice ? 7 : 6, Paint()..color = sfondo);
      canvas.drawCircle(dove, i == indice ? 5 : 4, Paint()..color = marca);
    }
  }

  void _disegnaAsse(Canvas canvas) {
    final g = geometria;
    final ultimo = g.punti.length - 1;
    var precedente = double.negativeInfinity;
    // Dall'ultima all'indietro: la data più recente c'è sempre.
    for (var i = ultimo; i >= 0; i--) {
      final dovuta = g.barre ? (ultimo - i) % _ogniBarre == 0 : i == 0 || i == ultimo;
      if (!dovuta) continue;
      final etichetta = _testo(g.punti[i].asse, testo);
      final sinistra = (g.x(i) - etichetta.width / 2).clamp(0.0, g.area.right - etichetta.width).toDouble();
      if (precedente != double.negativeInfinity && sinistra + etichetta.width + 8 > precedente) continue;
      etichetta.paint(canvas, Offset(sinistra, g.area.bottom + 6));
      precedente = sinistra;
    }
  }

  void _disegnaDettaglio(Canvas canvas, Size size, int indice) {
    final g = geometria;
    final punto = g.punti[indice];
    final etichetta = _testo(punto.dettaglio, testoDettaglio);
    const margine = 8.0;
    final larghezza = etichetta.width + margine * 2;
    final altezza = etichetta.height + margine;
    final sinistra = (g.x(indice) - larghezza / 2).clamp(0.0, max(0.0, size.width - larghezza)).toDouble();
    final sopra = max(0.0, g.y(punto.valore) - altezza - 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(sinistra, sopra, larghezza, altezza),
        const Radius.circular(6),
      ),
      Paint()..color = sfondoDettaglio,
    );
    etichetta.paint(canvas, Offset(sinistra + margine, sopra + margine / 2));
  }

  TextPainter _testo(String testo, TextStyle stile) => TextPainter(
    text: TextSpan(text: testo, style: stile),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  bool shouldRepaint(_Pittore vecchio) =>
      vecchio.sotto != sotto ||
      vecchio.geometria.punti != geometria.punti ||
      vecchio.geometria.area != geometria.area ||
      vecchio.marca != marca;
}
