import 'date.dart';
import 'casuale.dart';

/// Tipi di domanda di un questionario (§8.6).
abstract final class TipoDomanda {
  static const testoBreve = 'testo_breve';
  static const testoLungo = 'testo_lungo';
  static const numero = 'numero';
  static const sceltaSingola = 'scelta_singola';
  static const sceltaMultipla = 'scelta_multipla';
  static const scala = 'scala';

  static const tutti = {testoBreve, testoLungo, numero, sceltaSingola, sceltaMultipla, scala};
  static const conScelte = {sceltaSingola, sceltaMultipla};
}

/// Limiti dei questionari (§8.6).
abstract final class LimitiQuestionario {
  static const domande = 100;
  static const opzioni = 50;
  static const testoDomanda = 500;
  static const opzione = 200;
  static const descrizione = 5000;
  static const testoBreve = 500;
  static const testoLungo = 5000;
  static const fotoMassime = 10;
  static const istruzioniFoto = 2000;
  static const numeroMassimo = 1000000;
}

/// Problemi del contenuto di un questionario come lo scrive il coach: titolo,
/// descrizione, domande e foto (§8.6). Lista vuota se è valido.
List<String> validaContenutoQuestionario(Object? contenuto) {
  final errori = <String>[];
  void errore(String percorso, String messaggio) => errori.add('$percorso: $messaggio');
  if (contenuto is! Map<String, Object?>) return ['questionario: deve essere un oggetto'];

  final titolo = contenuto['titolo'];
  if (titolo is! String || titolo.trim().isEmpty || titolo.length > 200) {
    errore('titolo', 'da 1 a 200 caratteri');
  }
  final descrizione = contenuto['descrizione'];
  if (descrizione != null &&
      (descrizione is! String || descrizione.length > LimitiQuestionario.descrizione)) {
    errore('descrizione', 'al massimo ${LimitiQuestionario.descrizione} caratteri');
  }

  final domande = contenuto['domande'];
  if (domande is! List<Object?>) {
    errore('domande', 'deve essere una lista');
  } else {
    final foto = contenuto['foto'];
    if (domande.isEmpty && foto == null) errore('domande', 'serve almeno una domanda o una richiesta di foto');
    if (domande.length > LimitiQuestionario.domande) {
      errore('domande', 'al massimo ${LimitiQuestionario.domande}');
    }
    final id = <Object?>{};
    for (final (i, d) in domande.indexed) {
      final p = 'domande[$i]';
      if (d is! Map<String, Object?>) {
        errore(p, 'deve essere un oggetto');
        continue;
      }
      if (!uuidValido(d['id']) || !id.add(d['id'])) errore('$p.id', 'UUID mancante o ripetuto');
      final tipo = d['tipo'];
      if (!TipoDomanda.tutti.contains(tipo)) errore('$p.tipo', 'tipo sconosciuto');
      final testo = d['testo'];
      if (testo is! String || testo.trim().isEmpty || testo.length > LimitiQuestionario.testoDomanda) {
        errore('$p.testo', 'da 1 a ${LimitiQuestionario.testoDomanda} caratteri');
      }
      if (d['obbligatoria'] is! bool) errore('$p.obbligatoria', 'deve essere true o false');
      if (TipoDomanda.conScelte.contains(tipo)) {
        final opzioni = d['opzioni'];
        if (opzioni is! List<Object?> ||
            opzioni.isEmpty ||
            opzioni.length > LimitiQuestionario.opzioni ||
            opzioni.any((o) => o is! String || o.trim().isEmpty || o.length > LimitiQuestionario.opzione) ||
            opzioni.toSet().length != opzioni.length) {
          errore('$p.opzioni', 'da 1 a ${LimitiQuestionario.opzioni} opzioni diverse, non vuote');
        }
        if (d['altro'] != null && d['altro'] is! bool) errore('$p.altro', 'deve essere true o false');
      }
      if (tipo == TipoDomanda.numero) {
        final unita = d['unita'];
        if (unita != null && (unita is! String || unita.length > 20)) {
          errore('$p.unita', 'al massimo 20 caratteri');
        }
        if (d['peso_corporeo'] != null && d['peso_corporeo'] is! bool) {
          errore('$p.peso_corporeo', 'deve essere true o false');
        }
      }
    }
  }

  final foto = contenuto['foto'];
  if (foto != null) {
    if (foto is! Map<String, Object?>) {
      errore('foto', 'deve essere un oggetto');
    } else {
      final numero = foto['numero'];
      if (numero is! int || numero < 1 || numero > LimitiQuestionario.fotoMassime) {
        errore('foto.numero', 'da 1 a ${LimitiQuestionario.fotoMassime}');
      }
      final istruzioni = foto['istruzioni'];
      if (istruzioni != null &&
          (istruzioni is! String || istruzioni.length > LimitiQuestionario.istruzioniFoto)) {
        errore('foto.istruzioni', 'al massimo ${LimitiQuestionario.istruzioniFoto} caratteri');
      }
    }
  }
  return errori;
}

/// Problemi di un questionario come lo riceve l'app (§8.6): il contenuto più
/// `id` e `inviato_il`.
List<String> validaQuestionario(Object? questionario) {
  if (questionario is! Map<String, Object?>) return ['questionario: deve essere un oggetto'];
  return [
    if (!uuidValido(questionario['id'])) 'id: deve essere un UUID in minuscolo',
    if (analizzaDataOra(questionario['inviato_il']) == null)
      'inviato_il: deve essere una data e ora ISO 8601 con fuso orario',
    ...validaContenutoQuestionario(questionario),
  ];
}

/// Problemi delle risposte a [questionario] (§8.6), come le manda l'app:
/// `questionario_id`, `inviata_il`, `risposte` e gli id delle `foto`.
List<String> validaRisposta(Object? risposta, Map<String, Object?> questionario) {
  final errori = <String>[];
  void errore(String percorso, String messaggio) => errori.add('$percorso: $messaggio');
  if (risposta is! Map<String, Object?>) return ['risposta: deve essere un oggetto'];
  if (risposta['questionario_id'] != questionario['id']) errore('questionario_id', 'non corrisponde');
  if (analizzaDataOra(risposta['inviata_il']) == null) errore('inviata_il', 'data e ora non valida');

  final domande = {
    for (final d in (questionario['domande'] as List<Object?>?) ?? const [])
      if (d is Map<String, Object?>) d['id']: d,
  };
  final risposte = risposta['risposte'];
  final date = <Object?>{};
  if (risposte is! List<Object?>) {
    errore('risposte', 'deve essere una lista');
  } else {
    for (final (i, r) in risposte.indexed) {
      final p = 'risposte[$i]';
      if (r is! Map<String, Object?>) {
        errore(p, 'deve essere un oggetto');
        continue;
      }
      final domanda = domande[r['domanda_id']];
      if (domanda == null || !date.add(r['domanda_id'])) {
        errore('$p.domanda_id', 'domanda sconosciuta o ripetuta');
        continue;
      }
      final problema = _problemaValore(domanda, r['valore']);
      if (problema != null) errore('$p.valore', problema);
    }
  }
  for (final domanda in domande.values) {
    if (domanda['obbligatoria'] == true && !date.contains(domanda['id'])) {
      errore('risposte', 'manca la risposta obbligatoria a «${domanda['testo']}»');
    }
  }

  final richieste = switch (questionario['foto']) {
    {'numero': final int numero} => numero,
    _ => 0,
  };
  final foto = risposta['foto'];
  if (foto is! List<Object?> || foto.length != richieste || !foto.every(uuidValido) || foto.toSet().length != foto.length) {
    errore('foto', 'servono $richieste id di foto diversi');
  }
  return errori;
}

String? _problemaValore(Map<String, Object?> domanda, Object? valore) {
  String? testo(int massimo) =>
      valore is String && valore.trim().isNotEmpty && valore.length <= massimo
      ? null
      : 'testo da 1 a $massimo caratteri';
  final opzioni = {...?(domanda['opzioni'] as List<Object?>?)};
  final altro = domanda['altro'] == true;
  String? altroValido(Object? a) =>
      a is String && a.trim().isNotEmpty && a.length <= LimitiQuestionario.opzione
      ? null
      : '«altro» da 1 a ${LimitiQuestionario.opzione} caratteri';
  switch (domanda['tipo']) {
    case TipoDomanda.testoBreve:
      return testo(LimitiQuestionario.testoBreve);
    case TipoDomanda.testoLungo:
      return testo(LimitiQuestionario.testoLungo);
    case TipoDomanda.numero:
      return valore is num && valore.isFinite && valore.abs() <= LimitiQuestionario.numeroMassimo
          ? null
          : 'numero non valido';
    case TipoDomanda.scala:
      return valore is int && valore >= 1 && valore <= 10 ? null : 'intero da 1 a 10';
    case TipoDomanda.sceltaSingola:
      return switch (valore) {
        {'scelta': final Object? s} when valore.length == 1 => opzioni.contains(s) ? null : 'opzione sconosciuta',
        {'altro': final Object? a} when valore.length == 1 => altro ? altroValido(a) : '«altro» non ammesso',
        _ => 'serve {"scelta"} o {"altro"}',
      };
    case TipoDomanda.sceltaMultipla:
      if (valore is! Map<String, Object?>) return 'serve {"scelte", "altro"}';
      final scelte = valore['scelte'];
      if (scelte is! List<Object?> || !scelte.every(opzioni.contains) || scelte.toSet().length != scelte.length) {
        return 'scelte sconosciute o ripetute';
      }
      if (valore.containsKey('altro')) {
        if (!altro) return '«altro» non ammesso';
        final problema = altroValido(valore['altro']);
        if (problema != null) return problema;
      }
      if (scelte.isEmpty && !valore.containsKey('altro')) return 'nessuna scelta';
      return null;
  }
  return 'tipo di domanda sconosciuto';
}

/// Una foto è un JPEG: comincia con FF D8 FF.
bool sembraJpeg(List<int> byte) =>
    byte.length > 3 && byte[0] == 0xFF && byte[1] == 0xD8 && byte[2] == 0xFF;
