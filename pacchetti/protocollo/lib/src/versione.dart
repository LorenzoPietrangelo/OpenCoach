final _versione = RegExp(r'^(\d{1,6})\.(\d{1,6})\.(\d{1,6})(?:[-+][0-9A-Za-z.+-]+)?$');

/// Vero se [valore] è una versione `maggiore.minore.correzione`.
bool versioneValida(Object? valore) =>
    valore is String && _versione.hasMatch(valore);

/// Negativo se [a] precede [b], zero se sono uguali, positivo altrimenti.
/// Le etichette dopo `-` o `+` non contano.
int confrontaVersioni(String a, String b) {
  final pa = _parti(a);
  final pb = _parti(b);
  for (var i = 0; i < 3; i++) {
    final differenza = pa[i].compareTo(pb[i]);
    if (differenza != 0) return differenza;
  }
  return 0;
}

List<int> _parti(String versione) {
  final m = _versione.firstMatch(versione);
  if (m == null) throw FormatException('Versione non valida', versione);
  return [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)];
}
