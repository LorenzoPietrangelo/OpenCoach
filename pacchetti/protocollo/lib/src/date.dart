String _due(int n) => n.toString().padLeft(2, '0');
String _quattro(int n) => n.toString().padLeft(4, '0');

/// Data e ora in ISO 8601 con fuso orario, come nel protocollo (§6.2):
/// `2026-10-21T18:30:00+02:00`.
String formattaDataOra(DateTime istante) {
  final locale = istante.toLocal();
  final scarto = locale.timeZoneOffset;
  final segno = scarto.isNegative ? '-' : '+';
  final minuti = scarto.inMinutes.abs();
  return '${_quattro(locale.year)}-${_due(locale.month)}-${_due(locale.day)}'
      'T${_due(locale.hour)}:${_due(locale.minute)}:${_due(locale.second)}'
      '$segno${_due(minuti ~/ 60)}:${_due(minuti % 60)}';
}

/// Data semplice `YYYY-MM-DD`.
String formattaData(DateTime giorno) =>
    '${_quattro(giorno.year)}-${_due(giorno.month)}-${_due(giorno.day)}';

final _dataOra = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d{1,6})?'
  r'(Z|[+-](\d{2}):(\d{2}))$',
);
final _data = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Data e ora ISO 8601 con fuso orario obbligatorio; null se [valore] non lo è.
DateTime? analizzaDataOra(Object? valore) {
  if (valore is! String) return null;
  final m = _dataOra.firstMatch(valore);
  if (m == null) return null;
  final valida = _componentiValide(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  );
  if (!valida) return null;
  if (m[9] != null && (int.parse(m[9]!) > 23 || int.parse(m[10]!) > 59)) {
    return null;
  }
  return DateTime.parse(valore);
}

/// Data `YYYY-MM-DD` (in UTC); null se [valore] non lo è.
DateTime? analizzaData(Object? valore) {
  if (valore is! String) return null;
  final m = _data.firstMatch(valore);
  if (m == null) return null;
  final anno = int.parse(m[1]!);
  final mese = int.parse(m[2]!);
  final giorno = int.parse(m[3]!);
  if (!_componentiValide(anno, mese, giorno, 0, 0, 0)) return null;
  return DateTime.utc(anno, mese, giorno);
}

bool _componentiValide(int a, int me, int g, int o, int mi, int s) {
  final d = DateTime.utc(a, me, g, o, mi, s);
  return d.year == a &&
      d.month == me &&
      d.day == g &&
      d.hour == o &&
      d.minute == mi &&
      d.second == s;
}
