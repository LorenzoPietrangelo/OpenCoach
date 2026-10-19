/// Errore da restituire all'app come risposta HTTP (§6.4).
class ErroreHttp implements Exception {
  const ErroreHttp(this.stato, this.codice, {this.messaggio = '', this.riprovaTra});

  final int stato;
  final String codice;
  final String messaggio;
  final Duration? riprovaTra;

  @override
  String toString() => 'ErroreHttp($stato $codice)';
}

/// Operazione del coach che non si può eseguire nello stato attuale.
class OperazioneNonValida implements Exception {
  const OperazioneNonValida(this.messaggio);

  final String messaggio;

  @override
  String toString() => 'OperazioneNonValida: $messaggio';
}

/// La scheda non si può pubblicare: [errori] elenca i campi da correggere.
class SchedaNonValida implements Exception {
  const SchedaNonValida(this.errori);

  final List<String> errori;

  @override
  String toString() => 'SchedaNonValida: ${errori.join('; ')}';
}

/// La chiave d'identità salvata non si può decifrare, per esempio perché il
/// portachiavi del sistema operativo è stato azzerato. Serve un ripristino
/// da backup o una nuova identità.
class IdentitaIllegibile implements Exception {
  const IdentitaIllegibile();

  @override
  String toString() => 'IdentitaIllegibile';
}

/// Il programma è già in esecuzione con la stessa cartella dati.
class ProgrammaGiaAvviato implements Exception {
  const ProgrammaGiaAvviato();

  @override
  String toString() => 'ProgrammaGiaAvviato';
}
