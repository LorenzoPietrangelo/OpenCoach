import 'casuale.dart';
import 'chiavi.dart';
import 'cibo.dart';
import 'invito.dart';
import 'validazione.dart';
import 'versione.dart';

// Corpi delle richieste e delle risposte dell'API (§6.3). Ogni `fromJson`
// lancia FormatException se il JSON non rispetta il protocollo.

Map<String, Object?> _oggetto(Object? json) {
  if (json is Map<String, Object?>) return json;
  throw const FormatException('Atteso un oggetto JSON');
}

T _campo<T>(Map<String, Object?> m, String chiave) {
  final valore = m[chiave];
  if (valore is T) return valore;
  throw FormatException('Campo "$chiave" mancante o non valido');
}

List<T> _lista<T>(Map<String, Object?> m, String chiave) {
  final valore = m[chiave];
  if (valore is List<Object?> && valore.every((e) => e is T)) {
    return List<T>.from(valore);
  }
  throw FormatException('Campo "$chiave" mancante o non valido');
}

String _testo(Map<String, Object?> m, String chiave, {required int massimo}) {
  final valore = _campo<String>(m, chiave).trim();
  if (valore.isEmpty || valore.length > massimo) {
    throw FormatException('Campo "$chiave" vuoto o troppo lungo');
  }
  return valore;
}

String _versione(Map<String, Object?> m, String chiave) {
  final valore = _campo<String>(m, chiave);
  if (!versioneValida(valore)) {
    throw FormatException('Campo "$chiave" non è una versione');
  }
  return valore;
}

String _chiave32(Map<String, Object?> m, String chiave) {
  final valore = _campo<String>(m, chiave).toLowerCase();
  if (decodificaChiave32(valore) == null) {
    throw FormatException('Campo "$chiave" non è una chiave di 32 byte');
  }
  return valore;
}

String _uuid(Map<String, Object?> m, String chiave) {
  final valore = _campo<String>(m, chiave);
  if (!uuidValido(valore)) throw FormatException('Campo "$chiave" non è un UUID');
  return valore;
}

/// Risposta di `GET /v1/info`.
class RispostaInfo {
  const RispostaInfo({
    required this.protocollo,
    required this.nomeCoach,
    required this.versioneProgramma,
    required this.versioneAppMinima,
  });

  factory RispostaInfo.fromJson(Object? json) {
    final m = _oggetto(json);
    return RispostaInfo(
      protocollo: _lista<int>(m, 'protocollo'),
      nomeCoach: _campo<String>(m, 'nome_coach'),
      versioneProgramma: _versione(m, 'versione_programma'),
      versioneAppMinima: _versione(m, 'versione_app_minima'),
    );
  }

  final List<int> protocollo;
  final String nomeCoach;
  final String versioneProgramma;
  final String versioneAppMinima;

  Map<String, Object?> toJson() => {
    'protocollo': protocollo,
    'nome_coach': nomeCoach,
    'versione_programma': versioneProgramma,
    'versione_app_minima': versioneAppMinima,
  };
}

/// Dati del telefono inviati durante l'abbinamento.
class DatiDispositivo {
  const DatiDispositivo({
    required this.nome,
    required this.piattaforma,
    required this.versioneApp,
  });

  factory DatiDispositivo.fromJson(Object? json) {
    final m = _oggetto(json);
    final piattaforma = _campo<String>(m, 'piattaforma');
    if (!piattaforme.contains(piattaforma)) {
      throw const FormatException('Piattaforma sconosciuta');
    }
    return DatiDispositivo(
      nome: _testo(m, 'nome', massimo: 100),
      piattaforma: piattaforma,
      versioneApp: _versione(m, 'versione_app'),
    );
  }

  static const piattaforme = {'android', 'ios'};

  final String nome;
  final String piattaforma;
  final String versioneApp;

  Map<String, Object?> toJson() => {
    'nome': nome,
    'piattaforma': piattaforma,
    'versione_app': versioneApp,
  };
}

/// Corpo di `POST /v1/abbinamento`.
class RichiestaAbbinamento {
  const RichiestaAbbinamento({
    required this.invitoId,
    required this.segreto,
    required this.chiaveDispositivo,
    required this.dispositivo,
  });

  factory RichiestaAbbinamento.fromJson(Object? json) {
    final m = _oggetto(json);
    final invitoId = _campo<String>(m, 'invito_id').toLowerCase();
    if (!idInvitoValido(invitoId)) {
      throw const FormatException('Campo "invito_id" non valido');
    }
    return RichiestaAbbinamento(
      invitoId: invitoId,
      segreto: _chiave32(m, 'segreto'),
      chiaveDispositivo: _chiave32(m, 'chiave_dispositivo'),
      dispositivo: DatiDispositivo.fromJson(m['dispositivo']),
    );
  }

  final String invitoId;
  final String segreto;

  /// Chiave pubblica X25519 del dispositivo, in base32.
  final String chiaveDispositivo;
  final DatiDispositivo dispositivo;

  Map<String, Object?> toJson() => {
    'invito_id': invitoId,
    'segreto': segreto,
    'chiave_dispositivo': chiaveDispositivo,
    'dispositivo': dispositivo.toJson(),
  };
}

/// Risposta di `POST /v1/abbinamento`.
class RispostaAbbinamento {
  const RispostaAbbinamento({
    required this.atletaId,
    required this.dispositivoId,
    required this.token,
    required this.nomeAtleta,
    required this.nomeCoach,
  });

  factory RispostaAbbinamento.fromJson(Object? json) {
    final m = _oggetto(json);
    return RispostaAbbinamento(
      atletaId: _uuid(m, 'atleta_id'),
      dispositivoId: _uuid(m, 'dispositivo_id'),
      token: _chiave32(m, 'token'),
      nomeAtleta: _campo<String>(m, 'nome_atleta'),
      nomeCoach: _campo<String>(m, 'nome_coach'),
    );
  }

  final String atletaId;
  final String dispositivoId;
  final String token;
  final String nomeAtleta;
  final String nomeCoach;

  Map<String, Object?> toJson() => {
    'atleta_id': atletaId,
    'dispositivo_id': dispositivoId,
    'token': token,
    'nome_atleta': nomeAtleta,
    'nome_coach': nomeCoach,
  };
}

/// Corpo di `POST /v1/sync`. I log restano JSON grezzo: il programma del
/// coach li valida uno per uno e rifiuta solo quelli non validi.
class RichiestaSync {
  const RichiestaSync({
    required this.epoca,
    required this.cursore,
    required this.log,
    required this.versioneApp,
    this.pesi = const [],
    this.pesiCondivisi,
    this.risposte = const [],
    this.messaggi = const [],
    this.giornate = const [],
    this.ciboCondiviso,
  });

  factory RichiestaSync.fromJson(Object? json) {
    final m = _oggetto(json);
    final epoca = _campo<String?>(m, 'epoca');
    final cursore = _campo<String?>(m, 'cursore');
    if ((epoca?.length ?? 0) > 100 || (cursore?.length ?? 0) > 1000) {
      throw const FormatException('Epoca o cursore troppo lunghi');
    }
    return RichiestaSync(
      epoca: epoca,
      cursore: cursore,
      log: _lista<Object?>(m, 'log'),
      versioneApp: _versione(m, 'versione_app'),
      pesi: m.containsKey('pesi') ? _lista<Object?>(m, 'pesi') : const [],
      pesiCondivisi: _campo<bool?>(m, 'pesi_condivisi'),
      risposte: m.containsKey('risposte') ? _lista<Object?>(m, 'risposte') : const [],
      messaggi: m.containsKey('messaggi') ? _lista<Object?>(m, 'messaggi') : const [],
      giornate: m.containsKey('giornate') ? _lista<Object?>(m, 'giornate') : const [],
      ciboCondiviso: _campo<bool?>(m, 'cibo_condiviso'),
    );
  }

  final String? epoca;
  final String? cursore;
  final List<Object?> log;
  final String versioneApp;

  /// Pesi da salvare (§8.5), validati uno per uno come i log.
  final List<Object?> pesi;

  /// Falso se l'atleta non condivide il peso con questo coach: il coach
  /// cancella quelli che ha. Null da un'app che non conosce i pesi.
  final bool? pesiCondivisi;

  /// Risposte ai questionari (§8.6), validate una per una.
  final List<Object?> risposte;

  /// Messaggi della chat scritti dall'atleta (§8.7).
  final List<Object?> messaggi;

  /// Giornate del diario del cibo (§8.8), validate una per una come i pesi.
  final List<Object?> giornate;

  /// Falso se l'atleta non condivide il cibo con questo coach: il coach
  /// cancella le giornate che ha. Null da un'app che non conosce il cibo.
  final bool? ciboCondiviso;

  Map<String, Object?> toJson() => {
    'epoca': epoca,
    'cursore': cursore,
    'log': log,
    'versione_app': versioneApp,
    'pesi': pesi,
    'pesi_condivisi': ?pesiCondivisi,
    'risposte': risposte,
    'messaggi': messaggi,
    'giornate': giornate,
    'cibo_condiviso': ?ciboCondiviso,
  };
}

/// `POST /v1/attendi` (§6.3): il coach risponde appena ha qualcosa di nuovo
/// per il cursore indicato, o dopo [attesaS] secondi. Con la chat aperta i
/// messaggi arrivano così subito, senza sync continue.
class RichiestaAttesa {
  const RichiestaAttesa({
    required this.epoca,
    required this.cursore,
    required this.attesaS,
  });

  factory RichiestaAttesa.fromJson(Object? json) {
    final m = _oggetto(json);
    final epoca = _campo<String?>(m, 'epoca');
    final cursore = _campo<String?>(m, 'cursore');
    if ((epoca?.length ?? 0) > 100 || (cursore?.length ?? 0) > 1000) {
      throw const FormatException('Epoca o cursore troppo lunghi');
    }
    final attesaS = _campo<int>(m, 'attesa_s');
    if (attesaS < 0) throw const FormatException('Attesa negativa');
    return RichiestaAttesa(epoca: epoca, cursore: cursore, attesaS: attesaS);
  }

  final String? epoca;
  final String? cursore;
  final int attesaS;

  Map<String, Object?> toJson() => {
    'epoca': epoca,
    'cursore': cursore,
    'attesa_s': attesaS,
  };
}

/// Vero se conviene sincronizzare; falso se l'attesa è finita senza novità.
class RispostaAttesa {
  const RispostaAttesa({required this.novita});

  factory RispostaAttesa.fromJson(Object? json) =>
      RispostaAttesa(novita: _campo<bool>(_oggetto(json), 'novita'));

  final bool novita;

  Map<String, Object?> toJson() => {'novita': novita};
}

/// Log salvato dal coach nella revisione indicata.
class LogConfermato {
  const LogConfermato(this.id, this.rev);

  factory LogConfermato.fromJson(Object? json) {
    final m = _oggetto(json);
    return LogConfermato(_campo<String>(m, 'id'), _campo<int>(m, 'rev'));
  }

  final String id;
  final int rev;

  Map<String, Object?> toJson() => {'id': id, 'rev': rev};
}

/// Log scartato dal coach, con il motivo (vedi `RifiutoLog`).
class LogRifiutato {
  const LogRifiutato(this.id, this.errore);

  factory LogRifiutato.fromJson(Object? json) {
    final m = _oggetto(json);
    return LogRifiutato(_campo<String>(m, 'id'), _campo<String>(m, 'errore'));
  }

  final String id;
  final String errore;

  Map<String, Object?> toJson() => {'id': id, 'errore': errore};
}

/// Risposta di `POST /v1/sync`.
class RispostaSync {
  const RispostaSync({
    required this.epoca,
    required this.completo,
    required this.logAccettati,
    required this.logRifiutati,
    required this.schede,
    required this.schedeEliminate,
    required this.log,
    required this.cursore,
    required this.altro,
    this.pesiAccettati,
    this.pesi = const [],
    this.risposteAccettate = const [],
    this.risposteRifiutate = const [],
    this.questionari = const [],
    this.questionariAnnullati = const [],
    this.messaggiAccettati,
    this.messaggiRifiutati = const [],
    this.messaggi = const [],
    this.giornateAccettate,
    this.giornate = const [],
    this.conObiettivoCibo = false,
    this.obiettivoCibo,
  });

  factory RispostaSync.fromJson(Object? json) {
    final m = _oggetto(json);
    final obiettivo = m['obiettivo_cibo'];
    if (obiettivo != null && validaObiettivoCibo(obiettivo).isNotEmpty) {
      throw const FormatException('Campo "obiettivo_cibo" non valido');
    }
    return RispostaSync(
      epoca: _campo<String>(m, 'epoca'),
      completo: _campo<bool>(m, 'completo'),
      logAccettati: _lista<Object?>(
        m,
        'log_accettati',
      ).map(LogConfermato.fromJson).toList(),
      logRifiutati: _lista<Object?>(
        m,
        'log_rifiutati',
      ).map(LogRifiutato.fromJson).toList(),
      schede: _lista<Map<String, Object?>>(m, 'schede'),
      schedeEliminate: _lista<String>(m, 'schede_eliminate'),
      log: _lista<Map<String, Object?>>(m, 'log'),
      cursore: _campo<String>(m, 'cursore'),
      altro: _campo<bool>(m, 'altro'),
      pesiAccettati: m.containsKey('pesi_accettati')
          ? _lista<Object?>(
              m,
              'pesi_accettati',
            ).map(LogConfermato.fromJson).toList()
          : null,
      pesi: m.containsKey('pesi')
          ? _lista<Object?>(m, 'pesi').map(LogConfermato.fromJson).toList()
          : const [],
      risposteAccettate: m.containsKey('risposte_accettate')
          ? _lista<String>(m, 'risposte_accettate')
          : const [],
      risposteRifiutate: m.containsKey('risposte_rifiutate')
          ? _lista<Object?>(m, 'risposte_rifiutate').map(LogRifiutato.fromJson).toList()
          : const [],
      questionari: m.containsKey('questionari')
          ? _lista<Map<String, Object?>>(m, 'questionari')
          : const [],
      questionariAnnullati: m.containsKey('questionari_annullati')
          ? _lista<String>(m, 'questionari_annullati')
          : const [],
      messaggiAccettati: m.containsKey('messaggi_accettati')
          ? _lista<String>(m, 'messaggi_accettati')
          : null,
      messaggiRifiutati: m.containsKey('messaggi_rifiutati')
          ? _lista<Object?>(m, 'messaggi_rifiutati').map(LogRifiutato.fromJson).toList()
          : const [],
      messaggi: m.containsKey('messaggi') ? _lista<Map<String, Object?>>(m, 'messaggi') : const [],
      giornateAccettate: m.containsKey('giornate_accettate')
          ? _lista<Object?>(m, 'giornate_accettate').map(LogConfermato.fromJson).toList()
          : null,
      giornate: m.containsKey('giornate')
          ? _lista<Object?>(m, 'giornate').map(LogConfermato.fromJson).toList()
          : const [],
      conObiettivoCibo: m.containsKey('obiettivo_cibo'),
      obiettivoCibo: obiettivo == null
          ? null
          : ObiettivoCibo.fromJson(obiettivo as Map<String, Object?>),
    );
  }

  final String epoca;
  final bool completo;
  final List<LogConfermato> logAccettati;
  final List<LogRifiutato> logRifiutati;
  final List<Map<String, Object?>> schede;
  final List<String> schedeEliminate;
  final List<Map<String, Object?>> log;
  final String cursore;
  final bool altro;

  /// Pesi salvati, con la `rev`. Null da un programma che non conosce i pesi:
  /// l'app smette di mandarglieli.
  final List<LogConfermato>? pesiAccettati;

  /// Solo nello stato completo: `id` e `rev` di tutti i pesi che il coach ha
  /// dell'atleta, per rimandare quelli che mancano (§7.3).
  final List<LogConfermato> pesi;

  /// Id dei questionari di cui il coach ha salvato le risposte.
  final List<String> risposteAccettate;

  /// Risposte scartate, con il motivo (vedi `RifiutoRisposta`).
  final List<LogRifiutato> risposteRifiutate;

  /// Questionari da compilare: nella risposta incrementale quelli nuovi,
  /// nella completa tutti quelli ancora senza risposta (§8.6).
  final List<Map<String, Object?>> questionari;

  /// Questionari annullati dal coach dopo l'invio.
  final List<String> questionariAnnullati;

  /// Id dei messaggi dell'atleta che il coach ha salvato. Null da un
  /// programma che non conosce la chat: l'app smette di mandarglieli.
  final List<String>? messaggiAccettati;

  /// Messaggi scartati, con il motivo (vedi `RifiutoMessaggio`).
  final List<LogRifiutato> messaggiRifiutati;

  /// Messaggi della chat: nella risposta incrementale quelli nuovi del coach,
  /// nella completa tutti, anche quelli dell'atleta (§8.7).
  final List<Map<String, Object?>> messaggi;

  /// Giornate del cibo salvate, con la `rev`. Null da un programma che non
  /// conosce il cibo: l'app smette di mandargliele.
  final List<LogConfermato>? giornateAccettate;

  /// Solo nello stato completo: `id` e `rev` di tutte le giornate che il
  /// coach ha dell'atleta (§7.3).
  final List<LogConfermato> giornate;

  /// Vero se la risposta contiene `obiettivo_cibo`: nella completa c'è
  /// sempre, nell'incrementale solo se è cambiato. Senza il campo l'app tiene
  /// l'obiettivo che ha.
  final bool conObiettivoCibo;

  /// L'obiettivo del coach; null, con [conObiettivoCibo], se l'ha tolto.
  final ObiettivoCibo? obiettivoCibo;

  Map<String, Object?> toJson() => {
    'epoca': epoca,
    'completo': completo,
    'log_accettati': [for (final l in logAccettati) l.toJson()],
    'log_rifiutati': [for (final l in logRifiutati) l.toJson()],
    'schede': schede,
    'schede_eliminate': schedeEliminate,
    'log': log,
    'cursore': cursore,
    'altro': altro,
    if (pesiAccettati case final accettati?)
      'pesi_accettati': [for (final p in accettati) p.toJson()],
    'pesi': [for (final p in pesi) p.toJson()],
    'risposte_accettate': risposteAccettate,
    'risposte_rifiutate': [for (final r in risposteRifiutate) r.toJson()],
    'questionari': questionari,
    'questionari_annullati': questionariAnnullati,
    'messaggi_accettati': ?messaggiAccettati,
    'messaggi_rifiutati': [for (final r in messaggiRifiutati) r.toJson()],
    'messaggi': messaggi,
    if (giornateAccettate case final accettate?)
      'giornate_accettate': [for (final g in accettate) g.toJson()],
    'giornate': [for (final g in giornate) g.toJson()],
    if (conObiettivoCibo) 'obiettivo_cibo': obiettivoCibo?.toJson(),
  };
}
