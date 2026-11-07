/// Avvenimenti che l'interfaccia del coach mostra o usa per aggiornarsi.
sealed class EventoCoach {
  const EventoCoach(this.atletaId);

  /// Vuoto negli avvenimenti del telefono del coach, che non riguardano un
  /// atleta solo.
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

/// È arrivato un messaggio dell'atleta nella chat.
class MessaggioRicevuto extends EventoCoach {
  const MessaggioRicevuto(super.atletaId, this.messaggioId, {required this.conVideo});

  final String messaggioId;
  final bool conVideo;
}

/// Un telefono si è collegato come telefono del coach (§16.2): vede i dati di
/// tutti gli atleti, quindi il coach lo sa sempre.
class TelefonoCoachCollegato extends EventoCoach {
  const TelefonoCoachCollegato(this.nomeTelefono) : super('');

  final String nomeTelefono;
}

/// Il telefono del coach ha confermato il collegamento con la propria chiave.
class TelefonoCoachConfermato extends EventoCoach {
  const TelefonoCoachConfermato() : super('');
}

/// Un secondo telefono ha provato a usare un QR già in uso (§16.2).
class TelefonoCoachContestato extends EventoCoach {
  const TelefonoCoachContestato() : super('');
}

/// Il coach ha cambiato qualcosa dal telefono (§16.3), per esempio scritto un
/// messaggio: l'interfaccia sul PC si aggiorna.
class ModificaDalTelefonoCoach extends EventoCoach {
  const ModificaDalTelefonoCoach(super.atletaId);
}
