import 'dart:async';

import 'package:flutter/services.dart';

import '../dati/annunci.dart';
import '../dati/stato_coach.dart';
import '../l10n/testi.dart';

/// Il titolo e il testo delle notifiche: chi e quanti, mai il contenuto (§16.4).
Map<String, Object> notificaDa(Annuncio annuncio, Testi t) => {
  'atleta': annuncio.atletaId,
  'titolo': annuncio.nome,
  'testo': [
    if (annuncio.messaggi > 0) t.notificaMessaggi(annuncio.messaggi),
    if (annuncio.risposte > 0) t.notificaRisposte(annuncio.risposte),
  ].join(', '),
};

/// I controlli in background su Android (§16.4), dal lato Dart: WorkManager e le
/// notifiche stanno nel codice Kotlin (MotoreFlutter, LavoroControllo).
class ControlliInBackground {
  ControlliInBackground(this._stato, {required this.testi, this.mostraInterfaccia, MethodChannel? canale})
    : _canale = canale ?? canalePredefinito;

  static const canalePredefinito = MethodChannel('org.opencoach.coach/background');

  final StatoCoach _stato;
  final Testi testi;
  final MethodChannel _canale;

  /// Esegue `runApp` in un motore partito senza interfaccia, quando poi si apre
  /// l'app.
  final void Function()? mostraInterfaccia;
  bool? _pianificati;

  /// Riceve le richieste del codice Kotlin e dice che il codice Dart è pronto.
  /// Restituisce vero se va mostrata l'interfaccia.
  Future<bool> collega() async {
    _canale.setMethodCallHandler(_gestisci);
    _stato.addListener(() => unawaited(_allinea()));
    await _allinea();
    return await _canale.invokeMethod<bool>('pronto') ?? false;
  }

  /// Il lavoro periodico c'è solo con il telefono collegato.
  Future<void> _allinea() async {
    final attivi = _stato.collegato;
    if (attivi == _pianificati) return;
    _pianificati = attivi;
    await _canale.invokeMethod('pianifica', {'attiva': attivi});
    if (attivi) await _canale.invokeMethod('permessoNotifiche');
  }

  Future<Object?> _gestisci(MethodCall chiamata) async {
    switch (chiamata.method) {
      case 'controllaInBackground':
        return [
          for (final annuncio in await _stato.controllaInBackground()) notificaDa(annuncio, testi),
        ];
      case 'mostraInterfaccia':
        mostraInterfaccia?.call();
        return null;
    }
    throw MissingPluginException(chiamata.method);
  }

  /// Ogni quanti minuti gira il controllo; 0 se è disattivato.
  Future<int> frequenza() async => await _canale.invokeMethod<int>('frequenza') ?? 15;

  Future<void> impostaFrequenza(int minuti, {required bool attiva}) =>
      _canale.invokeMethod('impostaFrequenza', {'minuti': minuti, 'attiva': attiva});

  /// Vero se il telefono non lascia lavorare l'app in background.
  Future<bool> limitata() async => await _canale.invokeMethod<bool>('limitata') ?? false;

  Future<void> apriImpostazioniApp() => _canale.invokeMethod('apriImpostazioniApp');
}
