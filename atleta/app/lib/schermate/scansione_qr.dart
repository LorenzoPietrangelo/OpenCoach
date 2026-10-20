import 'package:atleta_nucleo/atleta_nucleo.dart' show ProblemaAbbinamento;
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart'
    show Code, Format, ReaderWidget;
import 'package:protocollo/protocollo.dart'
    show InvitoNonValido, UriInvito, VersioneInvitoSconosciuta;

import '../l10n/testi.dart';

/// Inquadra il QR d'invito che il coach mostra sul suo PC (§5.2) e si chiude
/// con il testo letto: l'URI intero, che il QR contiene in modalità byte.
/// La decodifica avviene sul telefono, con zxing-cpp, senza servizi esterni.
class ScansioneQr extends StatefulWidget {
  const ScansioneQr({super.key});

  /// Apre la scansione: restituisce il testo del QR, o null se l'atleta torna
  /// indietro.
  static Future<String?> apri(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<String>(builder: (_) => const ScansioneQr()));

  @override
  State<ScansioneQr> createState() => _ScansioneQrState();
}

class _ScansioneQrState extends State<ScansioneQr> {
  var _letto = false;

  /// L'ultimo QR inquadrato non era un invito di Open Coach.
  var _altroCodice = false;

  /// La fotocamera non si apre, per esempio perché manca il permesso.
  var _senzaFotocamera = false;

  void _scansionato(Code codice) {
    final testo = codice.text;
    if (_letto || !codice.isValid || testo == null) return;
    try {
      UriInvito.analizza(testo);
    } on InvitoNonValido {
      // Un altro QR: si continua a cercare quello dell'invito.
      if (!_altroCodice) setState(() => _altroCodice = true);
      return;
    } on VersioneInvitoSconosciuta {
      // Un invito per un'app più recente: lo spiega la schermata dell'invito,
      // che chiede di aggiornare l'app (§5.2).
    }
    _letto = true;
    Navigator.of(context).pop(testo);
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(testi.scansionaQr)),
      body: _senzaFotocamera
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  testi.fotocameraNonDisponibile,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Stack(
              children: [
                ReaderWidget(
                  codeFormat: Format.qrCode,
                  onScan: _scansionato,
                  onControllerCreated: (_, errore) {
                    if (errore != null && mounted) {
                      setState(() => _senzaFotocamera = true);
                    }
                  },
                  // Il QR di un invito è grande (versione 11): si cerca in
                  // gran parte dell'inquadratura.
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
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _altroCodice
                              ? ProblemaAbbinamento.codiceNonValido.messaggio
                              : testi.inquadraQr,
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
