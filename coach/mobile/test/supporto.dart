import 'dart:io';
import 'dart:typed_data';

import 'package:coach_mobile/dati/cassaforte.dart';
import 'package:coach_mobile/dati/collegamento.dart';
import 'package:coach_mobile/dati/stato_coach.dart';
import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:protocollo/protocollo.dart';
import 'package:trasporto_tor/trasporto_tor.dart';

const datiTelefono = DatiDispositivo(nome: 'Telefono di prova', piattaforma: 'android', versioneApp: '1.5.0');

/// Al posto di Tor si collega direttamente al server del PC; con [Ambiente.pcSpento]
/// la connessione fallisce come con il PC spento.
class TorFinto implements TrasportoTor {
  TorFinto(this._ambiente);

  final Ambiente _ambiente;
  final chiavi = <String, Uint8List>{};
  final rimosse = <String>[];
  var fermate = 0;

  @override
  Future<void> avvia({void Function(int percento)? avanzamento}) async {}

  @override
  Future<void> ferma() async => fermate++;

  @override
  Future<void> impostaChiave(String indirizzo, Uint8List chiavePrivata) async => chiavi[indirizzo] = chiavePrivata;

  @override
  Future<void> rimuoviChiave(String indirizzo) async {
    chiavi.remove(indirizzo);
    rimosse.add(indirizzo);
  }

  @override
  HttpClient creaHttpClient() => HttpClient()
    ..connectionFactory = (uri, proxyHost, proxyPort) async {
      if (_ambiente.pcSpento) throw const SocketException('PC spento');
      return Socket.startConnect('127.0.0.1', _ambiente.server.porta);
    };
}

/// Il programma del coach vero, in memoria, con il suo server HTTP, e i pezzi
/// dell'app sopra.
class Ambiente {
  Ambiente._();

  static Future<Ambiente> avvia() async {
    final a = Ambiente._();
    a.archivio = Archivio.inMemoria();
    final identita = await caricaOCreaIdentita(a.archivio, PortachiaviMemoria());
    a.nucleo = NucleoCoach(archivio: a.archivio, indirizzo: identita.indirizzo)..nomeCoach = 'Marco Bianchi';
    a.server = ServerCoach(a.nucleo);
    await a.server.avvia();
    a.tor = TorFinto(a);
    a.servizio = ServizioCollegamento(cassaforte: a.cassaforte, tor: a.tor, dispositivo: datiTelefono);
    return a;
  }

  late final Archivio archivio;
  late final NucleoCoach nucleo;
  late final ServerCoach server;
  late final TorFinto tor;
  late final ServizioCollegamento servizio;
  final cassaforte = CassaforteInMemoria();
  var pcSpento = false;

  ClienteApi cliente({String? token}) => ClienteApi(
    indirizzo: nucleo.indirizzo,
    http: tor.creaHttpClient(),
    token: token,
  );

  /// Lo stato dell'app con il telefono appena collegato, come dopo il QR. Le
  /// pause sono brevi: il test non aspetta davvero 30 secondi.
  Future<StatoCoach> statoCollegato() async {
    final qr = (await nucleo.telefonoCoach.creaInvito()).uri.toString();
    await (await servizio.leggi(qr)).conferma();
    final stato = StatoCoach(
      cassaforte: cassaforte,
      collegamento: servizio,
      attese: const [Duration(milliseconds: 20)],
      atteseConferma: const [Duration(milliseconds: 20)],
      atteseBackground: const [Duration(milliseconds: 20)],
    );
    await stato.carica();
    return stato;
  }

  /// Aspetta che [condizione] diventi vera.
  Future<void> finche(bool Function() condizione) async {
    final scadenza = DateTime.now().add(const Duration(seconds: 15));
    while (!condizione()) {
      if (DateTime.now().isAfter(scadenza)) throw StateError('Condizione mai verificata');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Un telefono di un atleta che manda dati al PC, attraverso le sync vere.
  Future<AtletaFinto> abbinaAtleta(String atletaId) async {
    final invito = await nucleo.inviti.crea(atletaId);
    final uri = invito.uri!;
    final api = cliente();
    final risposta = await api.abbina(
      RichiestaAbbinamento(
        invitoId: uri.id,
        segreto: uri.segreto,
        chiaveDispositivo: (await CoppiaX25519.genera()).pubblicaBase32,
        dispositivo: datiTelefono,
      ),
    );
    api.token = risposta.token;
    await api.confermaAbbinamento();
    return AtletaFinto(api);
  }

  Future<void> chiudi() async {
    await server.chiudi();
    await nucleo.chiudi();
    archivio.chiudi();
  }
}

class AtletaFinto {
  AtletaFinto(this._api);

  final ClienteApi _api;

  Future<void> manda(String testo) => _api.sincronizza(
    RichiestaSync(
      epoca: null,
      cursore: null,
      log: const [],
      messaggi: [
        {
          'id': nuovoUuid(),
          'autore': 'atleta',
          'testo': testo,
          'inviato_il': formattaDataOra(DateTime.now()),
        },
      ],
      versioneApp: '1.5.0',
    ),
  );

  /// Un allenamento, un peso e una foto.
  Future<void> mandaDati({required String fotoId, required Uint8List jpeg}) async {
    await _api.caricaFoto(fotoId, jpeg);
    await _api.sincronizza(
      RichiestaSync(
        epoca: null,
        cursore: null,
        log: [
          {
            'id': nuovoUuid(),
            'rev': 1,
            'eliminato': false,
            'scheda_id': null,
            'scheda_revisione': null,
            'seduta_id': null,
            'eseguito_il': '2026-10-21T18:30:00+02:00',
            'note': '',
            'esercizi': [
              {
                'esercizio_id': null,
                'nome': 'Squat',
                'serie': [
                  {'ripetizioni': 8, 'carico_kg': 80, 'completata': true},
                ],
              },
            ],
          },
        ],
        pesi: [
          {'id': nuovoUuid(), 'rev': 1, 'eliminato': false, 'giorno': '2026-10-17', 'kg': 70.5},
        ],
        pesiCondivisi: true,
        versioneApp: '1.5.0',
      ),
    );
  }
}
