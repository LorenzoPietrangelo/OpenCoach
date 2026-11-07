import 'dart:async';

import 'package:flutter/material.dart';

import '../dati/collegamento.dart';
import '../dati/stato_coach.dart';
import '../l10n/testi.dart';
import '../piattaforma/qr_di_prova.dart';
import 'scansione_qr.dart';

/// La prima schermata: si collega il telefono al PC con il QR (§16.2).
class SchermataCollega extends StatefulWidget {
  const SchermataCollega({super.key, required this.stato, this.qrDiProva, this.scansiona = ScansioneQr.apri});

  final StatoCoach stato;

  /// Il QR aperto come link: solo nella build di debug, per le prove.
  final QrDiProva? qrDiProva;
  final Future<String?> Function(BuildContext) scansiona;

  @override
  State<SchermataCollega> createState() => _SchermataCollegaState();
}

class _SchermataCollegaState extends State<SchermataCollega> {
  FaseCollegamento? _fase;
  ProblemaCollegamento? _problema;

  @override
  void initState() {
    super.initState();
    widget.qrDiProva?.addListener(_controllaQrDiProva);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controllaQrDiProva());
  }

  @override
  void dispose() {
    widget.qrDiProva?.removeListener(_controllaQrDiProva);
    super.dispose();
  }

  void _controllaQrDiProva() {
    if (_fase != null) return;
    if (widget.qrDiProva?.prendi() case final testo?) unawaited(_collega(testo));
  }

  void _avanza(FaseCollegamento fase) {
    if (mounted) setState(() => _fase = fase);
  }

  Future<void> _inquadra() async {
    final testo = await widget.scansiona(context);
    if (testo != null && mounted) await _collega(testo);
  }

  Future<void> _collega(String testo) async {
    setState(() {
      _problema = null;
      _fase = FaseCollegamento.avvioTor;
    });
    final servizio = widget.stato.collegamento;
    try {
      final letto = await servizio.leggi(testo, avanzamento: _avanza);
      if (!mounted) return;
      final conferma = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final t = Testi.of(context);
          return AlertDialog(
            title: Text(t.confermaTitolo(letto.nomeCoach)),
            content: Text(t.confermaTesto),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.annulla)),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.confermaAzione)),
            ],
          );
        },
      );
      if (conferma != true) {
        await letto.annulla();
        if (mounted) setState(() => _fase = null);
        return;
      }
      // Da qui la schermata se ne va: l'app mostra gli atleti.
      await widget.stato.usaCredenziali(await letto.conferma(avanzamento: _avanza));
    } on ErroreCollegamento catch (e) {
      if (mounted) {
        setState(() {
          _problema = e.problema;
          _fase = null;
        });
      }
    }
  }

  String _testoFase(Testi t, FaseCollegamento fase) => switch (fase) {
    FaseCollegamento.avvioTor => t.faseAvvioTor,
    FaseCollegamento.ricercaPc => t.faseRicercaPc,
    FaseCollegamento.attesaPc => t.faseAttesaPc,
    FaseCollegamento.collegamento => t.faseCollegamento,
  };

  String _testoProblema(Testi t, ProblemaCollegamento problema) => switch (problema) {
    ProblemaCollegamento.codiceNonValido => t.erroreCodice,
    ProblemaCollegamento.aggiornaApp => t.erroreAggiorna,
    ProblemaCollegamento.qrNonValido => t.erroreQr,
    ProblemaCollegamento.qrInUso => t.erroreQrInUso,
    ProblemaCollegamento.torNonParte => t.erroreTor,
    ProblemaCollegamento.pcIrraggiungibile => t.errorePc,
    ProblemaCollegamento.inatteso => t.erroreInatteso,
  };

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context);
    final fase = _fase;
    final problema = _problema;
    return Scaffold(
      appBar: AppBar(title: Text(t.nomeApp)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(t.collegaTitolo, style: tema.textTheme.headlineSmall),
            const SizedBox(height: 16),
            Text(t.collegaSpiegazione),
            const SizedBox(height: 12),
            Text(t.collegaAvviso, style: TextStyle(color: tema.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            if (fase != null) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(_testoFase(t, fase)),
            ] else
              FilledButton.icon(
                onPressed: _inquadra,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(t.collegaInquadra),
              ),
            if (problema != null) ...[
              const SizedBox(height: 16),
              Text(_testoProblema(t, problema), style: TextStyle(color: tema.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
