import 'package:protocollo/protocollo.dart';

import 'abbinamento.dart' as abbinamento;
import 'archivio.dart';
import 'cassaforte.dart';
import 'collegamenti.dart';
import 'contesto.dart';
import 'diario.dart';
import 'modelli.dart';
import 'orologio.dart';
import 'pianificatore.dart';
import 'schede.dart';
import 'sincronizzazione.dart';
import 'trasporto.dart';

/// L'app dell'atleta senza interfaccia (§10): archivio locale, abbinamento,
/// coda dei log e sincronizzazione. L'app Flutter lavora su queste parti e
/// fornisce Tor, la cassaforte del sistema operativo e lo stato della rete.
///
/// Le sync automatiche in primo piano partono solo dopo
/// [PianificatoreSync.entraInPrimoPiano].
class NucleoAtleta {
  NucleoAtleta({
    required ArchivioAtleta archivio,
    required Cassaforte cassaforte,
    required TrasportoTor tor,
    required DatiDispositivo dispositivo,
    Connettivita rete = const ReteSempreDisponibile(),
    Orologio orologio = const OrologioDiSistema(),
    void Function(String)? registra,
    int logPerRichiesta = Limiti.logPerRichiesta,
    int budgetRichiesta = MotoreSync.budgetPredefinito,
  }) : contesto = ContestoAtleta(
         archivio: archivio,
         cassaforte: cassaforte,
         tor: tor,
         rete: rete,
         orologio: orologio,
         dispositivo: dispositivo,
         registra: registra ?? (_) {},
       ),
       _logPerRichiesta = logPerRichiesta,
       _budgetRichiesta = budgetRichiesta;

  final ContestoAtleta contesto;
  final int _logPerRichiesta;
  final int _budgetRichiesta;

  late final schede = SchedeRicevute(contesto);
  late final diario = DiarioAllenamenti(
    contesto,
    cambiato: (coachId) => pianificatore.logCambiato(coachId),
  );
  late final sync = MotoreSync(
    contesto,
    schede,
    logPerRichiesta: _logPerRichiesta,
    budgetRichiesta: _budgetRichiesta,
  );
  late final collegamenti = Collegamenti(contesto, sync);
  late final pianificatore = PianificatoreSync(contesto, sync);

  /// Legge il QR o il link d'invito, incollato anche a mano, e chiede al
  /// coach il suo nome (§5.3, punti 1–3). Poi l'interfaccia chiede
  /// «Collegarti a Marco Bianchi?» e, se l'atleta conferma, chiama
  /// [abbinamento.InvitoLetto.collega].
  ///
  /// [avanzamento] segue l'avvio di Tor e i tentativi verso il coach, per la
  /// barra d'avanzamento.
  ///
  /// Lancia `ErroreAbbinamento` con il messaggio da mostrare (§5.4).
  Future<abbinamento.InvitoLetto> leggiInvito(
    String testo, {
    abbinamento.OsservatoreAbbinamento? avanzamento,
  }) => abbinamento.leggiInvito(contesto, sync, testo, avanzamento: avanzamento);

  /// Id dei coach i cui dati o il cui stato sono cambiati: l'interfaccia li
  /// rilegge.
  Stream<int> get cambiamenti => contesto.cambiamenti;

  /// Sync di tutti i coach chiesta dal sistema operativo con l'app in
  /// background (§7.4). Alla fine Tor si ferma, salvo che nel frattempo
  /// l'app sia tornata in primo piano. Gli esiti dicono quali schede nuove
  /// annunciare con una notifica.
  Future<List<EsitoSync>> sincronizzaInBackground() async {
    final esiti = await sync.sincronizzaTutti();
    if (!pianificatore.inPrimoPiano && !sync.occupato) {
      await contesto.tor.ferma();
    }
    return esiti;
  }

  /// I dati dell'atleta in JSON (§10.2, §11.3): coach, schede e log, senza
  /// chiavi né token. Con [coachId] solo quelli di un coach, anche dopo una
  /// revoca.
  Map<String, Object?> esporta({int? coachId}) => {
    'formato': 'open-coach-atleta',
    'versione': 1,
    'esportato_il': formattaDataOra(contesto.orologio.adesso()),
    'coach': [
      for (final coach in collegamenti.elenco())
        if (coachId == null || coach.id == coachId) _esportaCoach(coach),
    ],
  };

  Map<String, Object?> _esportaCoach(CoachCollegato coach) => {
    'nome_coach': coach.nomeCoach,
    'indirizzo': coach.indirizzo,
    'nome_atleta': coach.nomeAtleta,
    'atleta_id': coach.atletaId,
    'stato': coach.stato.name,
    'abbinato_il': formattaDataOra(coach.abbinatoIl),
    'ultima_sync': switch (coach.ultimaSync) {
      final DateTime quando => formattaDataOra(quando),
      null => null,
    },
    'schede': [
      for (final scheda in [
        ...schede.elenco(coach.id),
        ...schede.elenco(coach.id, archiviate: true),
      ])
        scheda.contenuto,
    ],
    'log': [for (final log in diario.elenco(coach.id)) log.perProtocollo],
  };

  /// Ferma il pianificatore e aspetta le sync in corso. L'archivio lo chiude
  /// chi l'ha aperto.
  Future<void> chiudi() async {
    pianificatore.ferma();
    await sync.attendiTutte();
    await contesto.chiudi();
  }
}
