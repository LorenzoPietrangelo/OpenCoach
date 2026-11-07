import 'package:flutter/widgets.dart';

/// Il QR aperto come link, per le prove senza fotocamera. Il filtro che lo fa
/// arrivare sta solo nel manifest della build di debug: nell'app da distribuire
/// il QR si inquadra e basta (§16.2).
///
/// Va creato subito dopo `WidgetsFlutterBinding.ensureInitialized()`, prima di
/// ogni `await`: il link che ha aperto l'app arriva appena parte il codice Dart.
class QrDiProva extends ChangeNotifier with WidgetsBindingObserver {
  QrDiProva() {
    WidgetsBinding.instance.addObserver(this);
  }

  String? _inAttesa;

  String? prendi() {
    final testo = _inAttesa;
    _inAttesa = null;
    return testo;
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    final uri = routeInformation.uri;
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
