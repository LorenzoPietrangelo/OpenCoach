// Prova sulla rete Tor vera: richiede l'eseguibile `tor` indicato nella
// variabile OPENCOACH_TOR. Dura qualche minuto. Il telefono è il codice vero
// dell'app, con un tor in un processo al posto di tor-android.
//
//   OPENCOACH_TOR=C:\percorso\tor.exe flutter test test/tor_reale_test.dart
@Tags(['tor'])
@Timeout(Duration(minutes: 20))
library;

import 'dart:io';

import 'package:coach_mobile/dati/cassaforte.dart';
import 'package:coach_mobile/dati/coda_messaggi.dart';
import 'package:coach_mobile/dati/collegamento.dart';
import 'package:coach_mobile/dati/stato_coach.dart';
import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';
import 'package:trasporto_tor/trasporto_tor.dart';

import 'supporto.dart';

void main() {
  final eseguibile = Platform.environment['OPENCOACH_TOR'];

  test(
    'il telefono del coach si collega, legge e scrive attraverso la rete Tor',
    () async {
      final cartella = await Directory.systemTemp.createTemp('opencoach_telefono_');
      final cronometro = Stopwatch()..start();
      // ignore: avoid_print
      void tappa(String testo) => print('[${cronometro.elapsed}] $testo');

      final programma = await ProgrammaCoach.avvia(
        cartellaDati: '${cartella.path}${Platform.pathSeparator}coach',
        portachiavi: PortachiaviMemoria(),
        eseguibileTor: eseguibile,
      );
      final nucleo = programma.nucleo..nomeCoach = 'Coach Tor';
      final atleta = nucleo.atleti.crea('Giulia');
      final avviatore = AvviatoreTorProcesso(
        eseguibile: eseguibile!,
        cartellaDati: '${cartella.path}${Platform.pathSeparator}telefono',
      );
      final tor = TrasportoTorControllato(avviatore);
      final cassaforte = CassaforteInMemoria();
      final servizio = ServizioCollegamento(
        cassaforte: cassaforte,
        tor: tor,
        dispositivo: datiTelefono,
        attesaMassima: const Duration(minutes: 5),
      );
      StatoCoach? stato;
      try {
        await finche(() => programma.statoTor.fase != FaseTor.avvio, const Duration(minutes: 5));
        tappa('servizio del coach: ${programma.statoTor}');

        final qr = (await nucleo.telefonoCoach.creaInvito()).uri.toString();
        final letto = await servizio.leggi(qr, avanzamento: (f) => tappa('fase ${f.name}'));
        expect(letto.nomeCoach, 'Coach Tor');
        tappa('QR letto');
        await letto.conferma(avanzamento: (f) => tappa('fase ${f.name}'));
        expect(nucleo.telefonoCoach.attivo(), isNotNull);
        tappa('telefono collegato, in attesa della conferma');

        stato = StatoCoach(cassaforte: cassaforte, collegamento: servizio, registra: tappa);
        await stato.carica();
        stato.entraInPrimoPiano();
        await finche(() => stato!.caricato, const Duration(minutes: 12));
        expect(stato.inCollegamento, isFalse);
        expect(stato.atleti.single.nome, 'Giulia');
        tappa('conferma e primo elenco');

        // Un messaggio scritto sul PC arriva con l'attesa in sospeso.
        final generazione = stato.generazione;
        nucleo.messaggi.invia(atleta.id, 'Dal PC');
        await finche(() => stato!.generazione > generazione, const Duration(minutes: 2));
        expect((await stato.fonte.messaggi(atleta.id)).elementi.single.testo, 'Dal PC');
        tappa('novità arrivata dal PC');

        await stato.scrivi(atleta.id, 'Dal telefono');
        await finche(() => stato!.coda.vuota, const Duration(minutes: 2));
        expect(nucleo.messaggi.conversazione(atleta.id).map((m) => m.testo), ['Dal PC', 'Dal telefono']);
        tappa('messaggio arrivato al PC');

        // In background Tor si spegne; il controllo lo riaccende, manda la coda
        // e annuncia il messaggio nuovo dell'atleta.
        await stato.vaiInBackground();
        await stato.coda.aggiungi(
          MessaggioInCoda(id: nuovoUuid(), atletaId: atleta.id, testo: 'Dalla coda', scrittoIl: DateTime.now()),
        );
        final telefonoAtleta = await nucleo.inviti.crea(atleta.id);
        nucleo.abbinamento.abbina(
          RichiestaAbbinamento(
            invitoId: telefonoAtleta.uri!.id,
            segreto: telefonoAtleta.uri!.segreto,
            chiaveDispositivo: (await CoppiaX25519.genera()).pubblicaBase32,
            dispositivo: datiTelefono,
          ),
        );
        nucleo.sincronizzazione.sincronizza(
          nucleo.dispositivi.attivo(atleta.id)!,
          RichiestaSync(
            epoca: null,
            cursore: null,
            log: const [],
            messaggi: [
              {'id': nuovoUuid(), 'autore': 'atleta', 'testo': 'Ciao coach', 'inviato_il': formattaDataOra(DateTime.now())},
            ],
            versioneApp: '1.5.0',
          ),
        );
        await Future<void>.delayed(const Duration(minutes: 1));
        final annunci = await stato.controllaInBackground();
        expect(annunci.single.messaggi, 1);
        expect(nucleo.messaggi.conversazione(atleta.id).map((m) => m.testo), contains('Dalla coda'));
        tappa('controllo in background');
      } finally {
        stato?.dispose();
        await avviatore.ferma();
        await programma.chiudi();
        await cartella.delete(recursive: true);
      }
    },
    skip: eseguibile == null ? 'Imposta OPENCOACH_TOR con il percorso dell\'eseguibile tor' : false,
  );
}

Future<void> finche(bool Function() condizione, Duration durata) async {
  final fine = DateTime.now().add(durata);
  while (!condizione()) {
    if (DateTime.now().isAfter(fine)) fail('Tempo scaduto');
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
