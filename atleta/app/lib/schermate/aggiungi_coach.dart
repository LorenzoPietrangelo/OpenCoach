import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';

import '../l10n/testi.dart';
import '../piattaforma/inviti_in_arrivo.dart';
import 'avvisi.dart';
import 'scansione_qr.dart';

/// Abbinamento con il QR d'invito, con il link incollato a mano o con quello
/// aperto da un'altra app (§5.2, §5.3, §10.2): legge l'invito, chiede
/// «Collegarti a …?» e collega il telefono. Gli errori sono quelli del §5.4.
class AggiungiCoach extends StatefulWidget {
  const AggiungiCoach({
    super.key,
    required this.nucleo,
    this.inviti,
    this.scansiona = ScansioneQr.apri,
  });

  final NucleoAtleta nucleo;

  /// I link d'invito aperti da un'altra app: quello per cui si apre la
  /// schermata e quelli che arrivano mentre è aperta. Con un link si collega
  /// subito, come con il QR.
  final InvitiInArrivo? inviti;

  /// Inquadra il QR e restituisce il suo testo, o null se l'atleta ci
  /// rinuncia. I test la sostituiscono, perché la fotocamera non c'è.
  final Future<String?> Function(BuildContext context) scansiona;

  @override
  State<AggiungiCoach> createState() => _AggiungiCoachState();
}

class _AggiungiCoachState extends State<AggiungiCoach> {
  final _invito = TextEditingController();
  var _inCorso = false;
  String? _errore;

  /// A che punto è il collegamento in corso; null prima del primo passo.
  AvanzamentoAbbinamento? _avanzamento;

  void _avanza(AvanzamentoAbbinamento avanzamento) {
    if (mounted) setState(() => _avanzamento = avanzamento);
  }

  @override
  void initState() {
    super.initState();
    widget.inviti?.addListener(_invitoArrivato);
    WidgetsBinding.instance.addPostFrameCallback((_) => _invitoArrivato());
  }

  @override
  void dispose() {
    widget.inviti?.removeListener(_invitoArrivato);
    _invito.dispose();
    super.dispose();
  }

  /// Si collega con il link appena aperto. Con un collegamento già in corso
  /// il link si scarta: di solito è lo stesso, toccato due volte.
  void _invitoArrivato() {
    if (!mounted) return;
    final rotta = ModalRoute.of(context);
    // Mentre la schermata si chiude, il link lo apre l'elenco dei coach.
    if (rotta == null || !rotta.isActive) return;
    final link = widget.inviti?.prendi();
    if (link == null || _inCorso) return;
    // Il link vale più del QR: se la fotocamera è aperta, si chiude.
    Navigator.of(context).popUntil((altra) => altra == rotta);
    _invito.text = link;
    unawaited(_collega(link));
  }

  Future<void> _scansiona() async {
    final testo = await widget.scansiona(context);
    if (testo != null && mounted) await _collega(testo);
  }

  Future<void> _collega(String testo) async {
    // Un QR letto proprio mentre arrivava un link, o il contrario.
    if (_inCorso) return;
    final testi = Testi.of(context);
    setState(() {
      _inCorso = true;
      _errore = null;
      _avanzamento = null;
    });
    try {
      final invito = await widget.nucleo.leggiInvito(
        testo,
        avanzamento: _avanza,
      );
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
      // Emesso il token, il collegamento c'è già: conferma e prima sync
      // possono richiedere qualche minuto, mentre il coach ripubblica il
      // servizio con la chiave del telefono, e proseguono in background. Lo
      // stato della sync del coach le mostra.
      final collegato = Completer<void>();
      final abbinamento = invito.collega(
        avanzamento: (avanzamento) {
          _avanza(avanzamento);
          if (avanzamento.fase == FaseAbbinamento.conferma &&
              !collegato.isCompleted) {
            collegato.complete();
          }
        },
      );
      await Future.any([collegato.future, abbinamento]);
      unawaited(
        abbinamento.then<void>(
          (_) {},
          onError: (Object e) => debugPrint('Prima sync non riuscita: $e'),
        ),
      );
      if (!mounted) return;
      final messaggi = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messaggi.avvisa(testi.collegatoA(invito.nomeCoach));
    } on ErroreAbbinamento catch (e) {
      if (mounted) setState(() => _errore = e.messaggio);
    } finally {
      if (mounted) {
        setState(() {
          _inCorso = false;
          _avanzamento = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context);
    final errore = _errore;
    return Scaffold(
      appBar: AppBar(title: Text(testi.titoloInvito)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(testi.spiegazioneInvito),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _inCorso ? null : _scansiona,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(testi.scansionaQr),
          ),
          const SizedBox(height: 32),
          Text(testi.oppureIncolla, style: tema.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _invito,
            enabled: !_inCorso,
            decoration: InputDecoration(labelText: testi.etichettaInvito),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          if (_inCorso)
            _BarraAbbinamento(_avanzamento)
          else
            OutlinedButton(
              onPressed: () => _collega(_invito.text),
              child: Text(testi.continua),
            ),
          if (errore != null)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                errore,
                style: TextStyle(color: tema.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

/// Barra d'avanzamento dell'abbinamento, con la fase in corso: collegarsi
/// via Tor può richiedere qualche minuto, e l'atleta deve vedere che
/// procede.
class _BarraAbbinamento extends StatelessWidget {
  const _BarraAbbinamento(this.avanzamento);

  final AvanzamentoAbbinamento? avanzamento;

  /// Quota della barra all'inizio di ogni fase; l'avvio di Tor la riempie
  /// fino al 40% in base al suo bootstrap.
  static double _valore(AvanzamentoAbbinamento? a) => switch (a?.fase) {
    null => 0.02,
    FaseAbbinamento.avvioTor => 0.02 + 0.38 * (a!.percentoTor ?? 0) / 100,
    FaseAbbinamento.collegamento || FaseAbbinamento.attesaCoach => 0.5,
    FaseAbbinamento.abbinamento => 0.7,
    FaseAbbinamento.conferma => 0.85,
  };

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final a = avanzamento;
    final testo = switch (a?.fase) {
      null => testi.collegamentoInCorso,
      FaseAbbinamento.avvioTor => testi.faseAvvioTor(a!.percentoTor ?? 0),
      FaseAbbinamento.collegamento => testi.faseCollegamento,
      FaseAbbinamento.attesaCoach => testi.faseAttesaCoach(a!.tentativo),
      FaseAbbinamento.abbinamento => testi.faseAbbinamento,
      FaseAbbinamento.conferma => testi.faseConferma,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: _valore(a)),
          duration: const Duration(milliseconds: 400),
          builder: (context, valore, _) => LinearProgressIndicator(
            value: valore,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // La barra sta ferma tra una fase e l'altra: questo mostra che
            // il telefono sta comunque lavorando.
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(testo)),
          ],
        ),
      ],
    );
  }
}
