import 'dart:convert';
import 'dart:typed_data';

import 'package:coach_mobile/dati/annunci.dart';
import 'package:coach_mobile/dati/cassaforte.dart';
import 'package:coach_mobile/dati/coda_messaggi.dart';
import 'package:coach_mobile/dati/collegamento.dart';
import 'package:coach_mobile/dati/fonte_dati.dart';
import 'package:coach_mobile/dati/modelli.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';

import 'supporto.dart';

void main() {
  late Ambiente a;

  setUp(() async => a = await Ambiente.avvia());
  tearDown(() => a.chiudi());

  group('collegamento', () {
    test('legge il QR, chiede il nome e si collega', () async {
      final qr = (await a.nucleo.telefonoCoach.creaInvito()).uri.toString();
      final letto = await a.servizio.leggi(qr);
      expect(letto.nomeCoach, 'Marco Bianchi');
      expect(a.tor.chiavi, contains(a.nucleo.indirizzo));

      final credenziali = await letto.conferma();
      expect(credenziali.confermato, isFalse);
      expect(a.nucleo.telefonoCoach.attivo()?.nome, 'Telefono di prova');
      // La chiave del QR è uscita da Tor, così scarta il descrittore (§5.3).
      expect(a.tor.rimosse, [a.nucleo.indirizzo]);
      expect((await a.servizio.caricaCredenziali())?.token, credenziali.token);
    });

    test('un invito di un atleta non vale', () async {
      final atleta = a.nucleo.atleti.crea('Giulia');
      final invito = await a.nucleo.inviti.crea(atleta.id);
      await expectLater(
        a.servizio.leggi(invito.uri.toString()),
        throwsA(isA<ErroreCollegamento>().having((e) => e.problema, 'problema', ProblemaCollegamento.codiceNonValido)),
      );
    });

    test('un QR annullato sul PC non vale', () async {
      final qr = (await a.nucleo.telefonoCoach.creaInvito()).uri.toString();
      final letto = await a.servizio.leggi(qr);
      a.nucleo.telefonoCoach.annullaInvito();
      await expectLater(
        letto.conferma(),
        throwsA(isA<ErroreCollegamento>().having((e) => e.problema, 'problema', ProblemaCollegamento.qrNonValido)),
      );
    });

    test('se la risposta si è persa, riprova con la stessa chiave', () async {
      final qr = (await a.nucleo.telefonoCoach.creaInvito()).uri.toString();
      final uri = UriTelefonoCoach.analizza(qr);
      final primo = await (await a.servizio.leggi(qr)).conferma();

      // L'app si era chiusa prima di ricevere la risposta: la chiave è ancora
      // quella in corso, e il PC dà un token nuovo invece di dire che è in uso.
      await a.cassaforte.scrivi(
        'collegamento_in_corso',
        jsonEncode({'invito': uri.id, 'chiave': primo.chiavePrivata}),
      );
      final secondo = await (await a.servizio.leggi(qr)).conferma();
      expect(secondo.chiavePrivata, primo.chiavePrivata);
      expect(secondo.token, isNot(primo.token));
    });

    test('un altro telefono trova il QR occupato', () async {
      final qr = (await a.nucleo.telefonoCoach.creaInvito()).uri.toString();
      await (await a.servizio.leggi(qr)).conferma();
      await expectLater(
        (await a.servizio.leggi(qr)).conferma(),
        throwsA(isA<ErroreCollegamento>().having((e) => e.problema, 'problema', ProblemaCollegamento.qrInUso)),
      );
    });
  });

  group('stato in primo piano', () {
    test('conferma il collegamento e legge gli atleti', () async {
      a.nucleo.atleti.crea('Giulia');
      final stato = await a.statoCollegato();
      expect(stato.inCollegamento, isTrue);
      stato.entraInPrimoPiano();
      await a.finche(() => stato.caricato);
      expect(stato.atleti.single.nome, 'Giulia');
      expect(stato.inCollegamento, isFalse);
      expect(a.nucleo.telefonoCoach.invitoInCorso(), isNull);
      stato.dispose();
    });

    test('un messaggio dell\'atleta arriva da solo, e il letto torna al PC', () async {
      final atleta = a.nucleo.atleti.crea('Giulia');
      final telefono = await a.abbinaAtleta(atleta.id);
      final stato = await a.statoCollegato();
      stato.entraInPrimoPiano();
      await a.finche(() => stato.caricato);
      expect(stato.atleti.single.nonLetti, 0);
      final generazione = stato.generazione;

      await telefono.manda('Ciao coach');
      await a.finche(() => stato.generazione > generazione);
      expect(stato.atleti.single.nonLetti, 1);
      expect(stato.atleti.single.ultimoMessaggio?.testo, 'Ciao coach');

      await stato.segnaLetti(atleta.id);
      await a.finche(() => stato.atleti.single.nonLetti == 0);
      expect(a.nucleo.messaggi.nonLetti(atleta.id), 0);
      stato.dispose();
    });

    test('un messaggio scritto arriva all\'atleta e non resta in coda', () async {
      final atleta = a.nucleo.atleti.crea('Giulia');
      final stato = await a.statoCollegato();
      stato.entraInPrimoPiano();
      await a.finche(() => stato.caricato);
      await stato.scrivi(atleta.id, '  Bravissima  ');
      await a.finche(() => stato.coda.vuota);
      expect(a.nucleo.messaggi.conversazione(atleta.id).single.testo, 'Bravissima');
      stato.dispose();
    });

    test('con il PC irraggiungibile il problema si vede e il messaggio aspetta', () async {
      final atleta = a.nucleo.atleti.crea('Giulia');
      final stato = await a.statoCollegato();
      stato.entraInPrimoPiano();
      await a.finche(() => stato.caricato);

      a.pcSpento = true;
      await stato.scrivi(atleta.id, 'Quando torni');
      await a.finche(() => stato.problema == ProblemaCoach.irraggiungibile);
      expect(stato.coda.perAtleta(atleta.id).single.testo, 'Quando torni');
      expect(a.nucleo.messaggi.conversazione(atleta.id), isEmpty);

      // Il messaggio sopravvive alla chiusura dell'app.
      final riaperta = CodaMessaggi(a.cassaforte);
      await riaperta.carica();
      expect(riaperta.perAtleta(atleta.id).single.testo, 'Quando torni');

      a.pcSpento = false;
      stato.riprova();
      await a.finche(() => stato.coda.vuota && stato.problema == null);
      expect(a.nucleo.messaggi.conversazione(atleta.id).single.testo, 'Quando torni');
      stato.dispose();
    });

    test('un telefono revocato dal PC dimentica tutto', () async {
      final stato = await a.statoCollegato();
      stato.entraInPrimoPiano();
      await a.finche(() => stato.caricato);
      await stato.coda.aggiungi(
        MessaggioInCoda(id: nuovoUuid(), atletaId: nuovoUuid(), testo: 'Mai partito', scrittoIl: DateTime.now()),
      );
      a.nucleo.telefonoCoach.revoca();
      stato.riprova();
      await a.finche(() => !stato.collegato);
      expect(stato.coda.vuota, isTrue);
      expect(a.cassaforte.voci, isEmpty);
      stato.dispose();
    });

    test('scollegare dall\'app revoca il telefono anche sul PC', () async {
      final stato = await a.statoCollegato();
      stato.entraInPrimoPiano();
      await a.finche(() => stato.caricato);
      await stato.scollega();
      expect(stato.collegato, isFalse);
      expect(a.nucleo.telefonoCoach.attivo(), isNull);
      expect(a.cassaforte.voci, isEmpty);
      stato.dispose();
    });

    test('un messaggio rifiutato dal PC non si ritenta', () async {
      final stato = await a.statoCollegato();
      stato.entraInPrimoPiano();
      await a.finche(() => stato.caricato);
      final inesistente = nuovoUuid();
      await stato.scrivi(inesistente, 'A nessuno');
      await a.finche(() => stato.coda.perAtleta(inesistente).single.rifiutato);
      expect(stato.coda.perAtleta(inesistente).single.comeMessaggio().statoInvio, StatoInvio.rifiutato);
      await stato.togliDallaCoda(stato.coda.perAtleta(inesistente).single.id);
      expect(stato.coda.vuota, isTrue);
      stato.dispose();
    });
  });

  group('controllo in background', () {
    test('manda la coda, annuncia una volta sola e spegne Tor', () async {
      final atleta = a.nucleo.atleti.crea('Giulia');
      final telefono = await a.abbinaAtleta(atleta.id);
      final stato = await a.statoCollegato();
      await stato.coda.aggiungi(
        MessaggioInCoda(id: nuovoUuid(), atletaId: atleta.id, testo: 'Scritto prima', scrittoIl: DateTime.now()),
      );
      await telefono.manda('Ciao coach');

      final annunci = await stato.controllaInBackground();
      expect(annunci.single.nome, 'Giulia');
      expect(annunci.single.messaggi, 1);
      expect(a.nucleo.messaggi.conversazione(atleta.id).map((m) => m.testo), contains('Scritto prima'));
      expect(a.tor.fermate, greaterThan(0));

      expect(await stato.controllaInBackground(), isEmpty);
      await telefono.manda('Ancora');
      expect((await stato.controllaInBackground()).single.messaggi, 2);
      stato.dispose();
    });

    test('con il PC spento non annuncia niente e non si rompe', () async {
      final stato = await a.statoCollegato();
      a.pcSpento = true;
      expect(await stato.controllaInBackground(), isEmpty);
      expect(stato.collegato, isTrue);
      stato.dispose();
    });

    test('con l\'app aperta non annuncia: il coach vede già', () async {
      final stato = await a.statoCollegato();
      stato.entraInPrimoPiano();
      await a.finche(() => stato.caricato);
      expect(await stato.controllaInBackground(), isEmpty);
      stato.dispose();
    });
  });

  group('registro degli annunci', () {
    RiepilogoAtleta atleta(int nonLetti, int risposte) => RiepilogoAtleta(
      id: 'a',
      nome: 'Giulia',
      telefonoCollegato: true,
      ultimoContatto: null,
      nonLetti: nonLetti,
      risposteNuove: risposte,
      ultimoMessaggio: null,
      ultimoAllenamento: null,
    );

    test('annuncia solo quando i numeri crescono', () async {
      final r = RegistroAnnunci(CassaforteInMemoria());
      expect((await r.confronta([atleta(2, 0)])).single.messaggi, 2);
      expect(await r.confronta([atleta(2, 0)]), isEmpty);
      expect(await r.confronta([atleta(0, 0)]), isEmpty);
      final dopo = (await r.confronta([atleta(1, 1)])).single;
      expect(dopo.messaggi, 1);
      expect(dopo.risposte, 1);
    });

    test('quello che il coach ha già visto non si annuncia', () async {
      final r = RegistroAnnunci(CassaforteInMemoria());
      await r.ricorda([atleta(3, 1)]);
      expect(await r.confronta([atleta(3, 1)]), isEmpty);
    });
  });

  group('dati', () {
    test('legge allenamenti, pesi, questionari, foto e dettagli', () async {
      final atleta = a.nucleo.atleti.crea('Giulia', note: 'Ginocchio');
      final telefono = await a.abbinaAtleta(atleta.id);
      final foto = nuovoUuid();
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9]);
      final modello = a.nucleo.questionari.creaModello({
        'titolo': 'Check',
        'domande': [
          {'id': nuovoUuid(), 'tipo': 'numero', 'testo': 'Quanto pesi?', 'obbligatoria': false, 'unita': 'kg'},
        ],
      });
      final inviato = a.nucleo.questionari.invia(modello, atleta.id);
      await telefono.mandaDati(fotoId: foto, jpeg: jpeg);

      final stato = await a.statoCollegato();
      stato.entraInPrimoPiano();
      await a.finche(() => stato.caricato);
      final fonte = stato.fonte;

      final allenamenti = await fonte.allenamenti(atleta.id);
      expect(allenamenti.elementi.single.esercizi.single.nome, 'Squat');
      expect(allenamenti.elementi.single.serieFatte, (1, 1));
      expect(allenamenti.elementi.single.esercizi.single.serie.single.caricoKg, 80);

      final pesi = await fonte.pesi(atleta.id);
      expect(pesi.single.kg, 70.5);

      final questionari = await fonte.questionari(atleta.id);
      expect(questionari.single.id, inviato);
      expect(questionari.single.titolo, 'Check');

      expect(await fonte.foto(foto), jpeg);

      final dettaglio = await fonte.atleta(atleta.id);
      expect(dettaglio.note, 'Ginocchio');
      expect(dettaglio.allenamentiTotali, 1);
      stato.dispose();
    });

    test('le risposte di un questionario diventano testo', () {
      final q = QuestionarioAtleta.daJson({
        'id': 'q',
        'titolo': 'Check',
        'stato': 'risposto',
        'contenuto': {
          'domande': [
            {'id': '1', 'testo': 'Giorni?'},
            {'id': '2', 'testo': 'Peso?', 'unita': 'kg'},
            {'id': '3', 'testo': 'Altro?'},
            {'id': '4', 'testo': 'Quali?'},
            {'id': '5', 'testo': 'Saltata'},
          ],
        },
        'risposta': {
          'risposte': [
            {'domanda_id': '1', 'valore': {'scelta': '3 giorni'}},
            {'domanda_id': '2', 'valore': 72.4},
            {'domanda_id': '3', 'valore': {'altro': 'Giorni alterni'}},
            {'domanda_id': '4', 'valore': {'scelte': ['A', 'B'], 'altro': 'C'}},
          ],
          'foto': ['f1'],
        },
      });
      expect(q.risposte.map((r) => r.risposta), ['3 giorni', '72.4 kg', 'Giorni alterni', 'A, B, C', null]);
      expect(q.foto, ['f1']);
      expect(q.risposto, isTrue);
    });

    test('un campo sconosciuto o mancante non fa cadere l\'app', () {
      final m = MessaggioChat.daJson({'id': 'x', 'campo_nuovo': 1});
      expect(m.testo, '');
      expect(m.inviatoIl, isNull);
      final r = RiepilogoAtleta.daJson({'id': 'x'});
      expect(r.nonLetti, 0);
      final al = AllenamentoAtleta.daJson({'id': 'x'});
      expect(al.serieFatte, (0, 0));
    });
  });
}

