import 'casuale.dart';
import 'chiavi.dart';
import 'invito.dart';
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

  Map<String, Object?> toJson() => {
    'epoca': epoca,
    'cursore': cursore,
    'log': log,
    'versione_app': versioneApp,
    'pesi': pesi,
    'pesi_condivisi': ?pesiCondivisi,
    'risposte': risposte,
  };
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
  });

  factory RispostaSync.fromJson(Object? json) {
    final m = _oggetto(json);
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
  };
}
