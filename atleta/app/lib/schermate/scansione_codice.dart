import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart' show Code, Format, ReaderWidget;

import '../l10n/testi.dart';

/// Inquadra il codice a barre di una confezione e si chiude con le cifre
/// (§10.3). Come il QR d'invito, la decodifica avviene sul telefono, con
/// zxing-cpp, senza servizi esterni.
class ScansioneCodice extends StatefulWidget {
  const ScansioneCodice({super.key});

  /// Apre la scansione: restituisce il codice, o null se l'atleta torna
  /// indietro.
  static Future<String?> apri(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<String>(builder: (_) => const ScansioneCodice()));

  @override
  State<ScansioneCodice> createState() => _ScansioneCodiceState();
}

class _ScansioneCodiceState extends State<ScansioneCodice> {
  var _letto = false;
  var _senzaFotocamera = false;

  void _scansionato(Code codice) {
    final testo = codice.text;
    if (_letto || !codice.isValid || testo == null) return;
    if (!RegExp(r'^\d{8,14}$').hasMatch(testo)) return;
    _letto = true;
    Navigator.of(context).pop(testo);
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(testi.scansionaCodice)),
      body: _senzaFotocamera
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(testi.fotocameraNonDisponibile, textAlign: TextAlign.center),
              ),
            )
          : Stack(
              children: [
                ReaderWidget(
                  codeFormat: Format.ean13 | Format.ean8 | Format.upca | Format.upce,
                  onScan: _scansionato,
                  onControllerCreated: (_, errore) {
                    if (errore != null && mounted) setState(() => _senzaFotocamera = true);
                  },
                  cropPercent: 0.7,
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
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          testi.inquadraCodice,
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
