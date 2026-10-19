import 'problemi.dart';

/// L'abbinamento non è riuscito: [problema] dice perché e quale messaggio
/// mostrare all'atleta (§5.4).
class ErroreAbbinamento implements Exception {
  const ErroreAbbinamento(this.problema);

  final ProblemaAbbinamento problema;

  String get messaggio => problema.messaggio;

  @override
  String toString() => 'ErroreAbbinamento(${problema.name})';
}

/// Il log non rispetta il formato del protocollo (§8.2): [errori] elenca i
/// campi da correggere.
class LogNonValido implements Exception {
  const LogNonValido(this.errori);

  final List<String> errori;

  @override
  String toString() => 'LogNonValido: ${errori.join('; ')}';
}

/// Operazione che non si può eseguire nello stato attuale, per esempio
/// scrivere un log per un coach che ha chiuso il collegamento.
class OperazioneNonAmmessa implements Exception {
  const OperazioneNonAmmessa(this.messaggio);

  final String messaggio;

  @override
  String toString() => 'OperazioneNonAmmessa: $messaggio';
}
