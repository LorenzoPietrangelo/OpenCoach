import 'dart:convert';

import 'casuale.dart';
import 'date.dart';

/// Dimensione in byte della codifica JSON UTF-8 di [valore].
int dimensioneJson(Object? valore) => utf8.encode(jsonEncode(valore)).length;

/// Lunghezza massima del link al video di un esercizio (§8.1).
const linkVideoMassimo = 500;

/// Il link al video di un esercizio se [testo] è un indirizzo https con un
/// host e senza credenziali, altrimenti null (§8.1).
Uri? analizzaLinkVideo(String testo) {
  if (testo.length > linkVideoMassimo) return null;
  final uri = Uri.tryParse(testo);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  if (uri.userInfo.isNotEmpty) return null;
  return uri;
}

/// Peso corporeo minimo e massimo accettato, in kg (§8.5).
const pesoMinimoKg = 20;
const pesoMassimoKg = 400;

/// Problemi di un peso inviato dall'app (§8.5). Lista vuota se è valido.
List<String> validaPeso(Object? peso) {
  final v = _Verifica();
  final m = v.oggetto(peso, 'peso');
  if (m == null) return v.errori;
  v.uuid(m, 'id', '', obbligatorio: true);
  v.intero(m, 'rev', '', obbligatorio: true, minimo: 1, massimo: 0x7fffffff);
  v.booleano(m, 'eliminato', '', obbligatorio: true);
  if (m['eliminato'] == true) return v.errori;
  v.data(m, 'giorno', '', obbligatorio: true);
  v.numero(m, 'kg', '', obbligatorio: true, minimo: pesoMinimoKg, massimo: pesoMassimoKg);
  v.dataOra(m, 'modificato_il', '');
  return v.errori;
}

/// Problemi di un log inviato dall'app (§8.2). Lista vuota se è valido.
List<String> validaLog(Object? log) {
  final v = _Verifica();
  final m = v.oggetto(log, 'log');
  if (m == null) return v.errori;
  v.uuid(m, 'id', '', obbligatorio: true);
  v.intero(m, 'rev', '', obbligatorio: true, minimo: 1, massimo: 0x7fffffff);
  v.booleano(m, 'eliminato', '', obbligatorio: true);
  if (m['eliminato'] == true) return v.errori;

  v.uuid(m, 'scheda_id', '');
  v.intero(m, 'scheda_revisione', '', minimo: 1, massimo: 0x7fffffff);
  v.uuid(m, 'seduta_id', '');
  v.dataOra(m, 'eseguito_il', '', obbligatorio: true);
  v.intero(m, 'durata_min', '', minimo: 0, massimo: 1440);
  v.numero(m, 'rpe', '', minimo: 1, massimo: 10);
  v.testo(m, 'note', '', massimo: 10000);
  v.dataOra(m, 'modificato_il', '');

  final esercizi = v.lista(m, 'esercizi', '', obbligatoria: true, massimo: 200);
  for (final (i, elemento) in (esercizi ?? const <Object?>[]).indexed) {
    final pe = 'esercizi[$i]';
    final esercizio = v.oggetto(elemento, pe);
    if (esercizio == null) continue;
    v.uuid(esercizio, 'esercizio_id', pe);
    v.testo(esercizio, 'nome', pe, obbligatorio: true, nonVuoto: true, massimo: 200);
    v.testo(esercizio, 'note', pe, massimo: 2000);
    final serie = v.lista(esercizio, 'serie', pe, obbligatoria: true, massimo: 100);
    for (final (j, elementoSerie) in (serie ?? const <Object?>[]).indexed) {
      final ps = '$pe.serie[$j]';
      final riga = v.oggetto(elementoSerie, ps);
      if (riga == null) continue;
      v.booleano(riga, 'completata', ps, obbligatorio: true);
      v.intero(riga, 'ripetizioni', ps, minimo: 0, massimo: 10000);
      v.numero(riga, 'carico_kg', ps, minimo: 0, massimo: 10000);
      v.intero(riga, 'durata_s', ps, minimo: 0, massimo: 86400);
      v.numero(riga, 'rpe', ps, minimo: 0, massimo: 10, passo: 0.5);
    }
  }
  return v.errori;
}

/// Problemi del contenuto di una scheda scritta dal coach, prima della
/// pubblicazione: titolo, note, date e sedute (§8.1).
List<String> validaContenutoScheda(Object? contenuto) {
  final v = _Verifica();
  final m = v.oggetto(contenuto, 'scheda');
  if (m != null) _contenutoScheda(v, m);
  return v.errori;
}

/// Problemi di una scheda come la invia il programma del coach (§8.1).
List<String> validaScheda(Object? scheda) {
  final v = _Verifica();
  final m = v.oggetto(scheda, 'scheda');
  if (m == null) return v.errori;
  v.uuid(m, 'id', '', obbligatorio: true);
  v.intero(m, 'revisione', '', obbligatorio: true, minimo: 1, massimo: 0x7fffffff);
  v.scelta(m, 'stato', '', const {'pubblicata', 'archiviata'}, obbligatorio: true);
  v.dataOra(m, 'pubblicata_il', '', obbligatorio: true);
  _contenutoScheda(v, m);
  return v.errori;
}

void _contenutoScheda(_Verifica v, Map<String, Object?> m) {
  v.testo(m, 'titolo', '', obbligatorio: true, nonVuoto: true, massimo: 200);
  v.testo(m, 'note', '', massimo: 10000);
  final dal = v.data(m, 'valida_dal', '');
  final al = v.data(m, 'valida_al', '');
  if (dal != null && al != null && al.isBefore(dal)) {
    v.errore('valida_al', 'non può precedere valida_dal');
  }

  final id = <String>{};
  void unico(Object? valore, String percorso) {
    if (valore is String && !id.add(valore)) v.errore(percorso, 'id ripetuto');
  }

  final sedute = v.lista(m, 'sedute', '', obbligatoria: true, minimo: 1, massimo: 100);
  for (final (i, elemento) in (sedute ?? const <Object?>[]).indexed) {
    final ps = 'sedute[$i]';
    final seduta = v.oggetto(elemento, ps);
    if (seduta == null) continue;
    v.uuid(seduta, 'id', ps, obbligatorio: true);
    unico(seduta['id'], '$ps.id');
    v.testo(seduta, 'nome', ps, obbligatorio: true, nonVuoto: true, massimo: 200);
    v.testo(seduta, 'note', ps, massimo: 10000);
    final esercizi = v.lista(seduta, 'esercizi', ps, obbligatoria: true, massimo: 100);
    for (final (j, elementoEsercizio) in (esercizi ?? const <Object?>[]).indexed) {
      final pe = '$ps.esercizi[$j]';
      final esercizio = v.oggetto(elementoEsercizio, pe);
      if (esercizio == null) continue;
      v.uuid(esercizio, 'id', pe, obbligatorio: true);
      unico(esercizio['id'], '$pe.id');
      v.testo(esercizio, 'nome', pe, obbligatorio: true, nonVuoto: true, massimo: 200);
      v.testo(esercizio, 'note', pe, massimo: 5000);
      v.linkVideo(esercizio, 'video', pe);
      final prescrizione = v.lista(esercizio, 'prescrizione', pe, massimo: 50);
      for (final (k, elementoRiga) in (prescrizione ?? const <Object?>[]).indexed) {
        final pr = '$pe.prescrizione[$k]';
        final riga = v.oggetto(elementoRiga, pr);
        if (riga == null) continue;
        v.intero(riga, 'serie', pr, minimo: 1, massimo: 100);
        v.testo(riga, 'ripetizioni', pr, massimo: 50);
        v.testo(riga, 'carico', pr, massimo: 50);
        v.intero(riga, 'recupero_s', pr, minimo: 0, massimo: 3600);
        v.testo(riga, 'rir', pr, massimo: 20);
      }
    }
  }
}

/// Raccoglie gli errori di validazione, ciascuno con il percorso del campo.
class _Verifica {
  final errori = <String>[];

  void errore(String percorso, String messaggio) =>
      errori.add('$percorso: $messaggio');

  String _nome(String percorso, String chiave) =>
      percorso.isEmpty ? chiave : '$percorso.$chiave';

  Map<String, Object?>? oggetto(Object? valore, String percorso) {
    if (valore is Map<String, Object?>) return valore;
    errore(percorso, 'deve essere un oggetto');
    return null;
  }

  Object? _valore(
    Map<String, Object?> m,
    String chiave,
    String percorso,
    bool obbligatorio,
  ) {
    final valore = m[chiave];
    if (valore == null && obbligatorio) {
      errore(_nome(percorso, chiave), 'obbligatorio');
    }
    return valore;
  }

  List<Object?>? lista(
    Map<String, Object?> m,
    String chiave,
    String percorso, {
    required int massimo,
    int minimo = 0,
    bool obbligatoria = false,
  }) {
    final valore = _valore(m, chiave, percorso, obbligatoria);
    if (valore == null) return null;
    final nome = _nome(percorso, chiave);
    if (valore is! List<Object?>) {
      errore(nome, 'deve essere una lista');
      return null;
    }
    if (valore.length > massimo) {
      errore(nome, 'al massimo $massimo elementi');
      return null;
    }
    if (valore.length < minimo) errore(nome, 'servono almeno $minimo elementi');
    return valore;
  }

  void testo(
    Map<String, Object?> m,
    String chiave,
    String percorso, {
    required int massimo,
    bool obbligatorio = false,
    bool nonVuoto = false,
  }) {
    final valore = _valore(m, chiave, percorso, obbligatorio);
    if (valore == null) return;
    final nome = _nome(percorso, chiave);
    if (valore is! String) {
      errore(nome, 'deve essere un testo');
    } else if (nonVuoto && valore.trim().isEmpty) {
      errore(nome, 'non può essere vuoto');
    } else if (valore.length > massimo) {
      errore(nome, 'al massimo $massimo caratteri');
    }
  }

  void intero(
    Map<String, Object?> m,
    String chiave,
    String percorso, {
    required int minimo,
    required int massimo,
    bool obbligatorio = false,
  }) {
    final valore = _valore(m, chiave, percorso, obbligatorio);
    if (valore == null) return;
    final nome = _nome(percorso, chiave);
    if (valore is! int) {
      errore(nome, 'deve essere un numero intero');
    } else if (valore < minimo || valore > massimo) {
      errore(nome, 'deve essere tra $minimo e $massimo');
    }
  }

  void numero(
    Map<String, Object?> m,
    String chiave,
    String percorso, {
    required num minimo,
    required num massimo,
    num? passo,
    bool obbligatorio = false,
  }) {
    final valore = _valore(m, chiave, percorso, obbligatorio);
    if (valore == null) return;
    final nome = _nome(percorso, chiave);
    if (valore is! num) {
      errore(nome, 'deve essere un numero');
    } else if (valore < minimo || valore > massimo) {
      errore(nome, 'deve essere tra $minimo e $massimo');
    } else if (passo != null && (valore / passo) % 1 != 0) {
      errore(nome, 'deve essere un multiplo di $passo');
    }
  }

  void booleano(
    Map<String, Object?> m,
    String chiave,
    String percorso, {
    bool obbligatorio = false,
  }) {
    final valore = _valore(m, chiave, percorso, obbligatorio);
    if (valore != null && valore is! bool) {
      errore(_nome(percorso, chiave), 'deve essere true o false');
    }
  }

  void scelta(
    Map<String, Object?> m,
    String chiave,
    String percorso,
    Set<String> valori, {
    bool obbligatorio = false,
  }) {
    final valore = _valore(m, chiave, percorso, obbligatorio);
    if (valore != null && !valori.contains(valore)) {
      errore(_nome(percorso, chiave), 'deve essere uno tra ${valori.join(', ')}');
    }
  }

  void uuid(
    Map<String, Object?> m,
    String chiave,
    String percorso, {
    bool obbligatorio = false,
  }) {
    final valore = _valore(m, chiave, percorso, obbligatorio);
    if (valore != null && !uuidValido(valore)) {
      errore(_nome(percorso, chiave), 'deve essere un UUID in minuscolo');
    }
  }

  void linkVideo(Map<String, Object?> m, String chiave, String percorso) {
    final valore = _valore(m, chiave, percorso, false);
    if (valore == null) return;
    if (valore is! String || analizzaLinkVideo(valore) == null) {
      errore(
        _nome(percorso, chiave),
        'deve essere un link https di al massimo $linkVideoMassimo caratteri',
      );
    }
  }

  void dataOra(
    Map<String, Object?> m,
    String chiave,
    String percorso, {
    bool obbligatorio = false,
  }) {
    final valore = _valore(m, chiave, percorso, obbligatorio);
    if (valore != null && analizzaDataOra(valore) == null) {
      errore(
        _nome(percorso, chiave),
        'deve essere una data e ora ISO 8601 con fuso orario',
      );
    }
  }

  DateTime? data(
    Map<String, Object?> m,
    String chiave,
    String percorso, {
    bool obbligatorio = false,
  }) {
    final valore = _valore(m, chiave, percorso, obbligatorio);
    if (valore == null) return null;
    final giorno = analizzaData(valore);
    if (giorno == null) {
      errore(_nome(percorso, chiave), 'deve essere una data AAAA-MM-GG');
    }
    return giorno;
  }
}
