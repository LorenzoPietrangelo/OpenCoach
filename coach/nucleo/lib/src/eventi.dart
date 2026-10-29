/// Avvenimenti che l'interfaccia del coach mostra o usa per aggiornarsi.
sealed class EventoCoach {
  const EventoCoach(this.atletaId);

  final String atletaId;
}

/// Un telefono si è abbinato all'atleta (§5.3, punto 5).
class DispositivoAbbinato extends EventoCoach {
  const DispositivoAbbinato(super.atletaId, this.dispositivoId, this.nomeDispositivo);

  final String dispositivoId;
  final String nomeDispositivo;
}

/// Il telefono ha confermato l'abbinamento con la propria chiave (§5.3, punto 7).
class AbbinamentoConfermato extends EventoCoach {
  const AbbinamentoConfermato(super.atletaId, this.dispositivoId);

  final String dispositivoId;
}

/// Un secondo telefono ha provato a usare un invito già in uso: il link può
/// essere stato intercettato (§5.4).
class InvitoContestato extends EventoCoach {
  const InvitoContestato(super.atletaId, this.invitoId);

  final String invitoId;
}

/// È arrivato un log nuovo o modificato.
class LogRicevuto extends EventoCoach {
  const LogRicevuto(super.atletaId, this.logId, {required this.eliminato});

  final String logId;
  final bool eliminato;
}

/// L'atleta ha ricevuto una revisione di una scheda.
class RevisioneRicevuta extends EventoCoach {
  const RevisioneRicevuta(super.atletaId, this.schedaId, this.revisione);

  final String schedaId;
  final int revisione;
}

/// Un dispositivo ha completato una richiesta di sync.
class DispositivoSincronizzato extends EventoCoach {
  const DispositivoSincronizzato(super.atletaId, this.dispositivoId);

  final String dispositivoId;
}

/// L'atleta ha risposto a un questionario.
class QuestionarioRisposto extends EventoCoach {
  const QuestionarioRisposto(super.atletaId, this.questionarioId, this.titolo);

  final String questionarioId;
  final String titolo;
}
