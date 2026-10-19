// Prova sulla rete Tor vera: richiede l'eseguibile `tor` (ramo stabile,
// almeno 0.4.8) indicato nella variabile OPENCOACH_TOR. Dura qualche minuto.
//
//   OPENCOACH_TOR=D:\percorso\tor.exe dart test test/tor_reale_test.dart
@Tags(['tor'])
@Timeout(Duration(minutes: 15))
library;

import 'dart:async';
import 'dart:io';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:path/path.dart' as p;
import 'package:protocollo/protocollo.dart';
import 'package:test/test.dart';

import 'supporto.dart';

void main() {
  final eseguibile = Platform.environment['OPENCOACH_TOR'];

  test(
    'abbinamento e sync attraverso la rete Tor',
    () async {
      final cartella = await Directory.systemTemp.createTemp('opencoach_tor_');
      final cronometro = Stopwatch()..start();
      void tappa(String testo) => print('[${cronometro.elapsed}] $testo');

      final programma = await ProgrammaCoach.avvia(
        cartellaDati: p.join(cartella.path, 'coach'),
        portachiavi: PortachiaviMemoria(),
        eseguibileTor: eseguibile,
      );
      programma.cambiamentiStatoTor.listen((s) => tappa('coach: $s'));
      final nucleo = programma.nucleo..nomeCoach = 'Coach Tor';
      final atleta = nucleo.atleti.crea('Giulia');
      final invito = await nucleo.inviti.crea(atleta.id);
      final schedaId = nucleo.schede.crea(atleta.id, contenuto: contenutoScheda('A'));
      nucleo.schede.pubblica(schedaId);

      // Il client è un secondo Tor con la porta SOCKS, come quello dell'app.
      var client = await ProcessoTor.avvia(
        eseguibile: eseguibile!,
        cartellaDati: p.join(cartella.path, 'client'),
        socks: true,
      );
      try {
        await _attendi(
          () => programma.statoTor.fase == FaseTor.raggiungibile,
          const Duration(minutes: 5),
        );
        tappa('servizio raggiungibile');

        var http = clienteHttpTramiteTor(
          socksHost: '127.0.0.1',
          socksPorta: await client.portaSocks(),
        );
        final uri = UriInvito.analizza(invito.uri.toString());
        var api = ClienteApi(indirizzo: uri.indirizzo, http: http);

        // Senza chiave il servizio non si raggiunge.
        await expectLater(
          api.info(),
          throwsA(
            isA<ErroreSocks>().having(
              (e) => e.autorizzazioneRifiutata,
              'autorizzazione rifiutata',
              isTrue,
            ),
          ),
        );
        tappa('senza chiave: rifiutato come previsto');

        // Con la chiave d'invito sì (§5.3, punti 3 e 4).
        await client.controllo.aggiungiAutorizzazioneClient(
          uri.indirizzo,
          decodificaChiave32(uri.chiave)!,
        );
        final info = await _riprova(api.info, tappa);
        expect(info.nomeCoach, 'Coach Tor');
        tappa('info ricevute con la chiave d\'invito');

        final chiave = await CoppiaX25519.genera();
        final abbinamento = await api.abbina(
          RichiestaAbbinamento(
            invitoId: uri.id,
            segreto: uri.segreto,
            chiaveDispositivo: chiave.pubblicaBase32,
            dispositivo: const DatiDispositivo(
              nome: 'Telefono di prova',
              piattaforma: 'android',
              versioneApp: '1.0.0',
            ),
          ),
        );
        tappa('abbinato');

        // L'app passa alla propria chiave e riavvia Tor (§5.3, punto 6).
        http.close(force: true);
        await client.ferma();
        client = await ProcessoTor.avvia(
          eseguibile: eseguibile,
          cartellaDati: p.join(cartella.path, 'client'),
          socks: true,
        );
        await client.controllo.aggiungiAutorizzazioneClient(uri.indirizzo, chiave.privata);
        http = clienteHttpTramiteTor(
          socksHost: '127.0.0.1',
          socksPorta: await client.portaSocks(),
        );
        api = ClienteApi(indirizzo: uri.indirizzo, http: http, token: abbinamento.token);
        tappa('client riavviato con la chiave del dispositivo');

        await _riprova(api.confermaAbbinamento, tappa, durata: const Duration(minutes: 10));
        tappa('abbinamento confermato');

        final sync = await api.sincronizza(
          RichiestaSync(
            epoca: null,
            cursore: null,
            log: [nuovoLog(schedaId: schedaId, revisione: 1)],
            versioneApp: '1.0.0',
          ),
        );
        expect(sync.completo, isTrue);
        expect(sync.schede.single['id'], schedaId);
        expect(sync.logAccettati, hasLength(1));
        expect(nucleo.allenamenti.elenco(atleta.id), hasLength(1));
        tappa('sync completata');
        http.close(force: true);
      } finally {
        await client.ferma();
        await programma.chiudi();
        await cartella.delete(recursive: true);
      }
    },
    skip: eseguibile == null
        ? 'Imposta OPENCOACH_TOR con il percorso dell\'eseguibile tor'
        : false,
  );
}

Future<void> _attendi(bool Function() condizione, Duration durata) async {
  final fine = DateTime.now().add(durata);
  while (!condizione()) {
    if (DateTime.now().isAfter(fine)) fail('Tempo scaduto');
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}

/// Ripete [chiamata] finché i guasti di rete passano, al massimo per [durata].
Future<T> _riprova<T>(
  Future<T> Function() chiamata,
  void Function(String) tappa, {
  Duration durata = const Duration(minutes: 3),
}) async {
  final fine = DateTime.now().add(durata);
  var tentativo = 0;
  while (true) {
    tentativo++;
    try {
      return await chiamata();
    } on Object catch (e) {
      final transitorio =
          e is ErroreSocks ||
          e is ErroreProtocolloSocks ||
          e is SocketException ||
          e is TimeoutException ||
          e is HttpException;
      if (!transitorio || DateTime.now().isAfter(fine)) rethrow;
      tappa('tentativo $tentativo non riuscito: $e');
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }
}
