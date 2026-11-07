/// Nucleo dell'app dell'atleta di Open Coach (specifiche v1, §5.3,
/// §7.3–§7.5, §8.2, §8.4, §10.2): archivio locale, abbinamento, coda dei log
/// e sincronizzazione, senza interfaccia e senza Flutter.
library;

export 'src/abbinamento.dart'
    show
        AvanzamentoAbbinamento,
        FaseAbbinamento,
        InvitoLetto,
        OsservatoreAbbinamento,
        attesaMassimaCoach;
export 'src/archivio.dart';
export 'src/cassaforte.dart';
export 'src/chat.dart' show ChatCoach, MessaggioChat, StatoMessaggio, cancellaMetadatiMp4, compattaMp4;
export 'src/collegamenti.dart';
export 'src/diario.dart';
export 'src/errori.dart';
export 'src/esecuzione.dart';
export 'src/modelli.dart'
    show
        CoachCollegato,
        EsitoSync,
        LogAllenamento,
        SchedaRicevuta,
        StatoCollegamento;
export 'src/nucleo.dart';
export 'src/pesi.dart' show PesoDelGiorno, RegistroPesi;
export 'src/pianificatore.dart';
export 'src/problemi.dart';
export 'src/questionari.dart';
export 'src/schede.dart';
export 'src/sincronizzazione.dart';
export 'package:trasporto_tor/trasporto_tor.dart' hide Guasto, TipoGuasto, classifica;
