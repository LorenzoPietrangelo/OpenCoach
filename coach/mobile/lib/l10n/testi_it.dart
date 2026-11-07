// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'testi.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class TestiIt extends Testi {
  TestiIt([String locale = 'it']) : super(locale);

  @override
  String get nomeApp => 'OpenCoach Coach';

  @override
  String get annulla => 'Annulla';

  @override
  String get riprova => 'Riprova';

  @override
  String get sconosciuto => '—';

  @override
  String get bloccoMotivo => 'Sblocca per vedere i dati dei tuoi atleti';

  @override
  String get bloccoTitolo => 'App bloccata';

  @override
  String get bloccoSpiegazione => 'Qui ci sono i dati dei tuoi atleti.';

  @override
  String get bloccoSblocca => 'Sblocca';

  @override
  String get bloccoAssente =>
      'Il telefono non ha un blocco schermo: chi lo prende in mano vede i dati dei tuoi atleti. Impostalo nelle impostazioni del telefono.';

  @override
  String get collegaTitolo => 'Collega il telefono al PC';

  @override
  String get collegaSpiegazione =>
      'Sul PC apri Open Coach, vai in Impostazioni, Il mio telefono, e scegli «Collega il mio telefono». Poi inquadra il QR.';

  @override
  String get collegaAvviso =>
      'L\'app funziona mentre il PC è acceso con il programma aperto: i dati restano lì.';

  @override
  String get collegaInquadra => 'Inquadra il QR';

  @override
  String get scansioneTitolo => 'Inquadra il QR';

  @override
  String get scansioneAiuto => 'Inquadra il QR che vedi sul PC';

  @override
  String get scansioneAltroCodice =>
      'Questo non è il QR per collegare il telefono del coach.';

  @override
  String get scansioneSenzaFotocamera =>
      'La fotocamera non si apre. Controlla che l\'app abbia il permesso nelle impostazioni del telefono.';

  @override
  String get faseAvvioTor => 'Avvio di Tor…';

  @override
  String get faseRicercaPc => 'Cerco il tuo PC…';

  @override
  String get faseAttesaPc =>
      'Il PC non si trova ancora. Dopo aver creato il QR può volerci un paio di minuti: riprovo da solo…';

  @override
  String get faseCollegamento => 'Collegamento…';

  @override
  String confermaTitolo(String nome) {
    return 'Collegarti a $nome?';
  }

  @override
  String get confermaTesto =>
      'Questo telefono vedrà i dati di tutti i tuoi atleti e potrà scrivere loro. Se c\'era un altro telefono collegato, smette di funzionare.';

  @override
  String get confermaAzione => 'Collega';

  @override
  String get erroreCodice =>
      'Questo non è il QR per collegare il telefono del coach. Lo trovi nelle impostazioni del programma sul PC.';

  @override
  String get erroreAggiorna =>
      'Il programma sul PC e questa app hanno versioni diverse: aggiorna entrambi all\'ultima versione.';

  @override
  String get erroreQr => 'Questo QR non vale più. Creane uno nuovo sul PC.';

  @override
  String get erroreQrInUso =>
      'Questo QR è già stato usato da un altro telefono. Creane uno nuovo sul PC.';

  @override
  String get erroreTor =>
      'Tor non parte: controlla la connessione. Alcune reti lo bloccano, prova con un\'altra.';

  @override
  String get errorePc =>
      'Il PC non si trova. Deve essere acceso con il programma aperto.';

  @override
  String get erroreInatteso => 'Qualcosa è andato storto. Riprova.';

  @override
  String get atletiTitolo => 'I tuoi atleti';

  @override
  String get atletiVuoto =>
      'Non hai ancora atleti. Li crei dal programma sul PC.';

  @override
  String get atletiCaricamento => 'Cerco il tuo PC…';

  @override
  String get atletaSenzaTelefono => 'Telefono non collegato';

  @override
  String get atletaNessunMessaggio => 'Nessun messaggio';

  @override
  String anteprimaTu(String testo) {
    return 'Tu: $testo';
  }

  @override
  String get anteprimaVideo => 'Video';

  @override
  String risposteNuove(int numero) {
    String _temp0 = intl.Intl.pluralLogic(
      numero,
      locale: localeName,
      other: '$numero questionari da leggere',
      one: '1 questionario da leggere',
    );
    return '$_temp0';
  }

  @override
  String get problemaInCollegamento =>
      'Sto finendo di collegare il telefono: il PC può metterci qualche minuto.';

  @override
  String get problemaIrraggiungibile =>
      'Il PC non risponde. Deve essere acceso con il programma aperto. I messaggi che scrivi partono appena torna.';

  @override
  String get problemaTor =>
      'Tor non parte: controlla la connessione. I messaggi che scrivi partono appena torna.';

  @override
  String get problemaChiave =>
      'Il PC non accetta questo telefono. Se l\'hai scollegato dal PC, scollegalo anche qui e ricollegalo.';

  @override
  String get problemaVersione =>
      'Il programma sul PC e questa app hanno versioni diverse: aggiorna entrambi.';

  @override
  String get problemaOccupato => 'Il PC ha molto da fare: riprovo tra poco.';

  @override
  String get problemaInatteso =>
      'Il PC ha risposto in modo inatteso: riprovo tra poco.';

  @override
  String get problemaDati => 'Non riesco a leggere questi dati dal PC.';

  @override
  String get sezioneChat => 'Chat';

  @override
  String get sezioneAllenamenti => 'Allenamenti';

  @override
  String get sezionePeso => 'Peso';

  @override
  String get sezioneQuestionari => 'Questionari';

  @override
  String get sezioneScheda => 'Scheda';

  @override
  String get chatVuota => 'Nessun messaggio. Scrivi tu per primo.';

  @override
  String get chatScrivi => 'Scrivi un messaggio';

  @override
  String get chatInvia => 'Invia';

  @override
  String get chatPrecedenti => 'Messaggi precedenti';

  @override
  String get chatInAttesa => 'In attesa del PC';

  @override
  String get chatRifiutato => 'Il PC non l\'ha accettato. Tocca per toglierlo.';

  @override
  String chatVideo(int secondi) {
    return 'Video di $secondi s: si guarda dal programma sul PC';
  }

  @override
  String get chatVideoEliminato => 'Video eliminato dal PC';

  @override
  String chatRiferimento(String esercizio, int serie) {
    return '$esercizio, serie $serie';
  }

  @override
  String get allenamentiVuoto => 'Nessun allenamento ricevuto.';

  @override
  String get allenamentiAltri => 'Allenamenti precedenti';

  @override
  String allenamentoSerie(int fatte, int totali) {
    return '$fatte di $totali serie';
  }

  @override
  String allenamentoDurata(String minuti) {
    return '$minuti min';
  }

  @override
  String allenamentoSforzo(String valore) {
    return 'Sforzo $valore';
  }

  @override
  String serieNumero(int numero) {
    return 'Serie $numero';
  }

  @override
  String get serieNonFatta => 'non fatta';

  @override
  String get pesoVuoto => 'L\'atleta non condivide il peso con te.';

  @override
  String get pesoUltimo => 'Ultimo peso';

  @override
  String get pesoMedia => 'Media 7 giorni';

  @override
  String get pesoDifferenza => 'Rispetto ai 7 giorni prima';

  @override
  String pesoValore(String kg) {
    return '$kg kg';
  }

  @override
  String get questionariVuoto => 'Nessun questionario mandato.';

  @override
  String questionarioInAttesa(String quando) {
    return 'Mandato il $quando, senza risposta';
  }

  @override
  String get questionarioAnnullato => 'Annullato';

  @override
  String questionarioRisposto(String quando) {
    return 'Risposto il $quando';
  }

  @override
  String get questionarioNuovo => 'Nuovo';

  @override
  String get questionarioNessunaRisposta => 'Nessuna risposta';

  @override
  String get questionarioFoto => 'Foto';

  @override
  String get questionarioFotoErrore => 'Foto non disponibile';

  @override
  String get schedaNote => 'Le tue note';

  @override
  String get schedaNoteVuote => 'Nessuna nota. Le scrivi dal programma sul PC.';

  @override
  String get schedaTelefono => 'Telefono dell\'atleta';

  @override
  String schedaUltimoContatto(String quando) {
    return 'Ultimo contatto: $quando';
  }

  @override
  String get schedaMaiSincronizzato => 'Non ha ancora sincronizzato';

  @override
  String schedaAllenamenti(int numero) {
    return 'Allenamenti ricevuti: $numero';
  }

  @override
  String get schedaSchede => 'Schede';

  @override
  String get schedaNessuna => 'Nessuna scheda.';

  @override
  String get schedaAiuto => 'Le schede si scrivono dal programma sul PC.';

  @override
  String get schedaBozza => 'Bozza';

  @override
  String get schedaArchiviata => 'Archiviata';

  @override
  String schedaPubblicata(int revisione) {
    return 'Revisione $revisione';
  }

  @override
  String schedaRicevuta(int revisione, String quando) {
    return 'Revisione $revisione, ricevuta il $quando';
  }

  @override
  String schedaNonRicevuta(int revisione) {
    return 'Revisione $revisione, non ancora ricevuta';
  }

  @override
  String get impostazioniTitolo => 'Impostazioni';

  @override
  String get impostazioniPc => 'PC collegato';

  @override
  String impostazioniProgramma(String nome) {
    return 'Programma di $nome';
  }

  @override
  String get impostazioniControlli => 'Controlli con l\'app chiusa';

  @override
  String get impostazioniControlliAiuto =>
      'Senza un server non ci sono notifiche push: l\'app guarda se ci sono novità a intervalli. Android può rimandare i controlli.';

  @override
  String get controlliDisattivati => 'Disattivati';

  @override
  String controlliOgni(int minuti) {
    return 'Ogni $minuti minuti';
  }

  @override
  String get batteriaLimitata =>
      'La batteria dell\'app è «Limitata»: con l\'app chiusa i controlli non partono.';

  @override
  String get apriImpostazioniTelefono => 'Apri le impostazioni';

  @override
  String get impostazioniBlocco => 'Blocco dell\'app';

  @override
  String get impostazioniBloccoAttivo =>
      'L\'app chiede l\'impronta o il blocco schermo all\'apertura e dopo 5 minuti in background.';

  @override
  String get scollegaTitolo => 'Scollegare questo telefono?';

  @override
  String get scollegaTesto =>
      'L\'app dimentica il PC e i messaggi ancora in coda. Per ricollegarla servirà un nuovo QR.';

  @override
  String get scollegaAzione => 'Scollega questo telefono';

  @override
  String notificaMessaggi(int numero) {
    String _temp0 = intl.Intl.pluralLogic(
      numero,
      locale: localeName,
      other: '$numero messaggi nuovi',
      one: '1 messaggio nuovo',
    );
    return '$_temp0';
  }

  @override
  String notificaRisposte(int numero) {
    String _temp0 = intl.Intl.pluralLogic(
      numero,
      locale: localeName,
      other: '$numero questionari compilati',
      one: '1 questionario compilato',
    );
    return '$_temp0';
  }
}
