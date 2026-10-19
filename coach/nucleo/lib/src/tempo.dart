import 'package:protocollo/protocollo.dart';

String _due(int n) => n.toString().padLeft(2, '0');

/// Istante in UTC a larghezza fissa, per l'archivio: i testi si confrontano
/// nello stesso ordine degli istanti.
String istante(DateTime t) {
  final u = t.toUtc();
  return '${formattaData(u)}T${_due(u.hour)}:${_due(u.minute)}:${_due(u.second)}'
      '.${u.millisecond.toString().padLeft(3, '0')}Z';
}

DateTime leggiIstante(String testo) => DateTime.parse(testo);

DateTime? leggiIstanteFacoltativo(Object? testo) =>
    testo is String ? DateTime.parse(testo) : null;
