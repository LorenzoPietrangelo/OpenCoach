// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'testi.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class TestiIt extends Testi {
  TestiIt([String locale = 'it']) : super(locale);

  @override
  String get nomeApp => 'Open Coach';

  @override
  String get apriFinestra => 'Apri Open Coach';

  @override
  String get esci => 'Esci';

  @override
  String get annulla => 'Annulla';

  @override
  String get salva => 'Salva';

  @override
  String get chiudi => 'Chiudi';

  @override
  String get continua => 'Continua';

  @override
  String get modifica => 'Modifica';

  @override
  String get copia => 'Copia';

  @override
  String get elimina => 'Elimina';

  @override
  String get archivia => 'Archivia';

  @override
  String get riattiva => 'Riattiva';

  @override
  String get rinomina => 'Rinomina';

  @override
  String get nuovo => 'Nuovo';

  @override
  String get altreAzioni => 'Altre azioni';

  @override
  String get benvenutoTitolo => 'Benvenuto in Open Coach';

  @override
  String get benvenutoSpiegazione =>
      'Il programma fa da server per i tuoi atleti attraverso la rete Tor: niente account, niente servizi esterni. Gli atleti si collegano finché il programma è aperto su questo PC.';

  @override
  String get nomeCoach => 'Nome del coach';

  @override
  String get nomeCoachAiuto => 'Gli atleti lo vedono quando si collegano';

  @override
  String get avvioAutomatico => 'Avvia Open Coach con il computer';

  @override
  String get avvioAutomaticoAiuto =>
      'Il programma parte nell\'area di notifica, così gli atleti possono sincronizzare';

  @override
  String get inizia => 'Inizia';

  @override
  String get sezioneAtleti => 'Atleti';

  @override
  String get sezioneStato => 'Stato';

  @override
  String get sezioneImpostazioni => 'Impostazioni';

  @override
  String get avvisoBackup =>
      'Non c\'è un backup degli ultimi 30 giorni. Senza backup, se il PC si guasta tutti gli atleti dovranno riabbinarsi.';

  @override
  String get vaiAlBackup => 'Vai al backup';

  @override
  String get avvisoTorObsoleto =>
      'La versione di Tor inclusa è obsoleta: aggiorna Open Coach.';

  @override
  String get esciTitolo => 'Uscire da Open Coach?';

  @override
  String get esciTesto =>
      'Finché il programma è chiuso gli atleti non possono sincronizzare: i loro allenamenti restano sul telefono e le schede nuove non arrivano.';

  @override
  String get esciDaOpenCoach => 'Esci da Open Coach';

  @override
  String notificaLogRicevuto(String nome) {
    return '$nome ha registrato un allenamento';
  }

  @override
  String notificaAbbinato(String nome, String telefono) {
    return '$nome ha collegato $telefono';
  }

  @override
  String get notificaInvitoContestatoTitolo =>
      'Attenzione: invito usato due volte';

  @override
  String notificaInvitoContestato(String nome) {
    return 'Un secondo telefono ha provato a usare l\'invito di $nome. Il link può essere stato intercettato: controlla quale telefono è collegato.';
  }

  @override
  String statoAvvio(int percentuale) {
    return 'Avvio di Tor ($percentuale%)';
  }

  @override
  String get statoNessunaChiave => 'In attesa del primo invito';

  @override
  String get statoPubblicazione => 'Pubblicazione del servizio';

  @override
  String get statoRaggiungibile => 'Raggiungibile';

  @override
  String statoNonRaggiungibile(String motivo) {
    return 'Non raggiungibile: $motivo';
  }

  @override
  String get servizio => 'Servizio';

  @override
  String get spiegazioneRaggiungibile =>
      'I telefoni degli atleti possono collegarsi.';

  @override
  String get spiegazioneNessunaChiave =>
      'Il servizio si pubblica quando crei il primo invito: prima nessuno potrebbe raggiungerlo.';

  @override
  String get spiegazioneNonPronto =>
      'Gli atleti non possono ancora collegarsi. Gli allenamenti restano sui loro telefoni e partiranno appena il servizio sarà raggiungibile.';

  @override
  String get indirizzo => 'Indirizzo';

  @override
  String get indirizzoCopiato => 'Indirizzo copiato';

  @override
  String get indirizzoSpiegazione =>
      'Gli atleti lo ricevono nel QR dell\'invito: non serve comunicarlo.';

  @override
  String riepilogoAtleti(int atleti, int telefoni, int inviti) {
    return 'Atleti: $atleti · telefoni collegati: $telefoni · inviti aperti: $inviti';
  }

  @override
  String ultimoContattoDiTutti(String quando) {
    return 'Ultimo contatto di un telefono: $quando';
  }

  @override
  String get backup => 'Backup';

  @override
  String get backupMai => 'Nessun backup fatto finora';

  @override
  String backupUltimo(String quando) {
    return 'Ultimo backup: $quando';
  }

  @override
  String get atletiArchiviati => 'Atleti archiviati';

  @override
  String get mostraArchiviati => 'Mostra gli archiviati';

  @override
  String get mostraAttivi => 'Mostra gli attivi';

  @override
  String get nuovoAtleta => 'Nuovo atleta';

  @override
  String get nomeAtleta => 'Nome dell\'atleta';

  @override
  String get nessunAtleta => 'Nessun atleta. Crea il primo con «Nuovo».';

  @override
  String get nessunAtletaArchiviato => 'Nessun atleta archiviato.';

  @override
  String get scegliAtleta => 'Scegli un atleta, oppure creane uno nuovo.';

  @override
  String telefonoMaiSincronizzato(String telefono) {
    return '$telefono · non ha ancora sincronizzato';
  }

  @override
  String telefonoUltimoContatto(String telefono, String quando) {
    return '$telefono · $quando';
  }

  @override
  String get invitoInCorso => 'Invito in corso';

  @override
  String get nessunTelefono => 'Nessun telefono';

  @override
  String get atletaArchiviato => 'Archiviato';

  @override
  String get notePrivate => 'Note private';

  @override
  String get notePrivateAiuto => 'Restano su questo PC: l\'atleta non le vede';

  @override
  String get esportaJson => 'Esporta in JSON';

  @override
  String get esportaCsv => 'Esporta gli allenamenti in CSV';

  @override
  String esportato(String percorso) {
    return 'Salvato in $percorso';
  }

  @override
  String eliminaAtletaTitolo(String nome) {
    return 'Eliminare $nome?';
  }

  @override
  String get eliminaAtletaTesto =>
      'Il telefono viene scollegato e si cancellano schede e allenamenti dell\'atleta. Non si può annullare.';

  @override
  String get schedaTelefono => 'Telefono';

  @override
  String get schedaSchede => 'Schede';

  @override
  String get schedaAllenamenti => 'Allenamenti';

  @override
  String get telefono => 'Telefono collegato';

  @override
  String get nessunTelefonoSpiegazione =>
      'Nessun telefono collegato. Crea un invito e fallo scansionare dall\'app dell\'atleta.';

  @override
  String versioneApp(String versione) {
    return 'App $versione';
  }

  @override
  String abbinatoIl(String quando) {
    return 'Collegato il $quando';
  }

  @override
  String get maiSincronizzato => 'Non ha ancora sincronizzato';

  @override
  String ultimoContatto(String quando) {
    return 'Ultimo contatto: $quando';
  }

  @override
  String get revoca => 'Revoca';

  @override
  String revocaTitolo(String telefono) {
    return 'Scollegare $telefono?';
  }

  @override
  String revocaTesto(String nome) {
    return 'Il telefono di $nome non potrà più sincronizzare. Per ricollegarlo serve un nuovo invito.';
  }

  @override
  String get invito => 'Invito';

  @override
  String get nessunInvito => 'Nessun invito aperto.';

  @override
  String get invitoInAbbinamento =>
      'Il telefono sta completando l\'abbinamento.';

  @override
  String get invitoAperto => 'Invito aperto';

  @override
  String validoFinoAl(String quando) {
    return 'Valido fino al $quando';
  }

  @override
  String get annullaInvito => 'Annulla l\'invito';

  @override
  String get mostraQr => 'Mostra il QR';

  @override
  String get nuovoInvito => 'Nuovo invito';

  @override
  String get creaInvito => 'Crea l\'invito';

  @override
  String get sostituireTelefonoTitolo => 'Sostituire il telefono?';

  @override
  String get sostituireTelefonoTesto =>
      'Quando il nuovo telefono si collega, quello attuale viene scollegato. Gli allenamenti che il vecchio telefono non ha ancora inviato restano solo lì: fallo sincronizzare prima.';

  @override
  String get invitoTitolo => 'Invito per l\'app dell\'atleta';

  @override
  String get invitoSpiegazione =>
      'Fai scansionare questo codice dall\'app dell\'atleta. Se mandi il link con altri mezzi, trattalo come una password: vale una volta sola.';

  @override
  String get copiaLink => 'Copia il link';

  @override
  String get linkCopiato => 'Link copiato';

  @override
  String get nuovaScheda => 'Nuova scheda';

  @override
  String get nuovaSchedaTitolo => 'Nuova scheda';

  @override
  String get nessunaScheda => 'Nessuna scheda per questo atleta.';

  @override
  String get senzaTitolo => 'Senza titolo';

  @override
  String get duplica => 'Duplica…';

  @override
  String get duplicaPer => 'Duplica la scheda per';

  @override
  String stessoAtleta(String nome) {
    return '$nome (stesso atleta)';
  }

  @override
  String get schedaDuplicata => 'Scheda duplicata come bozza';

  @override
  String get riportaTraLeAttive => 'Riporta tra le attive';

  @override
  String get eliminaSchedaTitolo => 'Eliminare la scheda?';

  @override
  String get eliminaSchedaPubblicata =>
      'La scheda sparisce anche dal telefono dell\'atleta alla prossima sync. Gli allenamenti già registrati restano.';

  @override
  String get eliminaBozza =>
      'La bozza non è mai stata pubblicata: l\'atleta non l\'ha mai vista.';

  @override
  String get bozzaMaiPubblicata => 'Bozza, mai pubblicata';

  @override
  String get archiviata => 'Archiviata';

  @override
  String revisione(int numero) {
    return 'Revisione $numero';
  }

  @override
  String get inAttesaDiConsegna => 'in attesa di consegna';

  @override
  String ricevutaIl(String quando) {
    return 'ricevuta il $quando';
  }

  @override
  String get modificheNonPubblicate => 'modifiche non pubblicate';

  @override
  String get revisioniPubblicate => 'Revisioni pubblicate';

  @override
  String pubblicataIl(String quando) {
    return 'pubblicata il $quando';
  }

  @override
  String get sostituitaPrimaDiArrivare =>
      'sostituita prima di arrivare all\'atleta';

  @override
  String schedaDi(String nome) {
    return 'Scheda di $nome';
  }

  @override
  String get salvaBozza => 'Salva la bozza';

  @override
  String get pubblica => 'Pubblica';

  @override
  String pubblicataRevisione(int numero) {
    return 'Pubblicata la revisione $numero: l\'atleta la riceverà alla prossima sync';
  }

  @override
  String get schedaIncompleta => 'La scheda non si può ancora pubblicare';

  @override
  String get modificheNonSalvateTitolo => 'Uscire senza salvare?';

  @override
  String get modificheNonSalvateTesto =>
      'Le modifiche alla bozza andranno perse.';

  @override
  String get scarta => 'Esci senza salvare';

  @override
  String get titoloScheda => 'Titolo';

  @override
  String get noteScheda => 'Note per l\'atleta';

  @override
  String get validaDal => 'Valida dal';

  @override
  String get validaAl => 'Valida fino al';

  @override
  String get nessunaData => 'nessuna data';

  @override
  String get togliData => 'Togli la data';

  @override
  String get aggiungiSeduta => 'Aggiungi una seduta';

  @override
  String sedutaPredefinita(int numero) {
    return 'Giorno $numero';
  }

  @override
  String get nomeSeduta => 'Nome della seduta';

  @override
  String get noteSeduta => 'Note della seduta';

  @override
  String get togliSeduta => 'Togli la seduta';

  @override
  String get aggiungiEsercizio => 'Aggiungi un esercizio';

  @override
  String get nomeEsercizio => 'Esercizio';

  @override
  String get noteEsercizio => 'Note dell\'esercizio';

  @override
  String get togliEsercizio => 'Togli l\'esercizio';

  @override
  String get serie => 'Serie';

  @override
  String get ripetizioni => 'Ripetizioni';

  @override
  String get carico => 'Carico';

  @override
  String get recupero => 'Recupero';

  @override
  String get recuperoNonValido => 'es. 90 o 1:30';

  @override
  String get rir => 'RIR';

  @override
  String altreRighe(String elenco) {
    return 'Altre serie da una versione precedente: $elenco';
  }

  @override
  String get togliAltreRighe => 'Toglile';

  @override
  String get spostaSu => 'Sposta su';

  @override
  String get spostaGiu => 'Sposta giù';

  @override
  String get campoNome => 'nome';

  @override
  String get campoNote => 'note';

  @override
  String erroreSeduta(int numero) {
    return 'Seduta $numero';
  }

  @override
  String erroreEsercizio(int numero) {
    return 'esercizio $numero';
  }

  @override
  String erroreRiga(int numero) {
    return 'riga $numero';
  }

  @override
  String get erroreServeUnaSeduta => 'Serve almeno una seduta';

  @override
  String get nessunAllenamento => 'Nessun allenamento ricevuto finora.';

  @override
  String get allenamentoLibero => 'Allenamento libero';

  @override
  String get sedutaNonTrovata => 'Seduta di una scheda eliminata';

  @override
  String minuti(int minuti) {
    String _temp0 = intl.Intl.pluralLogic(
      minuti,
      locale: localeName,
      other: '$minuti minuti',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String rpeSeduta(String valore) {
    return 'RPE $valore';
  }

  @override
  String get suRevisioneSuperata => 'su una revisione superata';

  @override
  String get suRevisioneSuperataSpiegazione =>
      'L\'atleta seguiva una revisione della scheda non più attuale.';

  @override
  String prescritto(String righe) {
    return 'Prescritto: $righe';
  }

  @override
  String get esercizioAggiunto => 'Aggiunto dall\'atleta';

  @override
  String serieNumero(int numero) {
    return 'Serie $numero';
  }

  @override
  String ripetizioniEseguite(int numero) {
    String _temp0 = intl.Intl.pluralLogic(
      numero,
      locale: localeName,
      other: '$numero ripetizioni',
      one: '1 ripetizione',
    );
    return '$_temp0';
  }

  @override
  String get nonCompletata => 'non completata';

  @override
  String get coach => 'Coach';

  @override
  String get avvioENotifiche => 'Avvio e notifiche';

  @override
  String get impedisciSospensione => 'Impedisci la sospensione del PC';

  @override
  String get impedisciSospensioneAiuto =>
      'Con il PC sospeso gli atleti non possono sincronizzare';

  @override
  String get notificheDesktop => 'Notifiche sul desktop';

  @override
  String get notificheDesktopAiuto =>
      'Allenamenti ricevuti e telefoni collegati. Gli inviti usati due volte si segnalano sempre.';

  @override
  String backupConfigurato(String cartella, String frequenza) {
    return 'Backup automatici in $cartella, $frequenza';
  }

  @override
  String get backupNonConfigurato => 'Backup automatici non configurati';

  @override
  String get configuraBackup => 'Configura i backup';

  @override
  String get cambiaBackup => 'Cambia passphrase o cartella';

  @override
  String get backupOra => 'Fai un backup ora';

  @override
  String get salvaBackupIn => 'Salva un backup in un file…';

  @override
  String get ripristinaDaBackup => 'Ripristina da un backup…';

  @override
  String get backupSpiegazione =>
      'Il backup è cifrato con la passphrase e contiene l\'identità: ripristinato su un altro PC, gli atleti non devono riabbinarsi. Due PC con la stessa identità non devono mai essere accesi insieme.';

  @override
  String backupCreato(String percorso) {
    return 'Backup salvato in $percorso';
  }

  @override
  String get frequenzaBackup => 'Frequenza';

  @override
  String ogniGiorni(int giorni) {
    String _temp0 = intl.Intl.pluralLogic(
      giorni,
      locale: localeName,
      other: 'ogni $giorni giorni',
      one: 'ogni giorno',
    );
    return '$_temp0';
  }

  @override
  String get passphrase => 'Passphrase';

  @override
  String get ripetiPassphrase => 'Ripeti la passphrase';

  @override
  String get passphraseSpiegazione =>
      'Serve per ripristinare il backup: se la perdi, il backup non si apre più.';

  @override
  String get passphraseCorta => 'La passphrase deve avere almeno 8 caratteri';

  @override
  String get passphraseDiverse => 'Le due passphrase sono diverse';

  @override
  String get passphraseNuovoBackup => 'Passphrase per questo backup';

  @override
  String get passphraseDelBackup => 'Passphrase del backup';

  @override
  String get passphraseErrata =>
      'Passphrase sbagliata, oppure il file è danneggiato';

  @override
  String get scegliCartellaBackup => 'Scegli la cartella dei backup';

  @override
  String get scegliCartella => 'Scegli la cartella';

  @override
  String get nessunaCartella => 'Nessuna cartella scelta';

  @override
  String get ripristina => 'Ripristina';

  @override
  String get ripristinaTitolo => 'Ripristinare il backup?';

  @override
  String ripristinaTesto(String file) {
    return 'I dati attuali vengono sostituiti da quelli di $file. I telefoni si riallineano da soli alla prossima sync. Spegni il PC da cui viene il backup, se è un altro.';
  }

  @override
  String get tor => 'Tor';

  @override
  String get torIncluso => 'Si usa il Tor incluso nel programma.';

  @override
  String torEsterno(String percorso) {
    return 'Si usa un Tor esterno: $percorso';
  }

  @override
  String get scegliTorEsterno => 'Usa un tor esterno…';

  @override
  String get usaTorIncluso => 'Torna al Tor incluso';

  @override
  String get torEsternoImpostato => 'Vale dal prossimo avvio del programma';

  @override
  String get identita => 'Identità';

  @override
  String get reimpostaIdentita => 'Reimposta l\'identità';

  @override
  String get reimpostaIdentitaTitolo => 'Reimpostare l\'identità?';

  @override
  String get reimpostaIdentitaTesto =>
      'Serve solo se la chiave del coach è stata compromessa. L\'indirizzo cambia, tutti i telefoni vengono scollegati e ogni atleta dovrà ricollegarsi con un nuovo invito.';

  @override
  String get reimpostaIdentitaConfermaTitolo => 'Ne sei sicuro?';

  @override
  String get reimpostaIdentitaConfermaTesto => 'Non si può annullare.';

  @override
  String get identitaReimpostata =>
      'Identità reimpostata: crea nuovi inviti per gli atleti';

  @override
  String get giaAvviato =>
      'Open Coach risulta già aperto su questo PC, ma non risponde. Chiudilo dal Task Manager e riaprilo.';

  @override
  String get identitaIllegibile =>
      'La chiave del coach non si può leggere: il portachiavi del sistema potrebbe essere stato azzerato.';

  @override
  String get recuperoDaBackup =>
      'Puoi ripristinare un backup: l\'indirizzo resta lo stesso e gli atleti non devono riabbinarsi.';

  @override
  String get nessunFile => 'Nessun file scelto';

  @override
  String get scegliFile => 'Scegli il file';

  @override
  String get recuperoNuovaIdentita =>
      'Senza backup puoi creare una nuova identità: atleti, schede e allenamenti restano, ma ogni atleta dovrà ricollegarsi con un nuovo invito.';

  @override
  String get creaNuovaIdentita => 'Crea una nuova identità';

  @override
  String get chiudiProgramma => 'Chiudi il programma';
}
