import 'package:flutter/widgets.dart';

/// I link d'invito `opencoach://invito` aperti da un'altra app (§5.3, punto
/// 1). Android (MainActivity) e iOS li passano a Flutter come una rotta da
/// aprire: qui si fermano, perché l'app non ha rotte con un nome, e aspettano
/// la schermata d'abbinamento.
///
/// Va creato subito dopo `WidgetsFlutterBinding.ensureInitialized()`, prima di
/// ogni `await`: il link che ha aperto l'app arriva appena parte il codice
/// Dart, quando l'interfaccia non c'è ancora.
class InvitiInArrivo extends ChangeNotifier with WidgetsBindingObserver {
  InvitiInArrivo() {
    WidgetsBinding.instance.addObserver(this);
  }

  String? _inAttesa;

  /// Il link arrivato e non ancora aperto. Se prima ne arriva un altro, resta
  /// quello nuovo.
  String? get inAttesa => _inAttesa;

  /// Toglie il link in attesa e lo restituisce.
  String? prendi() {
    final link = _inAttesa;
    _inAttesa = null;
    return link;
  }

  /// Vero se il link è di Open Coach: il sistema sa così che l'app l'ha
  /// aperto. Gli altri, che l'app non riceve, li gestirebbe il Navigator.
  @override
  Future<bool> didPushRouteInformation(RouteInformation informazioni) async {
    final uri = informazioni.uri;
    if (uri.scheme != 'opencoach') return false;
    _inAttesa = uri.toString();
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
