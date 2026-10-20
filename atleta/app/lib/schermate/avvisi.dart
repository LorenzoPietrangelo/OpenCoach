import 'package:flutter/material.dart';

/// Messaggi brevi in fondo allo schermo.
extension Avvisi on ScaffoldMessengerState {
  /// Mostra [testo] al posto del messaggio eventualmente visibile, invece di
  /// metterlo in coda dietro.
  void avvisa(String testo) {
    hideCurrentSnackBar();
    showSnackBar(SnackBar(content: Text(testo)));
  }
}
