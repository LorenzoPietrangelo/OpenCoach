import 'dart:io';
import 'dart:typed_data';

import 'package:atleta_nucleo/atleta_nucleo.dart';

/// Segnaposto finché Tor non è integrato nell'app (§10.1: tor-android su
/// Android, Tor.framework su iOS). Ogni sync e ogni abbinamento si fermano
/// con «Tor non parte»: l'interfaccia funziona, la rete no.
class TorNonIntegrato implements TrasportoTor {
  const TorNonIntegrato();

  @override
  Future<void> avvia() async => throw const TorNonParte();

  @override
  Future<void> ferma() async {}

  @override
  Future<void> impostaChiave(String indirizzo, Uint8List chiavePrivata) async {}

  @override
  Future<void> rimuoviChiave(String indirizzo) async {}

  @override
  HttpClient creaHttpClient() =>
      throw UnsupportedError('Tor non è ancora integrato nell\'app');
}
