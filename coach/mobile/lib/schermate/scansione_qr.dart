import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart' show Code, Format, ReaderWidget;
import 'package:protocollo/protocollo.dart' show InvitoNonValido, UriTelefonoCoach, VersioneInvitoSconosciuta;

import '../l10n/testi.dart';

/// Inquadra il QR sul PC (§16.2) e si chiude con il testo letto. La decodifica
/// avviene sul telefono, senza servizi esterni.
class ScansioneQr extends StatefulWidget {
  const ScansioneQr({super.key});

  static Future<String?> apri(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<String>(builder: (_) => const ScansioneQr()));

  @override
  State<ScansioneQr> createState() => _ScansioneQrState();
}

class _ScansioneQrState extends State<ScansioneQr> {
  var _letto = false;
  var _altroCodice = false;
  var _senzaFotocamera = false;

  void _scansionato(Code codice) {
    final testo = codice.text;
    if (_letto || !codice.isValid || testo == null) return;
    try {
      UriTelefonoCoach.analizza(testo);
    } on InvitoNonValido {
      if (!_altroCodice) setState(() => _altroCodice = true);
      return;
    } on VersioneInvitoSconosciuta {
      // Lo spiega la schermata di collegamento, che chiede di aggiornare.
    }
    _letto = true;
    Navigator.of(context).pop(testo);
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.scansioneTitolo)),
      body: _senzaFotocamera
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(t.scansioneSenzaFotocamera, textAlign: TextAlign.center),
              ),
            )
          : Stack(
              children: [
                ReaderWidget(
                  codeFormat: Format.qrCode,
                  onScan: _scansionato,
                  onControllerCreated: (_, errore) {
                    if (errore != null && mounted) setState(() => _senzaFotocamera = true);
                  },
                  // Il QR è grande: si cerca in gran parte dell'inquadratura.
                  cropPercent: 0.8,
                  tryHarder: true,
                  showGallery: false,
                  showToggleCamera: false,
                  scanDelaySuccess: const Duration(milliseconds: 500),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _altroCodice ? t.scansioneAltroCodice : t.scansioneAiuto,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
