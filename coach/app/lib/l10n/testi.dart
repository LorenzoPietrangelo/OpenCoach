import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'testi_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of Testi
/// returned by `Testi.of(context)`.
///
/// Applications need to include `Testi.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/testi.dart';
///
/// return MaterialApp(
///   localizationsDelegates: Testi.localizationsDelegates,
///   supportedLocales: Testi.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the Testi.supportedLocales
/// property.
abstract class Testi {
  Testi(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static Testi of(BuildContext context) {
    return Localizations.of<Testi>(context, Testi)!;
  }

  static const LocalizationsDelegate<Testi> delegate = _TestiDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('it')];

  /// No description provided for @nomeApp.
  ///
  /// In it, this message translates to:
  /// **'Open Coach'**
  String get nomeApp;

  /// No description provided for @apriFinestra.
  ///
  /// In it, this message translates to:
  /// **'Apri Open Coach'**
  String get apriFinestra;

  /// No description provided for @esci.
  ///
  /// In it, this message translates to:
  /// **'Esci'**
  String get esci;

  /// No description provided for @annulla.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get annulla;

  /// No description provided for @salva.
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get salva;

  /// No description provided for @chiudi.
  ///
  /// In it, this message translates to:
  /// **'Chiudi'**
  String get chiudi;

  /// No description provided for @continua.
  ///
  /// In it, this message translates to:
  /// **'Continua'**
  String get continua;

  /// No description provided for @modifica.
  ///
  /// In it, this message translates to:
  /// **'Modifica'**
  String get modifica;

  /// No description provided for @copia.
  ///
  /// In it, this message translates to:
  /// **'Copia'**
  String get copia;

  /// No description provided for @elimina.
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get elimina;

  /// No description provided for @archivia.
  ///
  /// In it, this message translates to:
  /// **'Archivia'**
  String get archivia;

  /// No description provided for @riattiva.
  ///
  /// In it, this message translates to:
  /// **'Riattiva'**
  String get riattiva;

  /// No description provided for @rinomina.
  ///
  /// In it, this message translates to:
  /// **'Rinomina'**
  String get rinomina;

  /// No description provided for @nuovo.
  ///
  /// In it, this message translates to:
  /// **'Nuovo'**
  String get nuovo;

  /// No description provided for @altreAzioni.
  ///
  /// In it, this message translates to:
  /// **'Altre azioni'**
  String get altreAzioni;

  /// No description provided for @benvenutoTitolo.
  ///
  /// In it, this message translates to:
  /// **'Benvenuto in Open Coach'**
  String get benvenutoTitolo;

  /// No description provided for @benvenutoSpiegazione.
  ///
  /// In it, this message translates to:
  /// **'Il programma fa da server per i tuoi atleti attraverso la rete Tor: niente account, niente servizi esterni. Gli atleti si collegano finché il programma è aperto su questo PC.'**
  String get benvenutoSpiegazione;

  /// No description provided for @nomeCoach.
  ///
  /// In it, this message translates to:
  /// **'Nome del coach'**
  String get nomeCoach;

  /// No description provided for @nomeCoachAiuto.
  ///
  /// In it, this message translates to:
  /// **'Gli atleti lo vedono quando si collegano'**
  String get nomeCoachAiuto;

  /// No description provided for @avvioAutomatico.
  ///
  /// In it, this message translates to:
  /// **'Avvia Open Coach con il computer'**
  String get avvioAutomatico;

  /// No description provided for @avvioAutomaticoAiuto.
  ///
  /// In it, this message translates to:
  /// **'Il programma parte nell\'area di notifica, così gli atleti possono sincronizzare'**
  String get avvioAutomaticoAiuto;

  /// No description provided for @inizia.
  ///
  /// In it, this message translates to:
  /// **'Inizia'**
  String get inizia;

  /// No description provided for @sezioneAtleti.
  ///
  /// In it, this message translates to:
  /// **'Atleti'**
  String get sezioneAtleti;

  /// No description provided for @sezioneLibreria.
  ///
  /// In it, this message translates to:
  /// **'Libreria'**
  String get sezioneLibreria;

  /// No description provided for @sezioneStato.
  ///
  /// In it, this message translates to:
  /// **'Stato'**
  String get sezioneStato;

  /// No description provided for @sezioneImpostazioni.
  ///
  /// In it, this message translates to:
  /// **'Impostazioni'**
  String get sezioneImpostazioni;

  /// No description provided for @avvisoBackup.
  ///
  /// In it, this message translates to:
  /// **'Non c\'è un backup degli ultimi 30 giorni. Senza backup, se il PC si guasta tutti gli atleti dovranno riabbinarsi.'**
  String get avvisoBackup;

  /// No description provided for @vaiAlBackup.
  ///
  /// In it, this message translates to:
  /// **'Vai al backup'**
  String get vaiAlBackup;

  /// No description provided for @avvisoTorObsoleto.
  ///
  /// In it, this message translates to:
  /// **'La versione di Tor inclusa è obsoleta: aggiorna Open Coach.'**
  String get avvisoTorObsoleto;

  /// No description provided for @esciTitolo.
  ///
  /// In it, this message translates to:
  /// **'Uscire da Open Coach?'**
  String get esciTitolo;

  /// No description provided for @esciTesto.
  ///
  /// In it, this message translates to:
  /// **'Finché il programma è chiuso gli atleti non possono sincronizzare: i loro allenamenti restano sul telefono e le schede nuove non arrivano.'**
  String get esciTesto;

  /// No description provided for @esciDaOpenCoach.
  ///
  /// In it, this message translates to:
  /// **'Esci da Open Coach'**
  String get esciDaOpenCoach;

  /// No description provided for @notificaLogRicevuto.
  ///
  /// In it, this message translates to:
  /// **'{nome} ha registrato un allenamento'**
  String notificaLogRicevuto(String nome);

  /// No description provided for @notificaAbbinato.
  ///
  /// In it, this message translates to:
  /// **'{nome} ha collegato {telefono}'**
  String notificaAbbinato(String nome, String telefono);

  /// No description provided for @notificaTelefonoCoach.
  ///
  /// In it, this message translates to:
  /// **'Il tuo telefono è collegato: {telefono}. Se non sei stato tu, scollegalo subito dalle impostazioni.'**
  String notificaTelefonoCoach(String telefono);

  /// No description provided for @notificaTelefonoContestatoTitolo.
  ///
  /// In it, this message translates to:
  /// **'Attenzione: QR usato due volte'**
  String get notificaTelefonoContestatoTitolo;

  /// No description provided for @notificaTelefonoContestato.
  ///
  /// In it, this message translates to:
  /// **'Un secondo telefono ha provato a usare il QR del tuo telefono. Il QR può essere stato fotografato: controlla quale telefono è collegato.'**
  String get notificaTelefonoContestato;

  /// No description provided for @telefonoCoach.
  ///
  /// In it, this message translates to:
  /// **'Il mio telefono'**
  String get telefonoCoach;

  /// No description provided for @telefonoCoachSpiegazione.
  ///
  /// In it, this message translates to:
  /// **'Con l\'app del coach rispondi agli atleti e guardi i loro dati anche dal telefono. Il telefono parla con questo PC attraverso Tor: funziona solo mentre il PC è acceso con il programma aperto.'**
  String get telefonoCoachSpiegazione;

  /// No description provided for @collegaTelefonoCoach.
  ///
  /// In it, this message translates to:
  /// **'Collega il mio telefono'**
  String get collegaTelefonoCoach;

  /// No description provided for @telefonoCoachCollegato.
  ///
  /// In it, this message translates to:
  /// **'Collegato: {telefono}'**
  String telefonoCoachCollegato(String telefono);

  /// No description provided for @telefonoCoachDettagli.
  ///
  /// In it, this message translates to:
  /// **'Collegato il {quando}. Ultimo contatto: {contatto}.'**
  String telefonoCoachDettagli(String quando, String contatto);

  /// No description provided for @telefonoCoachMaiVisto.
  ///
  /// In it, this message translates to:
  /// **'mai'**
  String get telefonoCoachMaiVisto;

  /// No description provided for @scollegaTelefonoCoach.
  ///
  /// In it, this message translates to:
  /// **'Scollega il mio telefono'**
  String get scollegaTelefonoCoach;

  /// No description provided for @scollegaTelefonoCoachTitolo.
  ///
  /// In it, this message translates to:
  /// **'Scollegare {telefono}?'**
  String scollegaTelefonoCoachTitolo(String telefono);

  /// No description provided for @scollegaTelefonoCoachTesto.
  ///
  /// In it, this message translates to:
  /// **'Il telefono smette subito di vedere i dati dei tuoi atleti. Fallo se lo perdi o te lo rubano. I messaggi che ha ancora in coda non partiranno.'**
  String get scollegaTelefonoCoachTesto;

  /// No description provided for @qrTelefonoCoachTitolo.
  ///
  /// In it, this message translates to:
  /// **'Collega il tuo telefono'**
  String get qrTelefonoCoachTitolo;

  /// No description provided for @qrTelefonoCoachSpiegazione.
  ///
  /// In it, this message translates to:
  /// **'Apri l\'app del coach sul telefono e inquadra questo QR. Chi lo inquadra vede i dati di tutti i tuoi atleti: non fotografarlo e non mostrarlo a nessuno.'**
  String get qrTelefonoCoachSpiegazione;

  /// No description provided for @qrTelefonoCoachValido.
  ///
  /// In it, this message translates to:
  /// **'Valido fino alle {quando}'**
  String qrTelefonoCoachValido(String quando);

  /// No description provided for @qrTelefonoCoachInCorso.
  ///
  /// In it, this message translates to:
  /// **'Telefono trovato: sta finendo di collegarsi…'**
  String get qrTelefonoCoachInCorso;

  /// No description provided for @qrTelefonoCoachFatto.
  ///
  /// In it, this message translates to:
  /// **'Telefono collegato: {telefono}'**
  String qrTelefonoCoachFatto(String telefono);

  /// No description provided for @sostituireTelefonoCoachTitolo.
  ///
  /// In it, this message translates to:
  /// **'Sostituire il telefono collegato?'**
  String get sostituireTelefonoCoachTitolo;

  /// No description provided for @sostituireTelefonoCoachTesto.
  ///
  /// In it, this message translates to:
  /// **'Puoi avere un solo telefono collegato: quando il nuovo inquadra il QR, {telefono} smette di funzionare.'**
  String sostituireTelefonoCoachTesto(String telefono);

  /// No description provided for @notificaInvitoContestatoTitolo.
  ///
  /// In it, this message translates to:
  /// **'Attenzione: invito usato due volte'**
  String get notificaInvitoContestatoTitolo;

  /// No description provided for @notificaInvitoContestato.
  ///
  /// In it, this message translates to:
  /// **'Un secondo telefono ha provato a usare l\'invito di {nome}. Il link può essere stato intercettato: controlla quale telefono è collegato.'**
  String notificaInvitoContestato(String nome);

  /// No description provided for @statoAvvio.
  ///
  /// In it, this message translates to:
  /// **'Avvio di Tor ({percentuale}%)'**
  String statoAvvio(int percentuale);

  /// No description provided for @statoNessunaChiave.
  ///
  /// In it, this message translates to:
  /// **'In attesa del primo invito'**
  String get statoNessunaChiave;

  /// No description provided for @statoPubblicazione.
  ///
  /// In it, this message translates to:
  /// **'Pubblicazione del servizio'**
  String get statoPubblicazione;

  /// No description provided for @statoRaggiungibile.
  ///
  /// In it, this message translates to:
  /// **'Raggiungibile'**
  String get statoRaggiungibile;

  /// No description provided for @statoNonRaggiungibile.
  ///
  /// In it, this message translates to:
  /// **'Non raggiungibile: {motivo}'**
  String statoNonRaggiungibile(String motivo);

  /// No description provided for @servizio.
  ///
  /// In it, this message translates to:
  /// **'Servizio'**
  String get servizio;

  /// No description provided for @spiegazioneRaggiungibile.
  ///
  /// In it, this message translates to:
  /// **'I telefoni degli atleti possono collegarsi.'**
  String get spiegazioneRaggiungibile;

  /// No description provided for @spiegazioneNessunaChiave.
  ///
  /// In it, this message translates to:
  /// **'Il servizio si pubblica quando crei il primo invito: prima nessuno potrebbe raggiungerlo.'**
  String get spiegazioneNessunaChiave;

  /// No description provided for @spiegazioneNonPronto.
  ///
  /// In it, this message translates to:
  /// **'Gli atleti non possono ancora collegarsi. Gli allenamenti restano sui loro telefoni e partiranno appena il servizio sarà raggiungibile.'**
  String get spiegazioneNonPronto;

  /// No description provided for @indirizzo.
  ///
  /// In it, this message translates to:
  /// **'Indirizzo'**
  String get indirizzo;

  /// No description provided for @indirizzoCopiato.
  ///
  /// In it, this message translates to:
  /// **'Indirizzo copiato'**
  String get indirizzoCopiato;

  /// No description provided for @indirizzoSpiegazione.
  ///
  /// In it, this message translates to:
  /// **'Gli atleti lo ricevono nel QR dell\'invito: non serve comunicarlo.'**
  String get indirizzoSpiegazione;

  /// No description provided for @riepilogoAtleti.
  ///
  /// In it, this message translates to:
  /// **'Atleti: {atleti} · telefoni collegati: {telefoni} · inviti aperti: {inviti}'**
  String riepilogoAtleti(int atleti, int telefoni, int inviti);

  /// No description provided for @ultimoContattoDiTutti.
  ///
  /// In it, this message translates to:
  /// **'Ultimo contatto di un telefono: {quando}'**
  String ultimoContattoDiTutti(String quando);

  /// No description provided for @backup.
  ///
  /// In it, this message translates to:
  /// **'Backup'**
  String get backup;

  /// No description provided for @backupMai.
  ///
  /// In it, this message translates to:
  /// **'Nessun backup fatto finora'**
  String get backupMai;

  /// No description provided for @backupUltimo.
  ///
  /// In it, this message translates to:
  /// **'Ultimo backup: {quando}'**
  String backupUltimo(String quando);

  /// No description provided for @atletiArchiviati.
  ///
  /// In it, this message translates to:
  /// **'Atleti archiviati'**
  String get atletiArchiviati;

  /// No description provided for @mostraArchiviati.
  ///
  /// In it, this message translates to:
  /// **'Mostra gli archiviati'**
  String get mostraArchiviati;

  /// No description provided for @mostraAttivi.
  ///
  /// In it, this message translates to:
  /// **'Mostra gli attivi'**
  String get mostraAttivi;

  /// No description provided for @nuovoAtleta.
  ///
  /// In it, this message translates to:
  /// **'Nuovo atleta'**
  String get nuovoAtleta;

  /// No description provided for @nomeAtleta.
  ///
  /// In it, this message translates to:
  /// **'Nome dell\'atleta'**
  String get nomeAtleta;

  /// No description provided for @nessunAtleta.
  ///
  /// In it, this message translates to:
  /// **'Nessun atleta. Crea il primo con «Nuovo».'**
  String get nessunAtleta;

  /// No description provided for @nessunAtletaArchiviato.
  ///
  /// In it, this message translates to:
  /// **'Nessun atleta archiviato.'**
  String get nessunAtletaArchiviato;

  /// No description provided for @scegliAtleta.
  ///
  /// In it, this message translates to:
  /// **'Scegli un atleta, oppure creane uno nuovo.'**
  String get scegliAtleta;

  /// No description provided for @telefonoMaiSincronizzato.
  ///
  /// In it, this message translates to:
  /// **'{telefono} · non ha ancora sincronizzato'**
  String telefonoMaiSincronizzato(String telefono);

  /// No description provided for @telefonoUltimoContatto.
  ///
  /// In it, this message translates to:
  /// **'{telefono} · {quando}'**
  String telefonoUltimoContatto(String telefono, String quando);

  /// No description provided for @invitoInCorso.
  ///
  /// In it, this message translates to:
  /// **'Invito in corso'**
  String get invitoInCorso;

  /// No description provided for @nessunTelefono.
  ///
  /// In it, this message translates to:
  /// **'Nessun telefono'**
  String get nessunTelefono;

  /// No description provided for @atletaArchiviato.
  ///
  /// In it, this message translates to:
  /// **'Archiviato'**
  String get atletaArchiviato;

  /// No description provided for @notePrivate.
  ///
  /// In it, this message translates to:
  /// **'Note private'**
  String get notePrivate;

  /// No description provided for @notePrivateAiuto.
  ///
  /// In it, this message translates to:
  /// **'Restano su questo PC: l\'atleta non le vede'**
  String get notePrivateAiuto;

  /// No description provided for @esportaJson.
  ///
  /// In it, this message translates to:
  /// **'Esporta in JSON'**
  String get esportaJson;

  /// No description provided for @esportaCsv.
  ///
  /// In it, this message translates to:
  /// **'Esporta gli allenamenti in CSV'**
  String get esportaCsv;

  /// No description provided for @esportato.
  ///
  /// In it, this message translates to:
  /// **'Salvato in {percorso}'**
  String esportato(String percorso);

  /// No description provided for @eliminaAtletaTitolo.
  ///
  /// In it, this message translates to:
  /// **'Eliminare {nome}?'**
  String eliminaAtletaTitolo(String nome);

  /// No description provided for @eliminaAtletaTesto.
  ///
  /// In it, this message translates to:
  /// **'Il telefono viene scollegato e si cancellano schede e allenamenti dell\'atleta. Non si può annullare.'**
  String get eliminaAtletaTesto;

  /// No description provided for @schedaSchede.
  ///
  /// In it, this message translates to:
  /// **'Schede'**
  String get schedaSchede;

  /// No description provided for @schedaStorico.
  ///
  /// In it, this message translates to:
  /// **'Storico'**
  String get schedaStorico;

  /// No description provided for @storicoTotale.
  ///
  /// In it, this message translates to:
  /// **'Allenamenti registrati'**
  String get storicoTotale;

  /// No description provided for @storicoSettimana.
  ///
  /// In it, this message translates to:
  /// **'Questa settimana'**
  String get storicoSettimana;

  /// No description provided for @storicoUltimo.
  ///
  /// In it, this message translates to:
  /// **'Ultimo allenamento'**
  String get storicoUltimo;

  /// No description provided for @storicoAllenamenti.
  ///
  /// In it, this message translates to:
  /// **'Allenamenti a settimana'**
  String get storicoAllenamenti;

  /// No description provided for @storicoAllenamentiDettaglio.
  ///
  /// In it, this message translates to:
  /// **'Dal {giorno}: {numero, plural, one{1 allenamento} other{{numero} allenamenti}}'**
  String storicoAllenamentiDettaglio(String giorno, int numero);

  /// No description provided for @storicoDiQualeScheda.
  ///
  /// In it, this message translates to:
  /// **'Scheda'**
  String get storicoDiQualeScheda;

  /// No description provided for @storicoSchedaAttiva.
  ///
  /// In it, this message translates to:
  /// **'{titolo} (attiva)'**
  String storicoSchedaAttiva(String titolo);

  /// No description provided for @storicoLiberi.
  ///
  /// In it, this message translates to:
  /// **'Allenamenti liberi'**
  String get storicoLiberi;

  /// No description provided for @storicoTutte.
  ///
  /// In it, this message translates to:
  /// **'Tutte le schede'**
  String get storicoTutte;

  /// No description provided for @storicoSchedaVuota.
  ///
  /// In it, this message translates to:
  /// **'Nessun allenamento registrato con questa scheda.'**
  String get storicoSchedaVuota;

  /// No description provided for @storicoMisuraStima.
  ///
  /// In it, this message translates to:
  /// **'Il massimale stimato più alto di ogni allenamento, in chili: dal carico e dalle ripetizioni, contando il RIR previsto dal coach se c\'è.'**
  String get storicoMisuraStima;

  /// No description provided for @storicoProgressi.
  ///
  /// In it, this message translates to:
  /// **'Progressi per esercizio'**
  String get storicoProgressi;

  /// No description provided for @storicoMisuraCarico.
  ///
  /// In it, this message translates to:
  /// **'Il carico più alto di ogni allenamento, in chili.'**
  String get storicoMisuraCarico;

  /// No description provided for @storicoMisuraRipetizioni.
  ///
  /// In it, this message translates to:
  /// **'Il numero più alto di ripetizioni di ogni allenamento.'**
  String get storicoMisuraRipetizioni;

  /// No description provided for @storicoMisuraDurata.
  ///
  /// In it, this message translates to:
  /// **'La serie più lunga di ogni allenamento, in secondi.'**
  String get storicoMisuraDurata;

  /// No description provided for @pubblicataEArchiviata.
  ///
  /// In it, this message translates to:
  /// **'Pubblicata la revisione {revisione}: «{titolo}» passa nell\'archivio'**
  String pubblicataEArchiviata(int revisione, String titolo);

  /// No description provided for @schedaPeso.
  ///
  /// In it, this message translates to:
  /// **'Peso'**
  String get schedaPeso;

  /// No description provided for @nessunPeso.
  ///
  /// In it, this message translates to:
  /// **'L\'atleta non ti ha ancora condiviso il suo peso. Lo registra nell\'app, dalla versione 1.2.0, e sceglie con quali coach condividerlo.'**
  String get nessunPeso;

  /// No description provided for @ultimoPeso.
  ///
  /// In it, this message translates to:
  /// **'Ultimo peso, {giorno}'**
  String ultimoPeso(String giorno);

  /// No description provided for @mediaSettimana.
  ///
  /// In it, this message translates to:
  /// **'Media degli ultimi 7 giorni'**
  String get mediaSettimana;

  /// No description provided for @rispettoSettimanaPrima.
  ///
  /// In it, this message translates to:
  /// **'Rispetto ai 7 giorni prima'**
  String get rispettoSettimanaPrima;

  /// No description provided for @legendaGraficoPeso.
  ///
  /// In it, this message translates to:
  /// **'I punti sono i pesi di ogni giorno, la linea è la media degli ultimi 7 giorni.'**
  String get legendaGraficoPeso;

  /// No description provided for @tuttiIPesi.
  ///
  /// In it, this message translates to:
  /// **'Tutti i pesi'**
  String get tuttiIPesi;

  /// No description provided for @schedaCibo.
  ///
  /// In it, this message translates to:
  /// **'Cibo'**
  String get schedaCibo;

  /// No description provided for @nessunCibo.
  ///
  /// In it, this message translates to:
  /// **'L\'atleta non ti ha ancora condiviso cosa mangia. Lo registra nell\'app, nella sezione Cibo, dalla versione 1.6.0.'**
  String get nessunCibo;

  /// No description provided for @obiettivoCibo.
  ///
  /// In it, this message translates to:
  /// **'Obiettivo giornaliero'**
  String get obiettivoCibo;

  /// No description provided for @nessunObiettivoCibo.
  ///
  /// In it, this message translates to:
  /// **'Nessun obiettivo. Puoi fissare le calorie e, se vuoi, i macronutrienti: l\'atleta li vede nell\'app.'**
  String get nessunObiettivoCibo;

  /// No description provided for @fissaObiettivo.
  ///
  /// In it, this message translates to:
  /// **'Fissa l\'obiettivo'**
  String get fissaObiettivo;

  /// No description provided for @modificaObiettivo.
  ///
  /// In it, this message translates to:
  /// **'Modifica'**
  String get modificaObiettivo;

  /// No description provided for @togliObiettivo.
  ///
  /// In it, this message translates to:
  /// **'Togli l\'obiettivo'**
  String get togliObiettivo;

  /// No description provided for @obiettivoSpiegazione.
  ///
  /// In it, this message translates to:
  /// **'Un obiettivo indicativo che l\'atleta vede accanto a quello che mangia. Le calorie sono obbligatorie, i macronutrienti no.'**
  String get obiettivoSpiegazione;

  /// No description provided for @obiettivoNonValido.
  ///
  /// In it, this message translates to:
  /// **'Le calorie vanno da 500 a 8000, i grammi da 0 a 1000.'**
  String get obiettivoNonValido;

  /// No description provided for @calorie.
  ///
  /// In it, this message translates to:
  /// **'Calorie'**
  String get calorie;

  /// No description provided for @proteine.
  ///
  /// In it, this message translates to:
  /// **'Proteine'**
  String get proteine;

  /// No description provided for @carboidrati.
  ///
  /// In it, this message translates to:
  /// **'Carboidrati'**
  String get carboidrati;

  /// No description provided for @grassi.
  ///
  /// In it, this message translates to:
  /// **'Grassi'**
  String get grassi;

  /// No description provided for @mediaCiboSettimana.
  ///
  /// In it, this message translates to:
  /// **'Media degli ultimi 7 giorni registrati'**
  String get mediaCiboSettimana;

  /// No description provided for @legendaGraficoCibo.
  ///
  /// In it, this message translates to:
  /// **'Le calorie di ogni giorno delle ultime 4 settimane; la linea è l\'obiettivo.'**
  String get legendaGraficoCibo;

  /// No description provided for @giorniCibo.
  ///
  /// In it, this message translates to:
  /// **'Giorni'**
  String get giorniCibo;

  /// No description provided for @pastoColazione.
  ///
  /// In it, this message translates to:
  /// **'Colazione'**
  String get pastoColazione;

  /// No description provided for @pastoPranzo.
  ///
  /// In it, this message translates to:
  /// **'Pranzo'**
  String get pastoPranzo;

  /// No description provided for @pastoCena.
  ///
  /// In it, this message translates to:
  /// **'Cena'**
  String get pastoCena;

  /// No description provided for @pastoSpuntini.
  ///
  /// In it, this message translates to:
  /// **'Spuntini'**
  String get pastoSpuntini;

  /// No description provided for @fonteOpenFoodFacts.
  ///
  /// In it, this message translates to:
  /// **'Open Food Facts'**
  String get fonteOpenFoodFacts;

  /// No description provided for @fonteAtleta.
  ///
  /// In it, this message translates to:
  /// **'scritto dall\'atleta'**
  String get fonteAtleta;

  /// No description provided for @nuovoQuestionario.
  ///
  /// In it, this message translates to:
  /// **'Nuovo questionario'**
  String get nuovoQuestionario;

  /// No description provided for @modificaQuestionario.
  ///
  /// In it, this message translates to:
  /// **'Modifica il questionario'**
  String get modificaQuestionario;

  /// No description provided for @questionariSpiegazione.
  ///
  /// In it, this message translates to:
  /// **'Anamnesi iniziale, check mensili, tutto quello che vuoi chiedere ai tuoi atleti, anche con delle foto. Si mandano dalla pagina dell\'atleta, nella scheda «Questionari».'**
  String get questionariSpiegazione;

  /// No description provided for @nessunQuestionario.
  ///
  /// In it, this message translates to:
  /// **'Non hai ancora scritto questionari.'**
  String get nessunQuestionario;

  /// No description provided for @numeroDomande.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 domanda} other{{n} domande}}'**
  String numeroDomande(int n);

  /// No description provided for @numeroFoto.
  ///
  /// In it, this message translates to:
  /// **'{n, plural, =1{1 foto} other{{n} foto}}'**
  String numeroFoto(int n);

  /// No description provided for @eliminaQuestionarioTitolo.
  ///
  /// In it, this message translates to:
  /// **'Eliminare «{titolo}»?'**
  String eliminaQuestionarioTitolo(String titolo);

  /// No description provided for @eliminaQuestionarioTesto.
  ///
  /// In it, this message translates to:
  /// **'I questionari già mandati agli atleti, con le loro risposte, restano.'**
  String get eliminaQuestionarioTesto;

  /// No description provided for @tipoTestoBreve.
  ///
  /// In it, this message translates to:
  /// **'Testo breve'**
  String get tipoTestoBreve;

  /// No description provided for @tipoTestoLungo.
  ///
  /// In it, this message translates to:
  /// **'Testo lungo'**
  String get tipoTestoLungo;

  /// No description provided for @tipoNumero.
  ///
  /// In it, this message translates to:
  /// **'Numero'**
  String get tipoNumero;

  /// No description provided for @tipoSceltaSingola.
  ///
  /// In it, this message translates to:
  /// **'Scelta singola'**
  String get tipoSceltaSingola;

  /// No description provided for @tipoSceltaMultipla.
  ///
  /// In it, this message translates to:
  /// **'Scelta multipla'**
  String get tipoSceltaMultipla;

  /// No description provided for @tipoScala.
  ///
  /// In it, this message translates to:
  /// **'Scala da 1 a 10'**
  String get tipoScala;

  /// No description provided for @titoloQuestionario.
  ///
  /// In it, this message translates to:
  /// **'Titolo'**
  String get titoloQuestionario;

  /// No description provided for @descrizioneQuestionario.
  ///
  /// In it, this message translates to:
  /// **'Descrizione'**
  String get descrizioneQuestionario;

  /// No description provided for @descrizioneAiuto.
  ///
  /// In it, this message translates to:
  /// **'L\'atleta la legge prima delle domande: a cosa serve il questionario, come compilarlo'**
  String get descrizioneAiuto;

  /// No description provided for @domandaNumero.
  ///
  /// In it, this message translates to:
  /// **'Domanda {n}'**
  String domandaNumero(int n);

  /// No description provided for @aggiungiDomanda.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi una domanda'**
  String get aggiungiDomanda;

  /// No description provided for @togliDomanda.
  ///
  /// In it, this message translates to:
  /// **'Togli la domanda'**
  String get togliDomanda;

  /// No description provided for @opzioni.
  ///
  /// In it, this message translates to:
  /// **'Opzioni'**
  String get opzioni;

  /// No description provided for @opzioniAiuto.
  ///
  /// In it, this message translates to:
  /// **'Una per riga'**
  String get opzioniAiuto;

  /// No description provided for @consentiAltro.
  ///
  /// In it, this message translates to:
  /// **'Consenti «Altro:» con una risposta scritta'**
  String get consentiAltro;

  /// No description provided for @unita.
  ///
  /// In it, this message translates to:
  /// **'Unità'**
  String get unita;

  /// No description provided for @pesoCorporeo.
  ///
  /// In it, this message translates to:
  /// **'È il peso corporeo'**
  String get pesoCorporeo;

  /// No description provided for @pesoCorporeoAiuto.
  ///
  /// In it, this message translates to:
  /// **'L\'app la precompila con l\'ultimo peso registrato dall\'atleta'**
  String get pesoCorporeoAiuto;

  /// No description provided for @obbligatoria.
  ///
  /// In it, this message translates to:
  /// **'Obbligatoria'**
  String get obbligatoria;

  /// No description provided for @chiediFoto.
  ///
  /// In it, this message translates to:
  /// **'Chiedi delle foto'**
  String get chiediFoto;

  /// No description provided for @chiediFotoAiuto.
  ///
  /// In it, this message translates to:
  /// **'L\'atleta le scatta o le sceglie dalla galleria; l\'app le comprime e toglie la posizione GPS'**
  String get chiediFotoAiuto;

  /// No description provided for @quanteFoto.
  ///
  /// In it, this message translates to:
  /// **'Quante foto'**
  String get quanteFoto;

  /// No description provided for @daUnoADieci.
  ///
  /// In it, this message translates to:
  /// **'Da 1 a 10'**
  String get daUnoADieci;

  /// No description provided for @istruzioniFoto.
  ///
  /// In it, this message translates to:
  /// **'Istruzioni per le foto'**
  String get istruzioniFoto;

  /// No description provided for @istruzioniFotoAiuto.
  ///
  /// In it, this message translates to:
  /// **'Per esempio le pose, la luce, il corpo intero'**
  String get istruzioniFotoAiuto;

  /// No description provided for @questionarioSalvato.
  ///
  /// In it, this message translates to:
  /// **'Questionario salvato'**
  String get questionarioSalvato;

  /// No description provided for @questionarioIncompleto.
  ///
  /// In it, this message translates to:
  /// **'Il questionario non è completo'**
  String get questionarioIncompleto;

  /// No description provided for @mandaQuestionario.
  ///
  /// In it, this message translates to:
  /// **'Manda un questionario'**
  String get mandaQuestionario;

  /// No description provided for @manda.
  ///
  /// In it, this message translates to:
  /// **'Manda'**
  String get manda;

  /// No description provided for @mandaQuestionarioA.
  ///
  /// In it, this message translates to:
  /// **'Mandare a {nome}'**
  String mandaQuestionarioA(String nome);

  /// No description provided for @questionarioMandato.
  ///
  /// In it, this message translates to:
  /// **'Mandato: l\'atleta lo riceve alla prossima sincronizzazione'**
  String get questionarioMandato;

  /// No description provided for @inAttesaDiRisposta.
  ///
  /// In it, this message translates to:
  /// **'Mandato il {quando}, in attesa di risposta'**
  String inAttesaDiRisposta(String quando);

  /// No description provided for @rispostoIl.
  ///
  /// In it, this message translates to:
  /// **'Risposte arrivate il {quando}'**
  String rispostoIl(String quando);

  /// No description provided for @questionarioAnnullato.
  ///
  /// In it, this message translates to:
  /// **'Annullato'**
  String get questionarioAnnullato;

  /// No description provided for @annullaQuestionario.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get annullaQuestionario;

  /// No description provided for @annullaQuestionarioTitolo.
  ///
  /// In it, this message translates to:
  /// **'Annullare il questionario?'**
  String get annullaQuestionarioTitolo;

  /// No description provided for @annullaQuestionarioTesto.
  ///
  /// In it, this message translates to:
  /// **'Sparisce dal telefono dell\'atleta alla prossima sincronizzazione. Se l\'ha già compilato e inviato, le risposte arrivano lo stesso.'**
  String get annullaQuestionarioTesto;

  /// No description provided for @fotoAllegate.
  ///
  /// In it, this message translates to:
  /// **'Foto'**
  String get fotoAllegate;

  /// No description provided for @altroValore.
  ///
  /// In it, this message translates to:
  /// **'Altro: {valore}'**
  String altroValore(String valore);

  /// No description provided for @risposteAtleta.
  ///
  /// In it, this message translates to:
  /// **'Risposte ai questionari'**
  String get risposteAtleta;

  /// No description provided for @nessunaRisposta.
  ///
  /// In it, this message translates to:
  /// **'L\'atleta non ha ancora risposto a nessun questionario.'**
  String get nessunaRisposta;

  /// No description provided for @notificaQuestionarioRisposto.
  ///
  /// In it, this message translates to:
  /// **'{nome} ha risposto a «{titolo}»'**
  String notificaQuestionarioRisposto(String nome, String titolo);

  /// No description provided for @nessunTelefonoSpiegazione.
  ///
  /// In it, this message translates to:
  /// **'Nessun telefono collegato. Crea un invito e fallo scansionare dall\'app dell\'atleta.'**
  String get nessunTelefonoSpiegazione;

  /// No description provided for @revoca.
  ///
  /// In it, this message translates to:
  /// **'Scollega'**
  String get revoca;

  /// No description provided for @scollegaTelefono.
  ///
  /// In it, this message translates to:
  /// **'Scollega il telefono'**
  String get scollegaTelefono;

  /// No description provided for @revocaTitolo.
  ///
  /// In it, this message translates to:
  /// **'Scollegare {telefono}?'**
  String revocaTitolo(String telefono);

  /// No description provided for @revocaTesto.
  ///
  /// In it, this message translates to:
  /// **'Il telefono di {nome} non potrà più sincronizzare. Per ricollegarlo serve un nuovo invito.'**
  String revocaTesto(String nome);

  /// No description provided for @validoFinoAl.
  ///
  /// In it, this message translates to:
  /// **'Valido fino al {quando}'**
  String validoFinoAl(String quando);

  /// No description provided for @nuovoInvito.
  ///
  /// In it, this message translates to:
  /// **'Nuovo invito'**
  String get nuovoInvito;

  /// No description provided for @creaInvito.
  ///
  /// In it, this message translates to:
  /// **'Crea l\'invito'**
  String get creaInvito;

  /// No description provided for @sostituireTelefonoTitolo.
  ///
  /// In it, this message translates to:
  /// **'Sostituire il telefono?'**
  String get sostituireTelefonoTitolo;

  /// No description provided for @sostituireTelefonoTesto.
  ///
  /// In it, this message translates to:
  /// **'Quando il nuovo telefono si collega, quello attuale viene scollegato. Gli allenamenti che il vecchio telefono non ha ancora inviato restano solo lì: fallo sincronizzare prima.'**
  String get sostituireTelefonoTesto;

  /// No description provided for @invitoTitolo.
  ///
  /// In it, this message translates to:
  /// **'Invito per l\'app dell\'atleta'**
  String get invitoTitolo;

  /// No description provided for @invitoSpiegazione.
  ///
  /// In it, this message translates to:
  /// **'Fai scansionare questo codice dall\'app dell\'atleta. Se mandi il link con altri mezzi, trattalo come una password: vale una volta sola.'**
  String get invitoSpiegazione;

  /// No description provided for @copiaLink.
  ///
  /// In it, this message translates to:
  /// **'Copia il link'**
  String get copiaLink;

  /// No description provided for @linkCopiato.
  ///
  /// In it, this message translates to:
  /// **'Link copiato'**
  String get linkCopiato;

  /// No description provided for @nuovaScheda.
  ///
  /// In it, this message translates to:
  /// **'Nuova scheda'**
  String get nuovaScheda;

  /// No description provided for @nuovaSchedaTitolo.
  ///
  /// In it, this message translates to:
  /// **'Nuova scheda'**
  String get nuovaSchedaTitolo;

  /// No description provided for @nessunaScheda.
  ///
  /// In it, this message translates to:
  /// **'Nessuna scheda per questo atleta.'**
  String get nessunaScheda;

  /// No description provided for @senzaTitolo.
  ///
  /// In it, this message translates to:
  /// **'Senza titolo'**
  String get senzaTitolo;

  /// No description provided for @duplica.
  ///
  /// In it, this message translates to:
  /// **'Duplica…'**
  String get duplica;

  /// No description provided for @duplicaPer.
  ///
  /// In it, this message translates to:
  /// **'Duplica la scheda per'**
  String get duplicaPer;

  /// No description provided for @stessoAtleta.
  ///
  /// In it, this message translates to:
  /// **'{nome} (stesso atleta)'**
  String stessoAtleta(String nome);

  /// No description provided for @schedaDuplicata.
  ///
  /// In it, this message translates to:
  /// **'Scheda duplicata come bozza'**
  String get schedaDuplicata;

  /// No description provided for @riportaTraLeAttive.
  ///
  /// In it, this message translates to:
  /// **'Riporta tra le attive'**
  String get riportaTraLeAttive;

  /// No description provided for @eliminaSchedaTitolo.
  ///
  /// In it, this message translates to:
  /// **'Eliminare la scheda?'**
  String get eliminaSchedaTitolo;

  /// No description provided for @eliminaSchedaPubblicata.
  ///
  /// In it, this message translates to:
  /// **'La scheda sparisce anche dal telefono dell\'atleta alla prossima sync. Gli allenamenti già registrati restano.'**
  String get eliminaSchedaPubblicata;

  /// No description provided for @eliminaBozza.
  ///
  /// In it, this message translates to:
  /// **'La bozza non è mai stata pubblicata: l\'atleta non l\'ha mai vista.'**
  String get eliminaBozza;

  /// No description provided for @bozzaMaiPubblicata.
  ///
  /// In it, this message translates to:
  /// **'Bozza, mai pubblicata'**
  String get bozzaMaiPubblicata;

  /// No description provided for @archiviata.
  ///
  /// In it, this message translates to:
  /// **'Archiviata'**
  String get archiviata;

  /// No description provided for @revisione.
  ///
  /// In it, this message translates to:
  /// **'Revisione {numero}'**
  String revisione(int numero);

  /// No description provided for @inAttesaDiConsegna.
  ///
  /// In it, this message translates to:
  /// **'in attesa di consegna'**
  String get inAttesaDiConsegna;

  /// No description provided for @ricevutaIl.
  ///
  /// In it, this message translates to:
  /// **'ricevuta il {quando}'**
  String ricevutaIl(String quando);

  /// No description provided for @modificheNonPubblicate.
  ///
  /// In it, this message translates to:
  /// **'modifiche non pubblicate'**
  String get modificheNonPubblicate;

  /// No description provided for @revisioniPubblicate.
  ///
  /// In it, this message translates to:
  /// **'Revisioni pubblicate'**
  String get revisioniPubblicate;

  /// No description provided for @pubblicataIl.
  ///
  /// In it, this message translates to:
  /// **'pubblicata il {quando}'**
  String pubblicataIl(String quando);

  /// No description provided for @sostituitaPrimaDiArrivare.
  ///
  /// In it, this message translates to:
  /// **'sostituita prima di arrivare all\'atleta'**
  String get sostituitaPrimaDiArrivare;

  /// No description provided for @schedaDi.
  ///
  /// In it, this message translates to:
  /// **'Scheda di {nome}'**
  String schedaDi(String nome);

  /// No description provided for @salvaBozza.
  ///
  /// In it, this message translates to:
  /// **'Salva la bozza'**
  String get salvaBozza;

  /// No description provided for @pubblica.
  ///
  /// In it, this message translates to:
  /// **'Pubblica'**
  String get pubblica;

  /// No description provided for @pubblicataRevisione.
  ///
  /// In it, this message translates to:
  /// **'Pubblicata la revisione {numero}: l\'atleta la riceverà alla prossima sync'**
  String pubblicataRevisione(int numero);

  /// No description provided for @schedaIncompleta.
  ///
  /// In it, this message translates to:
  /// **'La scheda non si può ancora pubblicare'**
  String get schedaIncompleta;

  /// No description provided for @modificheNonSalvateTitolo.
  ///
  /// In it, this message translates to:
  /// **'Uscire senza salvare?'**
  String get modificheNonSalvateTitolo;

  /// No description provided for @modificheNonSalvateTesto.
  ///
  /// In it, this message translates to:
  /// **'Le modifiche alla bozza andranno perse.'**
  String get modificheNonSalvateTesto;

  /// No description provided for @scarta.
  ///
  /// In it, this message translates to:
  /// **'Esci senza salvare'**
  String get scarta;

  /// No description provided for @titoloScheda.
  ///
  /// In it, this message translates to:
  /// **'Titolo'**
  String get titoloScheda;

  /// No description provided for @noteScheda.
  ///
  /// In it, this message translates to:
  /// **'Note per l\'atleta'**
  String get noteScheda;

  /// No description provided for @aggiungiSeduta.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi una seduta'**
  String get aggiungiSeduta;

  /// No description provided for @sedutaPredefinita.
  ///
  /// In it, this message translates to:
  /// **'Giorno {numero}'**
  String sedutaPredefinita(int numero);

  /// No description provided for @nomeSeduta.
  ///
  /// In it, this message translates to:
  /// **'Nome della seduta'**
  String get nomeSeduta;

  /// No description provided for @noteSeduta.
  ///
  /// In it, this message translates to:
  /// **'Note della seduta'**
  String get noteSeduta;

  /// No description provided for @togliSeduta.
  ///
  /// In it, this message translates to:
  /// **'Togli la seduta'**
  String get togliSeduta;

  /// No description provided for @aggiungiEsercizio.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi un esercizio'**
  String get aggiungiEsercizio;

  /// No description provided for @nomeEsercizio.
  ///
  /// In it, this message translates to:
  /// **'Esercizio'**
  String get nomeEsercizio;

  /// No description provided for @noteEsercizio.
  ///
  /// In it, this message translates to:
  /// **'Note dell\'esercizio'**
  String get noteEsercizio;

  /// No description provided for @togliEsercizio.
  ///
  /// In it, this message translates to:
  /// **'Togli l\'esercizio'**
  String get togliEsercizio;

  /// No description provided for @salvaNellaLibreria.
  ///
  /// In it, this message translates to:
  /// **'Salva nella libreria'**
  String get salvaNellaLibreria;

  /// No description provided for @videoDallaLibreria.
  ///
  /// In it, this message translates to:
  /// **'Video dalla libreria: {link}'**
  String videoDallaLibreria(String link);

  /// No description provided for @nellaLibreriaSenzaVideo.
  ///
  /// In it, this message translates to:
  /// **'Nella libreria, senza video: aggiungilo'**
  String get nellaLibreriaSenzaVideo;

  /// No description provided for @nuovoEsercizio.
  ///
  /// In it, this message translates to:
  /// **'Nuovo esercizio'**
  String get nuovoEsercizio;

  /// No description provided for @modificaEsercizio.
  ///
  /// In it, this message translates to:
  /// **'Modifica l\'esercizio'**
  String get modificaEsercizio;

  /// No description provided for @libreriaSpiegazione.
  ///
  /// In it, this message translates to:
  /// **'Gli esercizi che usi più spesso, con le note e il link a un video che mostra come si eseguono. Nelle schede li trovi scrivendo il nome; ogni esercizio con lo stesso nome riceve il video quando pubblichi la scheda.'**
  String get libreriaSpiegazione;

  /// No description provided for @libreriaVuota.
  ///
  /// In it, this message translates to:
  /// **'La libreria è vuota.'**
  String get libreriaVuota;

  /// No description provided for @linkVideo.
  ///
  /// In it, this message translates to:
  /// **'Link al video'**
  String get linkVideo;

  /// No description provided for @linkVideoAiuto.
  ///
  /// In it, this message translates to:
  /// **'YouTube, Vimeo o un altro sito, con https://'**
  String get linkVideoAiuto;

  /// No description provided for @videoNonValido.
  ///
  /// In it, this message translates to:
  /// **'Serve un link che inizia con https://'**
  String get videoNonValido;

  /// No description provided for @noteLibreriaAiuto.
  ///
  /// In it, this message translates to:
  /// **'Si copiano nella scheda quando scegli l\'esercizio'**
  String get noteLibreriaAiuto;

  /// No description provided for @eliminaEsercizioTitolo.
  ///
  /// In it, this message translates to:
  /// **'Eliminare {nome} dalla libreria?'**
  String eliminaEsercizioTitolo(String nome);

  /// No description provided for @eliminaEsercizioTesto.
  ///
  /// In it, this message translates to:
  /// **'Le schede già scritte non cambiano, ma alla prossima pubblicazione l\'esercizio non avrà più il video.'**
  String get eliminaEsercizioTesto;

  /// No description provided for @videoDaAggiornare.
  ///
  /// In it, this message translates to:
  /// **'{schede, plural, =1{Una scheda pubblicata ha un video diverso da quello della libreria.} other{{schede} schede pubblicate hanno un video diverso da quello della libreria.}}'**
  String videoDaAggiornare(int schede);

  /// No description provided for @aggiornaVideo.
  ///
  /// In it, this message translates to:
  /// **'Aggiorna i video'**
  String get aggiornaVideo;

  /// No description provided for @aggiornaVideoTitolo.
  ///
  /// In it, this message translates to:
  /// **'Aggiornare i video nelle schede?'**
  String get aggiornaVideoTitolo;

  /// No description provided for @aggiornaVideoTesto.
  ///
  /// In it, this message translates to:
  /// **'Gli atleti ricevono i video nuovi alla prossima sync. Le modifiche in bozza non vengono pubblicate.'**
  String get aggiornaVideoTesto;

  /// No description provided for @videoAggiornati.
  ///
  /// In it, this message translates to:
  /// **'{schede, plural, =1{Video aggiornato in una scheda} other{Video aggiornati in {schede} schede}}'**
  String videoAggiornati(int schede);

  /// No description provided for @serie.
  ///
  /// In it, this message translates to:
  /// **'Serie'**
  String get serie;

  /// No description provided for @ripetizioni.
  ///
  /// In it, this message translates to:
  /// **'Ripetizioni'**
  String get ripetizioni;

  /// No description provided for @carico.
  ///
  /// In it, this message translates to:
  /// **'Carico'**
  String get carico;

  /// No description provided for @recupero.
  ///
  /// In it, this message translates to:
  /// **'Recupero'**
  String get recupero;

  /// No description provided for @recuperoNonValido.
  ///
  /// In it, this message translates to:
  /// **'es. 90 o 1:30'**
  String get recuperoNonValido;

  /// No description provided for @rir.
  ///
  /// In it, this message translates to:
  /// **'RIR'**
  String get rir;

  /// No description provided for @altreRighe.
  ///
  /// In it, this message translates to:
  /// **'Altre serie da una versione precedente: {elenco}'**
  String altreRighe(String elenco);

  /// No description provided for @togliAltreRighe.
  ///
  /// In it, this message translates to:
  /// **'Toglile'**
  String get togliAltreRighe;

  /// No description provided for @spostaSu.
  ///
  /// In it, this message translates to:
  /// **'Sposta su'**
  String get spostaSu;

  /// No description provided for @spostaGiu.
  ///
  /// In it, this message translates to:
  /// **'Sposta giù'**
  String get spostaGiu;

  /// No description provided for @campoNome.
  ///
  /// In it, this message translates to:
  /// **'nome'**
  String get campoNome;

  /// No description provided for @campoNote.
  ///
  /// In it, this message translates to:
  /// **'note'**
  String get campoNote;

  /// No description provided for @erroreSeduta.
  ///
  /// In it, this message translates to:
  /// **'Seduta {numero}'**
  String erroreSeduta(int numero);

  /// No description provided for @erroreEsercizio.
  ///
  /// In it, this message translates to:
  /// **'esercizio {numero}'**
  String erroreEsercizio(int numero);

  /// No description provided for @erroreRiga.
  ///
  /// In it, this message translates to:
  /// **'riga {numero}'**
  String erroreRiga(int numero);

  /// No description provided for @erroreServeUnaSeduta.
  ///
  /// In it, this message translates to:
  /// **'Serve almeno una seduta'**
  String get erroreServeUnaSeduta;

  /// No description provided for @nessunAllenamento.
  ///
  /// In it, this message translates to:
  /// **'Nessun allenamento ricevuto finora.'**
  String get nessunAllenamento;

  /// No description provided for @coach.
  ///
  /// In it, this message translates to:
  /// **'Coach'**
  String get coach;

  /// No description provided for @avvioENotifiche.
  ///
  /// In it, this message translates to:
  /// **'Avvio e notifiche'**
  String get avvioENotifiche;

  /// No description provided for @impedisciSospensione.
  ///
  /// In it, this message translates to:
  /// **'Impedisci la sospensione del PC'**
  String get impedisciSospensione;

  /// No description provided for @impedisciSospensioneAiuto.
  ///
  /// In it, this message translates to:
  /// **'Con il PC sospeso gli atleti non possono sincronizzare'**
  String get impedisciSospensioneAiuto;

  /// No description provided for @notificheDesktop.
  ///
  /// In it, this message translates to:
  /// **'Notifiche sul desktop'**
  String get notificheDesktop;

  /// No description provided for @notificheDesktopAiuto.
  ///
  /// In it, this message translates to:
  /// **'Allenamenti ricevuti e telefoni collegati. Gli inviti usati due volte si segnalano sempre.'**
  String get notificheDesktopAiuto;

  /// No description provided for @backupConfigurato.
  ///
  /// In it, this message translates to:
  /// **'Backup automatici in {cartella}, {frequenza}'**
  String backupConfigurato(String cartella, String frequenza);

  /// No description provided for @backupNonConfigurato.
  ///
  /// In it, this message translates to:
  /// **'Backup automatici non configurati'**
  String get backupNonConfigurato;

  /// No description provided for @configuraBackup.
  ///
  /// In it, this message translates to:
  /// **'Configura i backup'**
  String get configuraBackup;

  /// No description provided for @cambiaBackup.
  ///
  /// In it, this message translates to:
  /// **'Cambia passphrase o cartella'**
  String get cambiaBackup;

  /// No description provided for @backupOra.
  ///
  /// In it, this message translates to:
  /// **'Fai un backup ora'**
  String get backupOra;

  /// No description provided for @salvaBackupIn.
  ///
  /// In it, this message translates to:
  /// **'Salva un backup in un file…'**
  String get salvaBackupIn;

  /// No description provided for @ripristinaDaBackup.
  ///
  /// In it, this message translates to:
  /// **'Ripristina da un backup…'**
  String get ripristinaDaBackup;

  /// No description provided for @backupSpiegazione.
  ///
  /// In it, this message translates to:
  /// **'Il backup è cifrato con la passphrase e contiene l\'identità: ripristinato su un altro PC, gli atleti non devono riabbinarsi. Due PC con la stessa identità non devono mai essere accesi insieme.'**
  String get backupSpiegazione;

  /// No description provided for @backupCreato.
  ///
  /// In it, this message translates to:
  /// **'Backup salvato in {percorso}'**
  String backupCreato(String percorso);

  /// No description provided for @frequenzaBackup.
  ///
  /// In it, this message translates to:
  /// **'Frequenza'**
  String get frequenzaBackup;

  /// No description provided for @ogniGiorni.
  ///
  /// In it, this message translates to:
  /// **'{giorni, plural, =1{ogni giorno} other{ogni {giorni} giorni}}'**
  String ogniGiorni(int giorni);

  /// No description provided for @passphrase.
  ///
  /// In it, this message translates to:
  /// **'Passphrase'**
  String get passphrase;

  /// No description provided for @ripetiPassphrase.
  ///
  /// In it, this message translates to:
  /// **'Ripeti la passphrase'**
  String get ripetiPassphrase;

  /// No description provided for @passphraseSpiegazione.
  ///
  /// In it, this message translates to:
  /// **'Serve per ripristinare il backup: se la perdi, il backup non si apre più.'**
  String get passphraseSpiegazione;

  /// No description provided for @passphraseCorta.
  ///
  /// In it, this message translates to:
  /// **'La passphrase deve avere almeno 8 caratteri'**
  String get passphraseCorta;

  /// No description provided for @passphraseDiverse.
  ///
  /// In it, this message translates to:
  /// **'Le due passphrase sono diverse'**
  String get passphraseDiverse;

  /// No description provided for @passphraseNuovoBackup.
  ///
  /// In it, this message translates to:
  /// **'Passphrase per questo backup'**
  String get passphraseNuovoBackup;

  /// No description provided for @passphraseDelBackup.
  ///
  /// In it, this message translates to:
  /// **'Passphrase del backup'**
  String get passphraseDelBackup;

  /// No description provided for @passphraseErrata.
  ///
  /// In it, this message translates to:
  /// **'Passphrase sbagliata, oppure il file è danneggiato'**
  String get passphraseErrata;

  /// No description provided for @scegliCartellaBackup.
  ///
  /// In it, this message translates to:
  /// **'Scegli la cartella dei backup'**
  String get scegliCartellaBackup;

  /// No description provided for @scegliCartella.
  ///
  /// In it, this message translates to:
  /// **'Scegli la cartella'**
  String get scegliCartella;

  /// No description provided for @nessunaCartella.
  ///
  /// In it, this message translates to:
  /// **'Nessuna cartella scelta'**
  String get nessunaCartella;

  /// No description provided for @ripristina.
  ///
  /// In it, this message translates to:
  /// **'Ripristina'**
  String get ripristina;

  /// No description provided for @ripristinaTitolo.
  ///
  /// In it, this message translates to:
  /// **'Ripristinare il backup?'**
  String get ripristinaTitolo;

  /// No description provided for @ripristinaTesto.
  ///
  /// In it, this message translates to:
  /// **'I dati attuali vengono sostituiti da quelli di {file}. I telefoni si riallineano da soli alla prossima sync. Spegni il PC da cui viene il backup, se è un altro.'**
  String ripristinaTesto(String file);

  /// No description provided for @tor.
  ///
  /// In it, this message translates to:
  /// **'Tor'**
  String get tor;

  /// No description provided for @torIncluso.
  ///
  /// In it, this message translates to:
  /// **'Si usa il Tor incluso nel programma.'**
  String get torIncluso;

  /// No description provided for @torEsterno.
  ///
  /// In it, this message translates to:
  /// **'Si usa un Tor esterno: {percorso}'**
  String torEsterno(String percorso);

  /// No description provided for @scegliTorEsterno.
  ///
  /// In it, this message translates to:
  /// **'Usa un tor esterno…'**
  String get scegliTorEsterno;

  /// No description provided for @usaTorIncluso.
  ///
  /// In it, this message translates to:
  /// **'Torna al Tor incluso'**
  String get usaTorIncluso;

  /// No description provided for @torEsternoImpostato.
  ///
  /// In it, this message translates to:
  /// **'Vale dal prossimo avvio del programma'**
  String get torEsternoImpostato;

  /// No description provided for @identita.
  ///
  /// In it, this message translates to:
  /// **'Identità'**
  String get identita;

  /// No description provided for @reimpostaIdentita.
  ///
  /// In it, this message translates to:
  /// **'Reimposta l\'identità'**
  String get reimpostaIdentita;

  /// No description provided for @reimpostaIdentitaTitolo.
  ///
  /// In it, this message translates to:
  /// **'Reimpostare l\'identità?'**
  String get reimpostaIdentitaTitolo;

  /// No description provided for @reimpostaIdentitaTesto.
  ///
  /// In it, this message translates to:
  /// **'Serve solo se la chiave del coach è stata compromessa. L\'indirizzo cambia, tutti i telefoni vengono scollegati e ogni atleta dovrà ricollegarsi con un nuovo invito.'**
  String get reimpostaIdentitaTesto;

  /// No description provided for @reimpostaIdentitaConfermaTitolo.
  ///
  /// In it, this message translates to:
  /// **'Ne sei sicuro?'**
  String get reimpostaIdentitaConfermaTitolo;

  /// No description provided for @reimpostaIdentitaConfermaTesto.
  ///
  /// In it, this message translates to:
  /// **'Non si può annullare.'**
  String get reimpostaIdentitaConfermaTesto;

  /// No description provided for @identitaReimpostata.
  ///
  /// In it, this message translates to:
  /// **'Identità reimpostata: crea nuovi inviti per gli atleti'**
  String get identitaReimpostata;

  /// No description provided for @giaAvviato.
  ///
  /// In it, this message translates to:
  /// **'Open Coach risulta già aperto su questo PC, ma non risponde. Chiudilo dal Task Manager e riaprilo.'**
  String get giaAvviato;

  /// No description provided for @identitaIllegibile.
  ///
  /// In it, this message translates to:
  /// **'La chiave del coach non si può leggere: il portachiavi del sistema potrebbe essere stato azzerato.'**
  String get identitaIllegibile;

  /// No description provided for @recuperoDaBackup.
  ///
  /// In it, this message translates to:
  /// **'Puoi ripristinare un backup: l\'indirizzo resta lo stesso e gli atleti non devono riabbinarsi.'**
  String get recuperoDaBackup;

  /// No description provided for @nessunFile.
  ///
  /// In it, this message translates to:
  /// **'Nessun file scelto'**
  String get nessunFile;

  /// No description provided for @scegliFile.
  ///
  /// In it, this message translates to:
  /// **'Scegli il file'**
  String get scegliFile;

  /// No description provided for @recuperoNuovaIdentita.
  ///
  /// In it, this message translates to:
  /// **'Senza backup puoi creare una nuova identità: atleti, schede e allenamenti restano, ma ogni atleta dovrà ricollegarsi con un nuovo invito.'**
  String get recuperoNuovaIdentita;

  /// No description provided for @creaNuovaIdentita.
  ///
  /// In it, this message translates to:
  /// **'Crea una nuova identità'**
  String get creaNuovaIdentita;

  /// No description provided for @chiudiProgramma.
  ///
  /// In it, this message translates to:
  /// **'Chiudi il programma'**
  String get chiudiProgramma;

  /// No description provided for @schedaChat.
  ///
  /// In it, this message translates to:
  /// **'Chat'**
  String get schedaChat;

  /// No description provided for @chatVuota.
  ///
  /// In it, this message translates to:
  /// **'Nessun messaggio. L\'atleta riceve i tuoi messaggi alla sua prossima sincronizzazione e può risponderti, anche con il video di una serie.'**
  String get chatVuota;

  /// No description provided for @chatAppVecchia.
  ///
  /// In it, this message translates to:
  /// **'L\'app dell\'atleta è la {versione}: per vedere la chat deve aggiornarla alla 1.3.0.'**
  String chatAppVecchia(String versione);

  /// No description provided for @scriviMessaggio.
  ///
  /// In it, this message translates to:
  /// **'Scrivi un messaggio'**
  String get scriviMessaggio;

  /// No description provided for @inviaMessaggio.
  ///
  /// In it, this message translates to:
  /// **'Invia'**
  String get inviaMessaggio;

  /// No description provided for @videoSerie.
  ///
  /// In it, this message translates to:
  /// **'{esercizio}, serie {serie}'**
  String videoSerie(String esercizio, int serie);

  /// No description provided for @videoDurata.
  ///
  /// In it, this message translates to:
  /// **'Video di {secondi} s'**
  String videoDurata(int secondi);

  /// No description provided for @guardaVideo.
  ///
  /// In it, this message translates to:
  /// **'Guarda'**
  String get guardaVideo;

  /// No description provided for @eliminaVideo.
  ///
  /// In it, this message translates to:
  /// **'Elimina il video'**
  String get eliminaVideo;

  /// No description provided for @eliminaVideoDomanda.
  ///
  /// In it, this message translates to:
  /// **'Eliminare il video dal PC? Il messaggio resta, ma il video non si potrà più guardare.'**
  String get eliminaVideoDomanda;

  /// No description provided for @videoEliminato.
  ///
  /// In it, this message translates to:
  /// **'Video eliminato'**
  String get videoEliminato;

  /// No description provided for @videoNonDisponibile.
  ///
  /// In it, this message translates to:
  /// **'Video non disponibile'**
  String get videoNonDisponibile;

  /// No description provided for @videoNonAperto.
  ///
  /// In it, this message translates to:
  /// **'Non riesco ad aprire il video: {errore}'**
  String videoNonAperto(String errore);

  /// No description provided for @notificaMessaggio.
  ///
  /// In it, this message translates to:
  /// **'{nome} ti ha scritto'**
  String notificaMessaggio(String nome);

  /// No description provided for @notificaVideo.
  ///
  /// In it, this message translates to:
  /// **'{nome} ti ha mandato un video'**
  String notificaVideo(String nome);

  /// No description provided for @apriConAltroProgramma.
  ///
  /// In it, this message translates to:
  /// **'Apri con un altro programma'**
  String get apriConAltroProgramma;

  /// No description provided for @videoNonRiproducibile.
  ///
  /// In it, this message translates to:
  /// **'Non riesco a riprodurre il video qui ({errore}). Puoi aprirlo con un altro programma, con il tasto in alto.'**
  String videoNonRiproducibile(String errore);

  /// No description provided for @pausa.
  ///
  /// In it, this message translates to:
  /// **'Pausa'**
  String get pausa;

  /// No description provided for @riproduci.
  ///
  /// In it, this message translates to:
  /// **'Riproduci'**
  String get riproduci;
}

class _TestiDelegate extends LocalizationsDelegate<Testi> {
  const _TestiDelegate();

  @override
  Future<Testi> load(Locale locale) {
    return SynchronousFuture<Testi>(lookupTesti(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['it'].contains(locale.languageCode);

  @override
  bool shouldReload(_TestiDelegate old) => false;
}

Testi lookupTesti(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'it':
      return TestiIt();
  }

  throw FlutterError(
    'Testi.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
