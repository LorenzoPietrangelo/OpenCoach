import 'dart:io';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:protocollo/protocollo.dart';

/// Programma del coach in memoria con il server HTTP vero e un orologio
/// controllato dal test.
class Ambiente {
  Ambiente._();

  static Future<Ambiente> avvia({int? budgetPagina, String? cartellaVideo}) async {
    final a = Ambiente._();
    a.archivio = Archivio.inMemoria();
    final identita = await caricaOCreaIdentita(a.archivio, PortachiaviMemoria());
    a.nucleo = NucleoCoach(
      archivio: a.archivio,
      indirizzo: identita.indirizzo,
      adesso: () => a.ora,
      budgetPagina: budgetPagina,
      cartellaVideo: cartellaVideo,
    )..nomeCoach = 'Marco Bianchi';
    a.nucleo.eventi.listen(a.eventi.add);
    a.nucleo.chiaviCambiate.listen((_) => a.segnalazioniChiavi++);
    a.server = ServerCoach(a.nucleo, adesso: () => a.ora, registra: print);
    await a.server.avvia();
    // Il client si collega direttamente al server locale, al posto di Tor.
    a.http = HttpClient()
      ..connectionFactory = (uri, proxyHost, proxyPort) =>
          Socket.startConnect('127.0.0.1', a.server.porta);
    return a;
  }

  late final Archivio archivio;
  late final NucleoCoach nucleo;
  late final ServerCoach server;
  late final HttpClient http;
  var ora = DateTime.utc(2026, 10, 18, 12);
  final eventi = <EventoCoach>[];
  var segnalazioniChiavi = 0;

  void avanza(Duration durata) => ora = ora.add(durata);

  ClienteApi cliente({String? token}) =>
      ClienteApi(indirizzo: nucleo.indirizzo, http: http, token: token);

  /// Abbina un telefono simulato all'atleta seguendo il flusso del §5.3.
  Future<TelefonoFinto> abbinaTelefono(
    String atletaId, {
    String nome = 'Pixel 8',
  }) async {
    final invito = await nucleo.inviti.crea(atletaId);
    final uri = UriInvito.analizza(invito.uri.toString());
    final chiave = await CoppiaX25519.genera();
    final cliente = this.cliente();
    final risposta = await cliente.abbina(
      RichiestaAbbinamento(
        invitoId: uri.id,
        segreto: uri.segreto,
        chiaveDispositivo: chiave.pubblicaBase32,
        dispositivo: DatiDispositivo(
          nome: nome,
          piattaforma: 'android',
          versioneApp: '1.0.0',
        ),
      ),
    );
    cliente.token = risposta.token;
    await cliente.confermaAbbinamento();
    return TelefonoFinto(this, cliente, risposta, chiave);
  }

  Future<void> chiudi() async {
    http.close(force: true);
    await server.chiudi();
    await nucleo.chiudi();
    archivio.chiudi();
  }
}

/// Telefono simulato che segue le regole di sync dell'app (§7.3), in forma
/// ridotta: tiene schede, log ricevuti, cursore ed epoca.
class TelefonoFinto {
  TelefonoFinto(this._ambiente, this.cliente, this.abbinamento, this.chiave);

  final Ambiente _ambiente;
  final ClienteApi cliente;
  final RispostaAbbinamento abbinamento;
  final CoppiaX25519 chiave;
  String? epoca;
  String? cursore;
  var schede = <String, Map<String, Object?>>{};
  var log = <String, Map<String, Object?>>{};
  var richieste = 0;

  /// Esegue una sync completa: invia [daInviare] con la prima richiesta e
  /// continua finché il programma ha altro da mandare.
  Future<List<RispostaSync>> sincronizza({
    List<Object?> daInviare = const [],
    String versioneApp = '1.0.0',
    List<Object?> pesi = const [],
    bool? pesiCondivisi,
    List<Object?> risposteQuestionari = const [],
    List<Object?> messaggi = const [],
    List<Object?> giornate = const [],
    bool? ciboCondiviso,
  }) async {
    final risposte = <RispostaSync>[];
    var cursoreRichiesta = cursore;
    var inviare = daInviare;
    var pesiDaInviare = pesi;
    var risposteDaInviare = risposteQuestionari;
    var messaggiDaInviare = messaggi;
    var giornateDaInviare = giornate;
    final schedeComplete = <String, Map<String, Object?>>{};
    final logCompleti = <String, Map<String, Object?>>{};
    while (true) {
      // Resta sotto il limite di 30 richieste al minuto.
      _ambiente.avanza(const Duration(seconds: 3));
      final risposta = await cliente.sincronizza(
        RichiestaSync(
          epoca: epoca,
          cursore: cursoreRichiesta,
          log: inviare,
          pesi: pesiDaInviare,
          pesiCondivisi: pesiCondivisi,
          risposte: risposteDaInviare,
          messaggi: messaggiDaInviare,
          giornate: giornateDaInviare,
          ciboCondiviso: ciboCondiviso,
          versioneApp: versioneApp,
        ),
      );
      richieste++;
      risposte.add(risposta);
      inviare = const [];
      risposteDaInviare = const [];
      messaggiDaInviare = const [];
      pesiDaInviare = const [];
      giornateDaInviare = const [];
      cursoreRichiesta = risposta.cursore;
      if (risposta.completo) {
        for (final s in risposta.schede) {
          schedeComplete[s['id'] as String] = s;
        }
        for (final l in risposta.log) {
          logCompleti[l['id'] as String] = l;
        }
        if (!risposta.altro) {
          schede = schedeComplete;
          log = logCompleti;
        }
      } else {
        for (final s in risposta.schede) {
          schede[s['id'] as String] = s;
        }
        risposta.schedeEliminate.forEach(schede.remove);
      }
      if (!risposta.altro) {
        epoca = risposta.epoca;
        cursore = risposta.cursore;
        return risposte;
      }
    }
  }
}

Map<String, Object?> contenutoScheda(
  String titolo, {
  String? sedutaId,
  String? esercizioId,
  String note = '',
}) => {
  'titolo': titolo,
  'note': note,
  'sedute': [
    {
      'id': sedutaId ?? nuovoUuid(),
      'nome': 'Giorno A',
      'esercizi': [
        {
          'id': esercizioId ?? nuovoUuid(),
          'nome': 'Squat',
          'prescrizione': [
            {
              'serie': 4,
              'ripetizioni': '6-8',
              'carico': '75% 1RM',
              'recupero_s': 150,
            },
          ],
        },
      ],
    },
  ],
};

Map<String, Object?> nuovoLog({
  String? id,
  int rev = 1,
  String? schedaId,
  int? revisione,
  String? sedutaId,
  String note = '',
}) => {
  'id': id ?? nuovoUuid(),
  'rev': rev,
  'eliminato': false,
  'scheda_id': schedaId,
  'scheda_revisione': revisione,
  'seduta_id': sedutaId,
  'eseguito_il': '2026-10-21T18:30:00+02:00',
  'note': note,
  'esercizi': [
    {
      'esercizio_id': null,
      'nome': 'Squat',
      'serie': [
        {'ripetizioni': 8, 'carico_kg': 80, 'completata': true},
      ],
    },
  ],
};
