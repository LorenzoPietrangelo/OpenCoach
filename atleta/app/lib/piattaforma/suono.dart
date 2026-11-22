import 'dart:io';

import 'package:flutter/services.dart';

const _canale = MethodChannel('org.opencoach.atleta/suono');

/// Il segnale di fine recupero (§10.2). Su Android suona e vibra il codice
/// Kotlin dell'app (`SuonoRecupero`), su iOS il codice Swift (`AppDelegate`):
/// `SystemSound.alert` su nessuno dei due fa niente. Altrove, o se il canale
/// manca, resta il suono di sistema.
Future<void> suonaFineRecupero() async {
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await _canale.invokeMethod<void>('suona');
      return;
    } on MissingPluginException {
      // Nei test non c'è il codice nativo.
    } on PlatformException {
      // Il suono non è partito: resta il ripiego qui sotto.
    }
  }
  await HapticFeedback.vibrate();
  await SystemSound.play(SystemSoundType.alert);
}
