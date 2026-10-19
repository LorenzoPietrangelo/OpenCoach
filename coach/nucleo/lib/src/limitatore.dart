import 'dart:collection';

/// Limite di frequenza a finestra mobile (§6.2).
class LimitatoreFrequenza {
  LimitatoreFrequenza({
    required this.massimo,
    this.finestra = const Duration(minutes: 1),
    DateTime Function()? adesso,
  }) : _adesso = adesso ?? DateTime.now;

  final int massimo;
  final Duration finestra;
  final DateTime Function() _adesso;
  final _richieste = <String, Queue<DateTime>>{};

  /// Registra una richiesta per [chiave]. Restituisce null se è ammessa,
  /// altrimenti quanto aspettare prima di riprovare.
  Duration? registra(String chiave) {
    final ora = _adesso();
    final coda = _richieste.putIfAbsent(chiave, Queue.new);
    while (coda.isNotEmpty && ora.difference(coda.first) >= finestra) {
      coda.removeFirst();
    }
    if (coda.length >= massimo) return finestra - ora.difference(coda.first);
    coda.add(ora);
    return null;
  }
}
