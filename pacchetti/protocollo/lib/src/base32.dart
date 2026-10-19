import 'dart:typed_data';

const _alfabeto = 'abcdefghijklmnopqrstuvwxyz234567';

/// Codifica [dati] in base32 RFC 4648, minuscolo e senza padding (§4).
String codificaBase32(List<int> dati) {
  final risultato = StringBuffer();
  var accumulo = 0;
  var bit = 0;
  for (final byte in dati) {
    accumulo = (accumulo << 8) | (byte & 0xff);
    bit += 8;
    while (bit >= 5) {
      bit -= 5;
      risultato.writeCharCode(_alfabeto.codeUnitAt((accumulo >> bit) & 31));
    }
    accumulo &= (1 << bit) - 1;
  }
  if (bit > 0) {
    risultato.writeCharCode(_alfabeto.codeUnitAt((accumulo << (5 - bit)) & 31));
  }
  return risultato.toString();
}

/// Decodifica un testo base32 senza padding, maiuscolo o minuscolo.
///
/// Restituisce null se il testo contiene caratteri non validi o non è una
/// codifica canonica, così ogni valore ha una sola rappresentazione.
Uint8List? decodificaBase32(String testo) {
  final risultato = <int>[];
  var accumulo = 0;
  var bit = 0;
  for (final carattere in testo.codeUnits) {
    final valore = _valore(carattere);
    if (valore < 0) return null;
    accumulo = (accumulo << 5) | valore;
    bit += 5;
    if (bit >= 8) {
      bit -= 8;
      risultato.add((accumulo >> bit) & 0xff);
      accumulo &= (1 << bit) - 1;
    }
  }
  if (bit >= 5 || accumulo != 0) return null;
  return Uint8List.fromList(risultato);
}

int _valore(int carattere) {
  if (carattere >= 0x61 && carattere <= 0x7a) return carattere - 0x61;
  if (carattere >= 0x41 && carattere <= 0x5a) return carattere - 0x41;
  if (carattere >= 0x32 && carattere <= 0x37) return carattere - 0x32 + 26;
  return -1;
}
