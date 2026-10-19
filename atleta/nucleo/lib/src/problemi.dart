// Messaggi per l'atleta (§5.4, §7.5). L'interfaccia può sostituirli con le
// proprie risorse tradotte, partendo dal nome del valore.

/// Perché l'ultima sync con un coach non è riuscita (§7.5).
enum ProblemaSync {
  /// Il sistema operativo non vede reti.
  offline('Sei offline. Gli allenamenti restano salvati sul telefono.'),

  /// Il bootstrap di Tor non si è completato in 60 s.
  torNonParte(
    'Non riesco a collegarmi alla rete Tor da questa connessione. '
    "Prova con un'altra rete, per esempio i dati mobili.",
  ),

  /// Errori SOCKS F0, F2, F3, F7 o timeout: di solito il PC del coach è
  /// spento o il programma è chiuso. Anche F4 e F5, finché non si ripetono
  /// per 3 sync consecutive.
  coachIrraggiungibile(
    'Il PC del coach non è raggiungibile. '
    'I tuoi allenamenti partiranno appena tornerà acceso.',
  ),

  /// Il programma del coach ha risposto 429, 503 o 5xx anche dopo i
  /// ritentativi.
  coachOccupato(
    'Il programma del coach non riesce a rispondere. Riprovo più tardi.',
  ),

  /// Errori SOCKS F4 o F5 in 3 sync consecutive, oppure chiave e token
  /// assenti dal telefono, per esempio dopo un ripristino su un altro
  /// telefono (§4).
  chiaveNonAccettata(
    'Il collegamento con il coach non è più valido. Chiedi un nuovo invito.',
  ),

  /// HTTP 401: il coach ha revocato il dispositivo.
  revocato('Il coach ha chiuso il collegamento.'),

  /// L'atleta si è scollegato da questo coach.
  scollegato('Non sei più collegato a questo coach.'),

  /// HTTP 426: l'app è sotto la versione minima del programma del coach.
  aggiornaApp("Aggiorna l'app per continuare a sincronizzare."),

  /// Risposta non conforme al protocollo o errore di programmazione (400,
  /// 403, 404, 405, 421): non si ritenta in automatico (§6.4).
  erroreImprevisto('Errore imprevisto nella sincronizzazione con il coach.');

  const ProblemaSync(this.messaggio);

  final String messaggio;

  /// Vero se in primo piano conviene ritentare a breve (§7.4).
  bool get temporaneo => this == coachIrraggiungibile || this == coachOccupato;
}

/// Perché l'abbinamento non è riuscito (§5.4).
enum ProblemaAbbinamento {
  /// Il testo non è un invito di Open Coach.
  codiceNonValido('Questo codice non è un invito di Open Coach.'),

  /// L'invito usa una versione del formato che l'app non conosce (§5.2).
  versioneInvito(
    "Questo invito richiede una versione più recente dell'app. "
    'Aggiornala e riprova.',
  ),

  /// HTTP 410, oppure la chiave d'invito non è più autorizzata: invito
  /// scaduto, usato o annullato.
  invitoNonValido('Invito non più valido. Chiedi al coach un nuovo QR.'),

  /// HTTP 409: l'invito è in uso con un'altra chiave di dispositivo. Il
  /// link può essere stato intercettato, e il coach ne è avvisato.
  invitoInUso(
    'Questo invito è già stato usato da un altro telefono. '
    'Chiedi al coach un nuovo QR.',
  ),

  coachIrraggiungibile(
    'Il PC del coach non è raggiungibile. '
    'Deve essere acceso con il programma aperto.',
  ),

  /// HTTP 429, 503 o 5xx.
  coachOccupato(
    'Il programma del coach non riesce a rispondere. Riprova tra un minuto.',
  ),

  offline('Sei offline. Collegati a una rete e riprova.'),

  torNonParte(
    'Non riesco a collegarmi alla rete Tor da questa connessione. '
    "Prova con un'altra rete, per esempio i dati mobili.",
  ),

  /// HTTP 426, oppure il coach non parla una versione del protocollo nota
  /// all'app.
  aggiornaApp("Aggiorna l'app per collegarti a questo coach."),

  erroreImprevisto("Errore imprevisto durante l'abbinamento.");

  const ProblemaAbbinamento(this.messaggio);

  final String messaggio;
}
