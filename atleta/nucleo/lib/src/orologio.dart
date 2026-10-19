import 'dart:async';

/// Tempo per l'app: ora corrente, attese e timer. I test lo sostituiscono con
/// un orologio controllato, così ritentativi e sync periodiche non aspettano
/// davvero.
abstract interface class Orologio {
  DateTime adesso();

  Future<void> attendi(Duration durata);

  /// Esegue [azione] dopo [durata], salvo che il timer venga annullato.
  Timer timer(Duration durata, void Function() azione);
}

/// Orologio del sistema.
class OrologioDiSistema implements Orologio {
  const OrologioDiSistema();

  @override
  DateTime adesso() => DateTime.now();

  @override
  Future<void> attendi(Duration durata) => Future<void>.delayed(durata);

  @override
  Timer timer(Duration durata, void Function() azione) => Timer(durata, azione);
}
