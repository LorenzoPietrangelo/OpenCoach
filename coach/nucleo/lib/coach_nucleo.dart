/// Nucleo del programma del coach di Open Coach (specifiche v1, §5–§9):
/// archivio, abbinamento, sincronizzazione, server HTTP e gestione di Tor.
library;

export 'src/allenamenti.dart' show EsercizioStorico, GestioneAllenamenti, MisuraEsercizio, SettimanaStorico, StoricoAtleta, rirDaTesto, stima1Rm;
export 'src/archivio.dart' show Archivio, Impostazioni;
export 'src/chat.dart' show GestioneMessaggi;
export 'src/atleti.dart' show GestioneAtleti;
export 'src/backup.dart';
export 'src/dispositivi.dart' show GestioneDispositivi;
export 'src/errori.dart';
export 'src/esportazioni.dart' show GestioneEsportazioni;
export 'src/eventi.dart';
export 'src/identita.dart';
export 'src/inviti.dart' show GestioneInviti;
export 'src/libreria.dart' show GestioneLibreria, chiaveEsercizio;
export 'src/pesi.dart' show GestionePesi;
export 'src/questionari.dart' show GestioneQuestionari, QuestionarioNonValido;
export 'src/modelli.dart';
export 'src/nucleo.dart';
export 'src/portachiavi.dart';
export 'src/programma_coach.dart';
export 'src/registro.dart';
export 'src/schede.dart' show GestioneSchede;
export 'src/server_http.dart';
export 'src/tor/controllo_tor.dart';
export 'src/tor/processo_tor.dart';
export 'src/tor/servizio_onion.dart';
