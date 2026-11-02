/// Codici d'errore delle risposte HTTP (§6.4).
abstract final class CodiceErrore {
  static const richiestaNonValida = 'richiesta_non_valida';
  static const nonTrovato = 'non_trovato';
  static const metodoNonAmmesso = 'metodo_non_ammesso';
  static const tokenRevocato = 'token_revocato';
  static const origineVietata = 'origine_vietata';
  static const hostErrato = 'host_errato';
  static const invitoNonValido = 'invito_non_valido';
  static const invitoInUso = 'invito_in_uso';
  static const troppoGrande = 'troppo_grande';
  static const aggiornaApp = 'aggiorna_app';
  static const troppeRichieste = 'troppe_richieste';
  static const occupato = 'occupato';
  static const erroreInterno = 'errore_interno';
}

/// Motivi di rifiuto di un singolo log in `log_rifiutati` (§6.3).
abstract final class RifiutoLog {
  static const nonValido = 'non_valido';
  static const troppoGrande = 'troppo_grande';
  static const altroAtleta = 'altro_atleta';
}

/// Motivi di rifiuto delle risposte a un questionario in
/// `risposte_rifiutate` (§6.3, §8.6).
abstract final class RifiutoRisposta {
  /// Il coach non ha (più) questo questionario per l'atleta.
  static const sconosciuto = 'sconosciuto';
  static const nonValida = 'non_valida';

  /// Manca almeno una foto: l'app la ricarica e ritenta.
  static const fotoMancanti = 'foto_mancanti';
}

/// Motivi di rifiuto di un messaggio in `messaggi_rifiutati` (§8.7).
abstract final class RifiutoMessaggio {
  static const nonValido = 'non_valido';
  static const altroAtleta = 'altro_atleta';

  /// Il coach non ha tutte le parti del video, o non corrispondono
  /// all'impronta: l'app le ricarica e ritenta.
  static const videoMancante = 'video_mancante';
}
