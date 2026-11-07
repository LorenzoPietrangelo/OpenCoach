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
  /// **'OpenCoach Coach'**
  String get nomeApp;

  /// No description provided for @annulla.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get annulla;

  /// No description provided for @riprova.
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get riprova;

  /// No description provided for @sconosciuto.
  ///
  /// In it, this message translates to:
  /// **'—'**
  String get sconosciuto;

  /// No description provided for @bloccoMotivo.
  ///
  /// In it, this message translates to:
  /// **'Sblocca per vedere i dati dei tuoi atleti'**
  String get bloccoMotivo;

  /// No description provided for @bloccoTitolo.
  ///
  /// In it, this message translates to:
  /// **'App bloccata'**
  String get bloccoTitolo;

  /// No description provided for @bloccoSpiegazione.
  ///
  /// In it, this message translates to:
  /// **'Qui ci sono i dati dei tuoi atleti.'**
  String get bloccoSpiegazione;

  /// No description provided for @bloccoSblocca.
  ///
  /// In it, this message translates to:
  /// **'Sblocca'**
  String get bloccoSblocca;

  /// No description provided for @bloccoAssente.
  ///
  /// In it, this message translates to:
  /// **'Il telefono non ha un blocco schermo: chi lo prende in mano vede i dati dei tuoi atleti. Impostalo nelle impostazioni del telefono.'**
  String get bloccoAssente;

  /// No description provided for @collegaTitolo.
  ///
  /// In it, this message translates to:
  /// **'Collega il telefono al PC'**
  String get collegaTitolo;

  /// No description provided for @collegaSpiegazione.
  ///
  /// In it, this message translates to:
  /// **'Sul PC apri Open Coach, vai in Impostazioni, Il mio telefono, e scegli «Collega il mio telefono». Poi inquadra il QR.'**
  String get collegaSpiegazione;

  /// No description provided for @collegaAvviso.
  ///
  /// In it, this message translates to:
  /// **'L\'app funziona mentre il PC è acceso con il programma aperto: i dati restano lì.'**
  String get collegaAvviso;

  /// No description provided for @collegaInquadra.
  ///
  /// In it, this message translates to:
  /// **'Inquadra il QR'**
  String get collegaInquadra;

  /// No description provided for @scansioneTitolo.
  ///
  /// In it, this message translates to:
  /// **'Inquadra il QR'**
  String get scansioneTitolo;

  /// No description provided for @scansioneAiuto.
  ///
  /// In it, this message translates to:
  /// **'Inquadra il QR che vedi sul PC'**
  String get scansioneAiuto;

  /// No description provided for @scansioneAltroCodice.
  ///
  /// In it, this message translates to:
  /// **'Questo non è il QR per collegare il telefono del coach.'**
  String get scansioneAltroCodice;

  /// No description provided for @scansioneSenzaFotocamera.
  ///
  /// In it, this message translates to:
  /// **'La fotocamera non si apre. Controlla che l\'app abbia il permesso nelle impostazioni del telefono.'**
  String get scansioneSenzaFotocamera;

  /// No description provided for @faseAvvioTor.
  ///
  /// In it, this message translates to:
  /// **'Avvio di Tor…'**
  String get faseAvvioTor;

  /// No description provided for @faseRicercaPc.
  ///
  /// In it, this message translates to:
  /// **'Cerco il tuo PC…'**
  String get faseRicercaPc;

  /// No description provided for @faseAttesaPc.
  ///
  /// In it, this message translates to:
  /// **'Il PC non si trova ancora. Dopo aver creato il QR può volerci un paio di minuti: riprovo da solo…'**
  String get faseAttesaPc;

  /// No description provided for @faseCollegamento.
  ///
  /// In it, this message translates to:
  /// **'Collegamento…'**
  String get faseCollegamento;

  /// No description provided for @confermaTitolo.
  ///
  /// In it, this message translates to:
  /// **'Collegarti a {nome}?'**
  String confermaTitolo(String nome);

  /// No description provided for @confermaTesto.
  ///
  /// In it, this message translates to:
  /// **'Questo telefono vedrà i dati di tutti i tuoi atleti e potrà scrivere loro. Se c\'era un altro telefono collegato, smette di funzionare.'**
  String get confermaTesto;

  /// No description provided for @confermaAzione.
  ///
  /// In it, this message translates to:
  /// **'Collega'**
  String get confermaAzione;

  /// No description provided for @erroreCodice.
  ///
  /// In it, this message translates to:
  /// **'Questo non è il QR per collegare il telefono del coach. Lo trovi nelle impostazioni del programma sul PC.'**
  String get erroreCodice;

  /// No description provided for @erroreAggiorna.
  ///
  /// In it, this message translates to:
  /// **'Il programma sul PC e questa app hanno versioni diverse: aggiorna entrambi all\'ultima versione.'**
  String get erroreAggiorna;

  /// No description provided for @erroreQr.
  ///
  /// In it, this message translates to:
  /// **'Questo QR non vale più. Creane uno nuovo sul PC.'**
  String get erroreQr;

  /// No description provided for @erroreQrInUso.
  ///
  /// In it, this message translates to:
  /// **'Questo QR è già stato usato da un altro telefono. Creane uno nuovo sul PC.'**
  String get erroreQrInUso;

  /// No description provided for @erroreTor.
  ///
  /// In it, this message translates to:
  /// **'Tor non parte: controlla la connessione. Alcune reti lo bloccano, prova con un\'altra.'**
  String get erroreTor;

  /// No description provided for @errorePc.
  ///
  /// In it, this message translates to:
  /// **'Il PC non si trova. Deve essere acceso con il programma aperto.'**
  String get errorePc;

  /// No description provided for @erroreInatteso.
  ///
  /// In it, this message translates to:
  /// **'Qualcosa è andato storto. Riprova.'**
  String get erroreInatteso;

  /// No description provided for @atletiTitolo.
  ///
  /// In it, this message translates to:
  /// **'I tuoi atleti'**
  String get atletiTitolo;

  /// No description provided for @atletiVuoto.
  ///
  /// In it, this message translates to:
  /// **'Non hai ancora atleti. Li crei dal programma sul PC.'**
  String get atletiVuoto;

  /// No description provided for @atletiCaricamento.
  ///
  /// In it, this message translates to:
  /// **'Cerco il tuo PC…'**
  String get atletiCaricamento;

  /// No description provided for @atletaSenzaTelefono.
  ///
  /// In it, this message translates to:
  /// **'Telefono non collegato'**
  String get atletaSenzaTelefono;

  /// No description provided for @atletaNessunMessaggio.
  ///
  /// In it, this message translates to:
  /// **'Nessun messaggio'**
  String get atletaNessunMessaggio;

  /// No description provided for @anteprimaTu.
  ///
  /// In it, this message translates to:
  /// **'Tu: {testo}'**
  String anteprimaTu(String testo);

  /// No description provided for @anteprimaVideo.
  ///
  /// In it, this message translates to:
  /// **'Video'**
  String get anteprimaVideo;

  /// No description provided for @risposteNuove.
  ///
  /// In it, this message translates to:
  /// **'{numero, plural, =1{1 questionario da leggere} other{{numero} questionari da leggere}}'**
  String risposteNuove(int numero);

  /// No description provided for @problemaInCollegamento.
  ///
  /// In it, this message translates to:
  /// **'Sto finendo di collegare il telefono: il PC può metterci qualche minuto.'**
  String get problemaInCollegamento;

  /// No description provided for @problemaIrraggiungibile.
  ///
  /// In it, this message translates to:
  /// **'Il PC non risponde. Deve essere acceso con il programma aperto. I messaggi che scrivi partono appena torna.'**
  String get problemaIrraggiungibile;

  /// No description provided for @problemaTor.
  ///
  /// In it, this message translates to:
  /// **'Tor non parte: controlla la connessione. I messaggi che scrivi partono appena torna.'**
  String get problemaTor;

  /// No description provided for @problemaChiave.
  ///
  /// In it, this message translates to:
  /// **'Il PC non accetta questo telefono. Se l\'hai scollegato dal PC, scollegalo anche qui e ricollegalo.'**
  String get problemaChiave;

  /// No description provided for @problemaVersione.
  ///
  /// In it, this message translates to:
  /// **'Il programma sul PC e questa app hanno versioni diverse: aggiorna entrambi.'**
  String get problemaVersione;

  /// No description provided for @problemaOccupato.
  ///
  /// In it, this message translates to:
  /// **'Il PC ha molto da fare: riprovo tra poco.'**
  String get problemaOccupato;

  /// No description provided for @problemaInatteso.
  ///
  /// In it, this message translates to:
  /// **'Il PC ha risposto in modo inatteso: riprovo tra poco.'**
  String get problemaInatteso;

  /// No description provided for @problemaDati.
  ///
  /// In it, this message translates to:
  /// **'Non riesco a leggere questi dati dal PC.'**
  String get problemaDati;

  /// No description provided for @sezioneChat.
  ///
  /// In it, this message translates to:
  /// **'Chat'**
  String get sezioneChat;

  /// No description provided for @sezioneAllenamenti.
  ///
  /// In it, this message translates to:
  /// **'Allenamenti'**
  String get sezioneAllenamenti;

  /// No description provided for @sezionePeso.
  ///
  /// In it, this message translates to:
  /// **'Peso'**
  String get sezionePeso;

  /// No description provided for @sezioneQuestionari.
  ///
  /// In it, this message translates to:
  /// **'Questionari'**
  String get sezioneQuestionari;

  /// No description provided for @sezioneScheda.
  ///
  /// In it, this message translates to:
  /// **'Scheda'**
  String get sezioneScheda;

  /// No description provided for @chatVuota.
  ///
  /// In it, this message translates to:
  /// **'Nessun messaggio. Scrivi tu per primo.'**
  String get chatVuota;

  /// No description provided for @chatScrivi.
  ///
  /// In it, this message translates to:
  /// **'Scrivi un messaggio'**
  String get chatScrivi;

  /// No description provided for @chatInvia.
  ///
  /// In it, this message translates to:
  /// **'Invia'**
  String get chatInvia;

  /// No description provided for @chatPrecedenti.
  ///
  /// In it, this message translates to:
  /// **'Messaggi precedenti'**
  String get chatPrecedenti;

  /// No description provided for @chatInAttesa.
  ///
  /// In it, this message translates to:
  /// **'In attesa del PC'**
  String get chatInAttesa;

  /// No description provided for @chatRifiutato.
  ///
  /// In it, this message translates to:
  /// **'Il PC non l\'ha accettato. Tocca per toglierlo.'**
  String get chatRifiutato;

  /// No description provided for @chatVideo.
  ///
  /// In it, this message translates to:
  /// **'Video di {secondi} s: si guarda dal programma sul PC'**
  String chatVideo(int secondi);

  /// No description provided for @chatVideoEliminato.
  ///
  /// In it, this message translates to:
  /// **'Video eliminato dal PC'**
  String get chatVideoEliminato;

  /// No description provided for @chatRiferimento.
  ///
  /// In it, this message translates to:
  /// **'{esercizio}, serie {serie}'**
  String chatRiferimento(String esercizio, int serie);

  /// No description provided for @allenamentiVuoto.
  ///
  /// In it, this message translates to:
  /// **'Nessun allenamento ricevuto.'**
  String get allenamentiVuoto;

  /// No description provided for @allenamentiAltri.
  ///
  /// In it, this message translates to:
  /// **'Allenamenti precedenti'**
  String get allenamentiAltri;

  /// No description provided for @allenamentoSerie.
  ///
  /// In it, this message translates to:
  /// **'{fatte} di {totali} serie'**
  String allenamentoSerie(int fatte, int totali);

  /// No description provided for @allenamentoDurata.
  ///
  /// In it, this message translates to:
  /// **'{minuti} min'**
  String allenamentoDurata(String minuti);

  /// No description provided for @allenamentoSforzo.
  ///
  /// In it, this message translates to:
  /// **'Sforzo {valore}'**
  String allenamentoSforzo(String valore);

  /// No description provided for @serieNumero.
  ///
  /// In it, this message translates to:
  /// **'Serie {numero}'**
  String serieNumero(int numero);

  /// No description provided for @serieNonFatta.
  ///
  /// In it, this message translates to:
  /// **'non fatta'**
  String get serieNonFatta;

  /// No description provided for @pesoVuoto.
  ///
  /// In it, this message translates to:
  /// **'L\'atleta non condivide il peso con te.'**
  String get pesoVuoto;

  /// No description provided for @pesoUltimo.
  ///
  /// In it, this message translates to:
  /// **'Ultimo peso'**
  String get pesoUltimo;

  /// No description provided for @pesoMedia.
  ///
  /// In it, this message translates to:
  /// **'Media 7 giorni'**
  String get pesoMedia;

  /// No description provided for @pesoDifferenza.
  ///
  /// In it, this message translates to:
  /// **'Rispetto ai 7 giorni prima'**
  String get pesoDifferenza;

  /// No description provided for @pesoValore.
  ///
  /// In it, this message translates to:
  /// **'{kg} kg'**
  String pesoValore(String kg);

  /// No description provided for @questionariVuoto.
  ///
  /// In it, this message translates to:
  /// **'Nessun questionario mandato.'**
  String get questionariVuoto;

  /// No description provided for @questionarioInAttesa.
  ///
  /// In it, this message translates to:
  /// **'Mandato il {quando}, senza risposta'**
  String questionarioInAttesa(String quando);

  /// No description provided for @questionarioAnnullato.
  ///
  /// In it, this message translates to:
  /// **'Annullato'**
  String get questionarioAnnullato;

  /// No description provided for @questionarioRisposto.
  ///
  /// In it, this message translates to:
  /// **'Risposto il {quando}'**
  String questionarioRisposto(String quando);

  /// No description provided for @questionarioNuovo.
  ///
  /// In it, this message translates to:
  /// **'Nuovo'**
  String get questionarioNuovo;

  /// No description provided for @questionarioNessunaRisposta.
  ///
  /// In it, this message translates to:
  /// **'Nessuna risposta'**
  String get questionarioNessunaRisposta;

  /// No description provided for @questionarioFoto.
  ///
  /// In it, this message translates to:
  /// **'Foto'**
  String get questionarioFoto;

  /// No description provided for @questionarioFotoErrore.
  ///
  /// In it, this message translates to:
  /// **'Foto non disponibile'**
  String get questionarioFotoErrore;

  /// No description provided for @schedaNote.
  ///
  /// In it, this message translates to:
  /// **'Le tue note'**
  String get schedaNote;

  /// No description provided for @schedaNoteVuote.
  ///
  /// In it, this message translates to:
  /// **'Nessuna nota. Le scrivi dal programma sul PC.'**
  String get schedaNoteVuote;

  /// No description provided for @schedaTelefono.
  ///
  /// In it, this message translates to:
  /// **'Telefono dell\'atleta'**
  String get schedaTelefono;

  /// No description provided for @schedaUltimoContatto.
  ///
  /// In it, this message translates to:
  /// **'Ultimo contatto: {quando}'**
  String schedaUltimoContatto(String quando);

  /// No description provided for @schedaMaiSincronizzato.
  ///
  /// In it, this message translates to:
  /// **'Non ha ancora sincronizzato'**
  String get schedaMaiSincronizzato;

  /// No description provided for @schedaAllenamenti.
  ///
  /// In it, this message translates to:
  /// **'Allenamenti ricevuti: {numero}'**
  String schedaAllenamenti(int numero);

  /// No description provided for @schedaSchede.
  ///
  /// In it, this message translates to:
  /// **'Schede'**
  String get schedaSchede;

  /// No description provided for @schedaNessuna.
  ///
  /// In it, this message translates to:
  /// **'Nessuna scheda.'**
  String get schedaNessuna;

  /// No description provided for @schedaAiuto.
  ///
  /// In it, this message translates to:
  /// **'Le schede si scrivono dal programma sul PC.'**
  String get schedaAiuto;

  /// No description provided for @schedaBozza.
  ///
  /// In it, this message translates to:
  /// **'Bozza'**
  String get schedaBozza;

  /// No description provided for @schedaArchiviata.
  ///
  /// In it, this message translates to:
  /// **'Archiviata'**
  String get schedaArchiviata;

  /// No description provided for @schedaPubblicata.
  ///
  /// In it, this message translates to:
  /// **'Revisione {revisione}'**
  String schedaPubblicata(int revisione);

  /// No description provided for @schedaRicevuta.
  ///
  /// In it, this message translates to:
  /// **'Revisione {revisione}, ricevuta il {quando}'**
  String schedaRicevuta(int revisione, String quando);

  /// No description provided for @schedaNonRicevuta.
  ///
  /// In it, this message translates to:
  /// **'Revisione {revisione}, non ancora ricevuta'**
  String schedaNonRicevuta(int revisione);

  /// No description provided for @impostazioniTitolo.
  ///
  /// In it, this message translates to:
  /// **'Impostazioni'**
  String get impostazioniTitolo;

  /// No description provided for @impostazioniPc.
  ///
  /// In it, this message translates to:
  /// **'PC collegato'**
  String get impostazioniPc;

  /// No description provided for @impostazioniProgramma.
  ///
  /// In it, this message translates to:
  /// **'Programma di {nome}'**
  String impostazioniProgramma(String nome);

  /// No description provided for @impostazioniControlli.
  ///
  /// In it, this message translates to:
  /// **'Controlli con l\'app chiusa'**
  String get impostazioniControlli;

  /// No description provided for @impostazioniControlliAiuto.
  ///
  /// In it, this message translates to:
  /// **'Senza un server non ci sono notifiche push: l\'app guarda se ci sono novità a intervalli. Android può rimandare i controlli.'**
  String get impostazioniControlliAiuto;

  /// No description provided for @controlliDisattivati.
  ///
  /// In it, this message translates to:
  /// **'Disattivati'**
  String get controlliDisattivati;

  /// No description provided for @controlliOgni.
  ///
  /// In it, this message translates to:
  /// **'Ogni {minuti} minuti'**
  String controlliOgni(int minuti);

  /// No description provided for @batteriaLimitata.
  ///
  /// In it, this message translates to:
  /// **'La batteria dell\'app è «Limitata»: con l\'app chiusa i controlli non partono.'**
  String get batteriaLimitata;

  /// No description provided for @apriImpostazioniTelefono.
  ///
  /// In it, this message translates to:
  /// **'Apri le impostazioni'**
  String get apriImpostazioniTelefono;

  /// No description provided for @impostazioniBlocco.
  ///
  /// In it, this message translates to:
  /// **'Blocco dell\'app'**
  String get impostazioniBlocco;

  /// No description provided for @impostazioniBloccoAttivo.
  ///
  /// In it, this message translates to:
  /// **'L\'app chiede l\'impronta o il blocco schermo all\'apertura e dopo 5 minuti in background.'**
  String get impostazioniBloccoAttivo;

  /// No description provided for @scollegaTitolo.
  ///
  /// In it, this message translates to:
  /// **'Scollegare questo telefono?'**
  String get scollegaTitolo;

  /// No description provided for @scollegaTesto.
  ///
  /// In it, this message translates to:
  /// **'L\'app dimentica il PC e i messaggi ancora in coda. Per ricollegarla servirà un nuovo QR.'**
  String get scollegaTesto;

  /// No description provided for @scollegaAzione.
  ///
  /// In it, this message translates to:
  /// **'Scollega questo telefono'**
  String get scollegaAzione;

  /// No description provided for @notificaMessaggi.
  ///
  /// In it, this message translates to:
  /// **'{numero, plural, =1{1 messaggio nuovo} other{{numero} messaggi nuovi}}'**
  String notificaMessaggi(int numero);

  /// No description provided for @notificaRisposte.
  ///
  /// In it, this message translates to:
  /// **'{numero, plural, =1{1 questionario compilato} other{{numero} questionari compilati}}'**
  String notificaRisposte(int numero);
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
