import 'dart:typed_data';

import 'modelli.dart';

/// Da dove le schermate leggono i dati del coach. Oggi c'è solo [FonteRemota],
/// il telefono come telecomando del PC. Tutta l'app passa da qui, così un
/// giorno potrà leggere da un archivio sul telefono senza cambiare le schermate
/// (§14).
abstract interface class FonteDatiCoach {
  Future<ElencoAtleti> atleti();

  Future<DettaglioAtleta> atleta(String id);

  /// Gli ultimi messaggi prima di [prima], dal più vecchio.
  Future<Pagina<MessaggioChat>> messaggi(String atletaId, {String? prima});

  /// Idempotente su [id]: rimandarlo non crea un doppione.
  Future<void> inviaMessaggio(String atletaId, String id, String testo);

  Future<void> segnaLetti(String atletaId);

  /// Gli allenamenti dopo [prima], dal più recente.
  Future<Pagina<AllenamentoAtleta>> allenamenti(String atletaId, {String? prima});

  Future<List<PesoGiorno>> pesi(String atletaId);

  /// L'obiettivo del cibo e le giornate prima del giorno [prima].
  Future<CiboAtleta> cibo(String atletaId, {String? prima});

  Future<List<QuestionarioAtleta>> questionari(String atletaId);

  Future<void> segnaQuestionarioLetto(String id);

  Future<Uint8List> foto(String id);

  /// Vero appena i dati sono diversi da quelli di [impronta], falso dopo
  /// un'attesa senza novità.
  Future<bool> attendi(String impronta);

  /// Il telefono ha finito di collegarsi (§16.2).
  Future<void> confermaCollegamento();

  /// Il coach scollega il telefono dall'app.
  Future<void> scollega();

  /// Smette di usare la rete: l'app è in background.
  Future<void> fermaRete();
}

class ElencoAtleti {
  const ElencoAtleti(this.atleti, this.impronta);

  final List<RiepilogoAtleta> atleti;

  /// Riassunto dei dati: vedi [FonteDatiCoach.attendi].
  final String impronta;
}

class Pagina<T> {
  const Pagina(this.elementi, {required this.altri});

  final List<T> elementi;

  /// Ce ne sono altri più vecchi.
  final bool altri;
}

/// Perché una richiesta non è riuscita.
enum ProblemaCoach {
  /// Il telefono è offline o la rete blocca Tor.
  torNonParte,

  /// Il PC è spento, sospeso o non ancora raggiungibile.
  irraggiungibile,

  /// Il servizio non accetta la chiave di questo telefono: può non essere
  /// ancora pubblicata, o il telefono è stato scollegato.
  chiaveRifiutata,

  /// Il PC ha scollegato questo telefono.
  revocato,

  /// Il programma sul PC è troppo vecchio per l'app, o il contrario.
  versioneDiversa,

  /// Il PC ha rifiutato questa richiesta: ritentarla non serve.
  rifiutata,

  /// Il PC ha troppo da fare: si riprova tra poco.
  occupato,

  /// Il PC ha risposto qualcosa di inatteso.
  inatteso,
}

class ErroreCoach implements Exception {
  const ErroreCoach(this.problema);

  final ProblemaCoach problema;

  @override
  String toString() => 'ErroreCoach(${problema.name})';
}
