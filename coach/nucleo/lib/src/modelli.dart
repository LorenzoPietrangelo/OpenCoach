import 'dart:convert';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'tempo.dart';

class Atleta {
  const Atleta({
    required this.id,
    required this.nome,
    required this.note,
    required this.archiviato,
    required this.creatoIl,
  });

  factory Atleta.daRiga(Row r) => Atleta(
    id: r['id'] as String,
    nome: r['nome'] as String,
    note: r['note'] as String,
    archiviato: r['stato'] == 'archiviato',
    creatoIl: leggiIstante(r['creato_il'] as String),
  );

  final String id;
  final String nome;

  /// Note private del coach: non arrivano mai all'atleta.
  final String note;
  final bool archiviato;
  final DateTime creatoIl;
}

class Dispositivo {
  const Dispositivo({
    required this.id,
    required this.atletaId,
    required this.nome,
    required this.piattaforma,
    required this.versioneApp,
    required this.abbinatoIl,
    required this.ultimoContatto,
    required this.ultimaSequenza,
    required this.attivo,
    required this.revocatoIl,
  });

  factory Dispositivo.daRiga(Row r) => Dispositivo(
    id: r['id'] as String,
    atletaId: r['atleta_id'] as String,
    nome: r['nome'] as String,
    piattaforma: r['piattaforma'] as String,
    versioneApp: r['versione_app'] as String,
    abbinatoIl: leggiIstante(r['abbinato_il'] as String),
    ultimoContatto: leggiIstanteFacoltativo(r['ultimo_contatto']),
    ultimaSequenza: r['ultima_sequenza'] as int,
    attivo: r['stato'] == 'attivo',
    revocatoIl: leggiIstanteFacoltativo(r['revocato_il']),
  );

  final String id;
  final String atletaId;
  final String nome;
  final String piattaforma;
  final String versioneApp;
  final DateTime abbinatoIl;
  final DateTime? ultimoContatto;

  /// Sequenza fino alla quale il dispositivo ha confermato di essere
  /// aggiornato.
  final int ultimaSequenza;
  final bool attivo;
  final DateTime? revocatoIl;
}

enum StatoInvito {
  aperto('aperto'),
  inAbbinamento('in_abbinamento'),
  usato('usato'),
  scaduto('scaduto'),
  annullato('annullato');

  const StatoInvito(this.nome);

  /// Nome nell'archivio.
  final String nome;

  static StatoInvito daNome(String nome) =>
      values.firstWhere((s) => s.nome == nome);
}

class Invito {
  const Invito({
    required this.id,
    required this.atletaId,
    required this.stato,
    required this.creatoIl,
    required this.scadeIl,
    required this.uri,
  });

  final String id;
  final String atletaId;
  final StatoInvito stato;
  final DateTime creatoIl;
  final DateTime scadeIl;

  /// Contenuto del QR, disponibile finché l'invito è aperto.
  final UriInvito? uri;
}

/// Atleta con il telefono attivo e l'invito in corso, per l'elenco.
class RiepilogoAtleta {
  const RiepilogoAtleta(this.atleta, this.dispositivo, this.invito);

  final Atleta atleta;
  final Dispositivo? dispositivo;
  final Invito? invito;
}

enum StatoScheda { bozza, pubblicata, archiviata }

class RevisioneScheda {
  const RevisioneScheda({
    required this.numero,
    required this.pubblicataIl,
    required this.ricevutaIl,
  });

  final int numero;

  /// Data e ora di pubblicazione, nel formato del protocollo.
  final String pubblicataIl;

  /// Quando un dispositivo dell'atleta ha confermato di averla ricevuta.
  /// Null se non l'ha ancora ricevuta o se è stata sostituita prima.
  final DateTime? ricevutaIl;
}

/// Scheda vista dal coach: la bozza su cui lavora e le revisioni pubblicate.
class Scheda {
  const Scheda({
    required this.id,
    required this.atletaId,
    required this.stato,
    required this.bozza,
    required this.revisione,
    required this.modificheNonPubblicate,
    required this.creataIl,
    required this.modificataIl,
    required this.revisioni,
  });

  final String id;
  final String atletaId;
  final StatoScheda stato;
  final Map<String, Object?> bozza;

  /// Ultima revisione pubblicata; 0 se la scheda non è mai stata pubblicata.
  final int revisione;
  final bool modificheNonPubblicate;
  final DateTime creataIl;
  final DateTime modificataIl;
  final List<RevisioneScheda> revisioni;

  String get titolo => bozza['titolo'] is String ? bozza['titolo'] as String : '';
}

/// Messaggio della chat tra coach e atleta (§8.7).
class Messaggio {
  const Messaggio({
    required this.id,
    required this.dalCoach,
    required this.testo,
    required this.inviatoIl,
    required this.video,
    required this.riferimento,
    required this.videoEliminato,
    required this.letto,
  });

  final String id;
  final bool dalCoach;
  final String testo;
  final DateTime inviatoIl;

  /// Id, dimensione, parti, impronta e durata del video allegato, se c'è.
  final Map<String, Object?>? video;

  /// L'esercizio e la serie a cui il video si riferisce, se c'è.
  final Map<String, Object?>? riferimento;

  /// Il coach ha eliminato il file del video per fare spazio.
  final bool videoEliminato;
  final bool letto;

  int? get durataVideoS => video?['durata_s'] as int?;
}

/// Modello di questionario scritto dal coach (§8.6, §9.3).
class ModelloQuestionario {
  const ModelloQuestionario({required this.id, required this.contenuto, required this.modificatoIl});

  final String id;

  /// Titolo, descrizione, domande e foto, nel formato del protocollo.
  final Map<String, Object?> contenuto;
  final DateTime modificatoIl;

  String get titolo => contenuto['titolo'] is String ? contenuto['titolo'] as String : '';
}

enum StatoQuestionario { inviato, risposto, annullato }

/// Questionario mandato a un atleta, con le risposte se sono arrivate.
class QuestionarioInviato {
  const QuestionarioInviato({
    required this.id,
    required this.atletaId,
    required this.contenuto,
    required this.inviatoIl,
    required this.stato,
    required this.risposta,
    required this.rispostoIl,
    required this.letto,
  });

  final String id;
  final String atletaId;

  /// Il questionario com'era al momento dell'invio.
  final Map<String, Object?> contenuto;
  final DateTime inviatoIl;
  final StatoQuestionario stato;

  /// Le risposte come le ha mandate l'app (§8.6).
  final Map<String, Object?>? risposta;
  final DateTime? rispostoIl;

  /// Il coach ha aperto le risposte.
  final bool letto;

  String get titolo => contenuto['titolo'] is String ? contenuto['titolo'] as String : '';

  /// Id delle foto allegate, nell'ordine dell'atleta.
  List<String> get foto => [
    if (risposta?['foto'] case final List<Object?> lista)
      for (final id in lista)
        if (id is String) id,
  ];
}

/// Peso corporeo di un giorno, registrato dall'atleta (§8.5).
class PesoDelGiorno {
  const PesoDelGiorno({required this.giorno, required this.kg});

  final DateTime giorno;
  final double kg;
}

/// Esercizio della libreria del coach (§9.3).
class EsercizioLibreria {
  const EsercizioLibreria({
    required this.id,
    required this.nome,
    required this.note,
    required this.video,
  });

  final String id;
  final String nome;

  /// Note proposte quando il coach sceglie l'esercizio in una scheda.
  final String note;

  /// Link https al video, che le schede ricevono alla pubblicazione.
  final String? video;
}

/// Allenamento registrato dall'atleta (log), in sola lettura per il coach.
class Allenamento {
  const Allenamento({
    required this.id,
    required this.atletaId,
    required this.rev,
    required this.contenuto,
    required this.eseguitoIl,
    required this.ricevutoIl,
    required this.revisioneNonAttuale,
  });

  factory Allenamento.daRiga(Row r, {required int? revisioneAttuale}) {
    final contenuto = jsonDecode(r['contenuto'] as String) as Map<String, Object?>;
    final revisioneUsata = contenuto['scheda_revisione'];
    return Allenamento(
      id: r['id'] as String,
      atletaId: r['atleta_id'] as String,
      rev: r['rev'] as int,
      contenuto: contenuto,
      eseguitoIl: analizzaDataOra(contenuto['eseguito_il'])!,
      ricevutoIl: leggiIstante(r['ricevuto_il'] as String),
      revisioneNonAttuale:
          revisioneAttuale != null &&
          revisioneUsata is int &&
          revisioneUsata < revisioneAttuale,
    );
  }

  final String id;
  final String atletaId;
  final int rev;

  /// Il log come l'ha inviato l'app (§8.2).
  final Map<String, Object?> contenuto;
  final DateTime eseguitoIl;
  final DateTime ricevutoIl;

  /// Vero se l'atleta seguiva una revisione della scheda non più attuale.
  final bool revisioneNonAttuale;
}
