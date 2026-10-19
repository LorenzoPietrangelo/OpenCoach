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
