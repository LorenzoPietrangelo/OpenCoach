import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:protocollo/protocollo.dart';

import 'abbinamento.dart';
import 'allenamenti.dart';
import 'archivio.dart';
import 'atleti.dart';
import 'chat.dart';
import 'contesto.dart';
import 'dispositivi.dart';
import 'errori.dart';
import 'esportazioni.dart';
import 'eventi.dart';
import 'identita.dart';
import 'inviti.dart';
import 'libreria.dart';
import 'pesi.dart';
import 'questionari.dart';
import 'schede.dart';
import 'sincronizzazione.dart';
import 'telefono_coach.dart';
import 'tempo.dart';
import 'vista_telefono.dart';

/// Il programma del coach senza rete: archivio e regole di abbinamento e
/// sincronizzazione. Il server HTTP e Tor gli stanno attorno.
class NucleoCoach {
  NucleoCoach({
    required Archivio archivio,
    required String indirizzo,
    String versioneProgramma = '1.0.0',
    DateTime Function()? adesso,
    int? budgetPagina,
    String? cartellaVideo,
  }) : contesto = ContestoCoach(
         archivio: archivio,
         indirizzo: indirizzo,
         versioneProgramma: versioneProgramma,
         adesso: adesso,
       ),
       _budgetPagina = budgetPagina,
       _cartellaVideo = cartellaVideo ?? p.join(Directory.systemTemp.path, 'opencoach-video');

  final ContestoCoach contesto;
  final int? _budgetPagina;

  /// Dove stanno i video della chat (§8.7): accanto all'archivio, fuori dal
  /// backup.
  final String _cartellaVideo;

  late final inviti = GestioneInviti(contesto);
  late final atleti = GestioneAtleti(
    contesto,
    inviti,
    eliminato: (id) => messaggi.eliminaVideoAtleta(id),
  );
  late final messaggi = GestioneMessaggi(contesto, _cartellaVideo);
  late final dispositivi = GestioneDispositivi(contesto);
  late final schede = GestioneSchede(contesto);
  late final libreria = GestioneLibreria(contesto, schede);
  late final pesi = GestionePesi(contesto);
  late final questionari = GestioneQuestionari(contesto);
  late final allenamenti = GestioneAllenamenti(contesto, schede);
  late final abbinamento = ServizioAbbinamento(contesto);
  late final telefonoCoach = GestioneTelefonoCoach(contesto, inviti);
  late final vistaTelefono = VistaTelefonoCoach(
    contesto,
    atleti: atleti,
    messaggi: messaggi,
    allenamenti: allenamenti,
    pesi: pesi,
    questionari: questionari,
    schede: schede,
  );
  late final sincronizzazione = _budgetPagina == null
      ? ServizioSincronizzazione(contesto, schede, questionari, messaggi)
      : ServizioSincronizzazione(contesto, schede, questionari, messaggi, budgetPagina: _budgetPagina);
  late final esportazioni = GestioneEsportazioni(
    contesto,
    atleti,
    schede,
    allenamenti,
  );

  /// Passa a una nuova identità (§4): salva il seme già cifrato, revoca
  /// tutti i telefoni, annulla gli inviti e cambia epoca. Gli atleti vanno
  /// reinvitati. Ripubblicare l'onion service spetta a chi gestisce Tor.
  void reimpostaIdentita(String nuovoIndirizzo, List<int> semeCifrato) {
    final archivio = contesto.archivio;
    final ora = contesto.adesso();
    archivio.transazione(() {
      scriviIdentita(archivio, nuovoIndirizzo, semeCifrato, ora);
      archivio.db.execute(
        "UPDATE dispositivi SET stato = 'revocato', revocato_il = ? "
        "WHERE stato = 'attivo'",
        [istante(ora)],
      );
      archivio.db.execute(
        "UPDATE inviti SET stato = 'annullato', segreto = NULL, "
        "chiave_privata = NULL WHERE stato IN ('aperto', 'in_abbinamento')",
      );
      archivio.db.execute(
        "UPDATE telefoni_coach SET stato = 'revocato', revocato_il = ? "
        "WHERE stato = 'attivo'",
        [istante(ora)],
      );
      archivio.db.execute(
        "UPDATE inviti_telefono_coach SET stato = 'annullato', segreto = NULL, "
        "chiave_privata = NULL WHERE stato IN ('aperto', 'in_abbinamento')",
      );
      archivio.rigeneraEpoca();
    });
    contesto.indirizzo = nuovoIndirizzo;
    contesto.segnalaChiaviCambiate();
  }

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
