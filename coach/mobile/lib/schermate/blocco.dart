import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/testi.dart';
import '../piattaforma/blocco.dart';

/// Tiene chiusa l'app finché il coach non si fa riconoscere: all'apertura e
/// dopo 5 minuti in background (§16.4). Prima del primo sblocco il contenuto non
/// viene nemmeno costruito; dopo resta montato sotto, così al ritorno il coach
/// ritrova la pagina dove l'aveva lasciata.
class CancelloBlocco extends StatefulWidget {
  const CancelloBlocco({
    super.key,
    required this.blocco,
    required this.child,
    this.tempoInBackground = const Duration(minutes: 5),
    DateTime Function()? adesso,
  }) : adesso = adesso ?? DateTime.now;

  final BloccoApp blocco;
  final Widget child;
  final Duration tempoInBackground;
  final DateTime Function() adesso;

  @override
  State<CancelloBlocco> createState() => _CancelloBloccoState();
}

class _CancelloBloccoState extends State<CancelloBlocco> {
  late final AppLifecycleListener _ciclo;
  var _sbloccata = false;
  var _maiSbloccata = true;

  /// Il dialogo del sistema è aperto: può nascondere l'app, ma non è un'uscita.
  var _inVerifica = false;
  var _senzaBlocco = false;
  DateTime? _uscitaIl;

  @override
  void initState() {
    super.initState();
    _ciclo = AppLifecycleListener(onHide: _uscita, onShow: _ritorno);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_verifica()));
  }

  @override
  void dispose() {
    _ciclo.dispose();
    super.dispose();
  }

  void _uscita() {
    if (!_inVerifica) _uscitaIl = widget.adesso();
  }

  void _ritorno() {
    if (_inVerifica) return;
    final uscita = _uscitaIl;
    _uscitaIl = null;
    if (!_sbloccata || _senzaBlocco || uscita == null) return;
    if (widget.adesso().difference(uscita) >= widget.tempoInBackground) {
      setState(() => _sbloccata = false);
      unawaited(_verifica());
    }
  }

  Future<void> _verifica() async {
    if (_inVerifica) return;
    _inVerifica = true;
    try {
      if (!await widget.blocco.disponibile()) {
        // Senza blocco schermo l'app resta usabile, e lo dice (§16.4).
        if (mounted) setState(() => _apri(senzaBlocco: true));
        return;
      }
      if (!mounted) return;
      final esito = await widget.blocco.chiedi(Testi.of(context).bloccoMotivo);
      if (esito && mounted) setState(_apri);
    } finally {
      _inVerifica = false;
    }
  }

  void _apri({bool senzaBlocco = false}) {
    _sbloccata = true;
    _maiSbloccata = false;
    _senzaBlocco = senzaBlocco;
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!_maiSbloccata) Offstage(offstage: !_sbloccata, child: widget.child),
              if (!_sbloccata)
                Scaffold(
                  body: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline, size: 48),
                            const SizedBox(height: 16),
                            Text(t.bloccoTitolo, style: tema.textTheme.titleLarge),
                            const SizedBox(height: 8),
                            Text(t.bloccoSpiegazione, textAlign: TextAlign.center),
                            const SizedBox(height: 24),
                            FilledButton(onPressed: _verifica, child: Text(t.bloccoSblocca)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_senzaBlocco)
          Material(
            color: tema.colorScheme.errorContainer,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(t.bloccoAssente, style: TextStyle(color: tema.colorScheme.onErrorContainer)),
              ),
            ),
          ),
      ],
    );
  }
}
