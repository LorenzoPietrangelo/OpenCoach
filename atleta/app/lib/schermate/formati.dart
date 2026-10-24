import 'package:flutter/material.dart';

import '../l10n/testi.dart';

/// Data breve e ora, come «21/10/2026 18:30».
String quando(BuildContext context, DateTime istante) {
  final locale = MaterialLocalizations.of(context);
  final ora = istante.toLocal();
  return '${locale.formatShortDate(ora)} '
      '${locale.formatTimeOfDay(TimeOfDay.fromDateTime(ora))}';
}

/// Giorno della settimana, data e ora, come «mar 21 ott, 18:30».
String giornoEOra(BuildContext context, DateTime istante) {
  final locale = MaterialLocalizations.of(context);
  final ora = istante.toLocal();
  return '${locale.formatMediumDate(ora)}, '
      '${locale.formatTimeOfDay(TimeOfDay.fromDateTime(ora))}';
}

/// Giorno e mese, come «20 ott». Per le date semplici del protocollo, che
/// non hanno fuso orario.
String giornoEMese(BuildContext context, DateTime giorno) =>
    MaterialLocalizations.of(context).formatShortMonthDay(giorno);

/// Numero con la virgola decimale e senza zeri inutili: «62,5», «80».
String numero(num valore) =>
    (valore == valore.roundToDouble() ? valore.round() : valore)
        .toString()
        .replaceAll('.', ',');

/// Durata del timer o del recupero, come «2:30» o «1:05:00».
String durata(Duration tempo) {
  final secondi = tempo.inSeconds;
  String due(int n) => n.toString().padLeft(2, '0');
  final ore = secondi ~/ 3600;
  final minuti = secondi % 3600 ~/ 60;
  return ore > 0
      ? '$ore:${due(minuti)}:${due(secondi % 60)}'
      : '$minuti:${due(secondi % 60)}';
}

final _intero = RegExp(r'^\d{1,5}$');
final _decimale = RegExp(r'^\d{1,5}(?:[.,]\d{1,3})?$');

/// Intero da 0 a [massimo] scritto dall'atleta; null se il testo è vuoto.
/// Lancia [FormatException] se il testo non lo è.
int? leggiIntero(String testo, {required int massimo}) {
  final pulito = testo.trim();
  if (pulito.isEmpty) return null;
  if (!_intero.hasMatch(pulito)) throw const FormatException();
  final valore = int.parse(pulito);
  if (valore > massimo) throw const FormatException();
  return valore;
}

/// Numero da 0 a [massimo], con la virgola o con il punto, e se c'è
/// [passo] multiplo di [passo]; null se il testo è vuoto. Lancia
/// [FormatException] se il testo non lo è.
num? leggiDecimale(String testo, {required num massimo, num? passo}) {
  final pulito = testo.trim();
  if (pulito.isEmpty) return null;
  if (!_decimale.hasMatch(pulito)) throw const FormatException();
  final valore = num.parse(pulito.replaceAll(',', '.'));
  if (valore > massimo ||
      (passo != null && valore / passo != (valore / passo).roundToDouble())) {
    throw const FormatException();
  }
  return valore == valore.roundToDouble() ? valore.round() : valore;
}

/// Una riga della prescrizione del coach (§8.1), come «4 × 6-8 · 75% 1RM ·
/// recupero 2:30 · RIR 1-2». Tutti i campi sono facoltativi.
String testoPrescrizione(
  Testi testi, {
  int? serie,
  String? ripetizioni,
  String? carico,
  Duration? recupero,
  String? rir,
}) {
  final rip = ripetizioni == null || ripetizioni.isEmpty ? null : ripetizioni;
  return [
    if (serie != null && rip != null)
      testi.serieRipetizioni(serie, rip)
    else if (serie != null)
      testi.numeroSerie(serie)
    else
      ?rip,
    if (carico != null && carico.isNotEmpty) carico,
    if (recupero != null) testi.recuperoDi(durata(recupero)),
    if (rir != null && rir.isNotEmpty) testi.rirDi(rir),
  ].join(' · ');
}
