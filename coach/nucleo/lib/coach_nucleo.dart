/// Nucleo del programma del coach di Open Coach (specifiche v1, §5–§9):
/// archivio, abbinamento, sincronizzazione, server HTTP e gestione di Tor.
library;

export 'src/allenamenti.dart' show GestioneAllenamenti;
export 'src/archivio.dart' show Archivio, Impostazioni;
export 'src/atleti.dart' show GestioneAtleti;
export 'src/backup.dart';
export 'src/dispositivi.dart' show GestioneDispositivi;
export 'src/errori.dart';
export 'src/esportazioni.dart' show GestioneEsportazioni;
export 'src/eventi.dart';
export 'src/identita.dart';
export 'src/inviti.dart' show GestioneInviti;
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
