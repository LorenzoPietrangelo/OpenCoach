import 'package:protocollo/protocollo.dart';

import 'abbinamento.dart';
import 'allenamenti.dart';
import 'archivio.dart';
import 'atleti.dart';
import 'contesto.dart';
import 'dispositivi.dart';
import 'errori.dart';
import 'eventi.dart';
import 'inviti.dart';
import 'schede.dart';
import 'sincronizzazione.dart';

/// Il programma del coach senza rete: archivio e regole di abbinamento e
/// sincronizzazione. Il server HTTP e Tor gli stanno attorno.
class NucleoCoach {
  NucleoCoach({
    required Archivio archivio,
    required String indirizzo,
    String versioneProgramma = '1.0.0',
    DateTime Function()? adesso,
    int? budgetPagina,
  }) : contesto = ContestoCoach(
         archivio: archivio,
         indirizzo: indirizzo,
         versioneProgramma: versioneProgramma,
         adesso: adesso,
       ),
       _budgetPagina = budgetPagina;

  final ContestoCoach contesto;
  final int? _budgetPagina;

  late final inviti = GestioneInviti(contesto);
  late final atleti = GestioneAtleti(contesto, inviti);
  late final dispositivi = GestioneDispositivi(contesto);
  late final schede = GestioneSchede(contesto);
  late final allenamenti = GestioneAllenamenti(contesto, schede);
  late final abbinamento = ServizioAbbinamento(contesto);
  late final sincronizzazione = _budgetPagina == null
      ? ServizioSincronizzazione(contesto, schede)
      : ServizioSincronizzazione(contesto, schede, budgetPagina: _budgetPagina);

  /// Indirizzo onion del coach, senza ".onion".
  String get indirizzo => contesto.indirizzo;

  Stream<EventoCoach> get eventi => contesto.eventi;

  /// Vedi [ContestoCoach.chiaviCambiate].
  Stream<void> get chiaviCambiate => contesto.chiaviCambiate;

  String get nomeCoach => contesto.nomeCoach;

  set nomeCoach(String nome) {
    final pulito = nome.trim();
    if (pulito.isEmpty || pulito.length > 100) {
      throw const OperazioneNonValida('Il nome deve avere da 1 a 100 caratteri');
    }
    contesto.archivio.scriviImpostazione(Impostazioni.nomeCoach, pulito);
  }

  /// Risposta di `GET /v1/info`.
  RispostaInfo info() => RispostaInfo(
    protocollo: versioniProtocollo,
    nomeCoach: nomeCoach,
    versioneProgramma: contesto.versioneProgramma,
    versioneAppMinima: contesto.versioneAppMinima,
  );

  /// Chiavi X25519 che il servizio onion deve autorizzare (§6.1).
  List<String> chiaviAutorizzate() => inviti.chiaviAutorizzate();

  Future<void> chiudi() => contesto.chiudi();
}
