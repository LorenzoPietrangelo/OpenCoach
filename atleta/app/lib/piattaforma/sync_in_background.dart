import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../l10n/testi.dart';

/// Notifica delle schede nuove o aggiornate di un coach, dopo una sync in
/// background (§7.4).
class NotificaSchede {
  const NotificaSchede({
    required this.coachId,
    required this.titolo,
    required this.testo,
  });

  final int coachId;
  final String titolo;
  final String testo;

  /// Come la legge il codice Kotlin (NotificheSchede).
  Map<String, Object> perAndroid() => {
    'coach': coachId,
    'titolo': titolo,
    'testo': testo,
  };
}

/// Una notifica per ogni coach che ha mandato schede nuove o nuove revisioni,
/// con i loro titoli.
List<NotificaSchede> notificheSchede(
  List<EsitoSync> esiti,
  String Function(int coachId) nomeCoach,
  Testi testi,
) => [
  for (final esito in esiti)
    if (esito.schedeNuove.isNotEmpty)
      NotificaSchede(
        coachId: esito.coachId,
        titolo: testi.notificaSchede(
          esito.schedeNuove.length,
          nomeCoach(esito.coachId),
        ),
        testo: esito.schedeNuove.map((scheda) => scheda.titolo).join(', '),
      ),
];

/// Sync in background su Android (§7.4), dal lato Dart. WorkManager e le
/// notifiche stanno nel codice Kotlin dell'app (MotoreFlutter, LavoroSync):
/// quando è il momento chiede a [sincronizza] le notifiche da mostrare, sul
/// nucleo del processo, lo stesso dell'interfaccia se l'app è aperta.
/// Le scelte di Android per la batteria di un'app.
enum StatoBatteria {
  /// Le sync in background partono quasi in orario.
  senzaRestrizioni,

  /// Il default: Android può rimandarle anche di ore.
  ottimizzata,

  /// Non partono mai: le schede arrivano solo ad app aperta.
  limitata,
}

class SyncInBackground {
  SyncInBackground(
    this._nucleo, {
    MethodChannel canale = canalePredefinito,
    this.mostraInterfaccia,
  }) : _canale = canale;

  static const canalePredefinito = MethodChannel(
    'org.opencoach.atleta/background',
  );

  final NucleoAtleta _nucleo;
  final MethodChannel _canale;

  /// Esegue `runApp` in un motore partito senza interfaccia, quando poi si
  /// apre l'app.
  final void Function()? mostraInterfaccia;

  StreamSubscription<int>? _cambiamenti;
  bool? _pianificata;

  /// Riceve le richieste del codice Kotlin, allinea il lavoro periodico ai
  /// coach collegati e dice che il nucleo è pronto. Restituisce vero se
  /// l'app è stata aperta nel frattempo e va mostrata l'interfaccia.
  Future<bool> collega() async {
    _canale.setMethodCallHandler(_gestisci);
    _cambiamenti = _nucleo.cambiamenti.listen(
      (_) => unawaited(aggiornaPianificazione()),
    );
    await aggiornaPianificazione();
    return await _canale.invokeMethod<bool>('pronto') ?? false;
  }

  Future<void> chiudi() async {
    await _cambiamenti?.cancel();
    _canale.setMethodCallHandler(null);
  }

  Future<Object?> _gestisci(MethodCall chiamata) async {
    switch (chiamata.method) {
      case 'sincronizzaInBackground':
        return [
          for (final notifica in await sincronizza()) notifica.perAndroid(),
        ];
      case 'mostraInterfaccia':
        mostraInterfaccia?.call();
        return null;
    }
    throw MissingPluginException(chiamata.method);
  }

  /// Sincronizza tutti i coach e prepara le notifiche delle schede nuove.
  Future<List<NotificaSchede>> sincronizza() async {
    final esiti = await _nucleo.sincronizzaInBackground();
    return notificheSchede(
      esiti,
      (id) => _nucleo.collegamenti.cerca(id)?.nomeCoach ?? '',
      lookupTesti(const Locale('it')),
    );
  }

  /// Il lavoro periodico c'è solo con almeno un coach collegato: lo si
  /// aggiorna quando la situazione cambia.
  Future<void> aggiornaPianificazione() async {
    final attiva = _haCoach;
    if (attiva == _pianificata) return;
    _pianificata = attiva;
    await _canale.invokeMethod('pianifica', {'attiva': attiva});
  }

  /// Ogni quanti minuti gira la sync in background; 0 se è disattivata.
  Future<int> frequenza() async =>
      await _canale.invokeMethod<int>('frequenza') ?? 60;

  Future<void> impostaFrequenza(int minuti) => _canale.invokeMethod(
    'impostaFrequenza',
    {'minuti': minuti, 'attiva': _haCoach},
  );

  /// Vero se il telefono non lascia lavorare l'app in background: con la
  /// batteria «Limitata» le sync in background non partono.
  Future<bool> limitata() async =>
      await _canale.invokeMethod<bool>('limitata') ?? false;

  /// Come il telefono tratta la batteria dell'app, che decide quanto
  /// ritardano le sync in background.
  Future<StatoBatteria> statoBatteria() async =>
      switch (await _canale.invokeMethod<String>('statoBatteria')) {
        'limitata' => StatoBatteria.limitata,
        'senza_restrizioni' => StatoBatteria.senzaRestrizioni,
        _ => StatoBatteria.ottimizzata,
      };

  /// Fino a quando l'atleta ha rimandato il consiglio sulla batteria; null se
  /// non l'ha mai rimandato.
  Future<DateTime?> consiglioBatteriaRimandato() async {
    final millisecondi =
        await _canale.invokeMethod<int>('avvisoBatteriaRimandato') ?? 0;
    return millisecondi == 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millisecondi, isUtc: true);
  }

  Future<void> rimandaConsiglioBatteria(DateTime fino) => _canale.invokeMethod(
    'rimandaAvvisoBatteria',
    {'fino': fino.millisecondsSinceEpoch},
  );

  /// Apre le informazioni sull'app nelle impostazioni del telefono.
  Future<void> apriImpostazioniApp() =>
      _canale.invokeMethod('apriImpostazioniApp');

  /// Se l'app va in background durante una sync, la sync prosegue come
  /// lavoro accelerato (§7.4).
  Future<void> proseguiSeInCorso() async {
    if (_nucleo.sync.occupato) await _canale.invokeMethod('prosegui');
  }

  /// Con almeno un coach collegato chiede il permesso per le notifiche, che
  /// da Android 13 serve.
  Future<void> chiediPermessoNotifiche() async {
    if (_haCoach) await _canale.invokeMethod('permessoNotifiche');
  }

  bool get _haCoach => _nucleo.collegamenti.attivi().isNotEmpty;
}
