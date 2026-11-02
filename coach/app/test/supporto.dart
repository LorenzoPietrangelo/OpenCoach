import 'dart:async';

import 'package:coach_app/app.dart';
import 'package:coach_app/piattaforma/desktop.dart';
import 'package:coach_app/servizi.dart';
import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';

/// Coach con l'archivio in memoria e senza Tor.
class CoachDiProva implements Coach {
  CoachDiProva({String nome = 'Marco Bianchi'})
    : archivio = Archivio.inMemoria(),
      indirizzo = indirizzoOnionDaChiave(List.filled(32, 7)) {
    nucleo = NucleoCoach(archivio: archivio, indirizzo: indirizzo);
    if (nome.isNotEmpty) nucleo.nomeCoach = nome;
    backup = GestioneBackup(
      archivio: archivio,
      identita: () => throw UnimplementedError(),
      portachiavi: PortachiaviMemoria(),
      versioneProgramma: '1.0.0',
    );
  }

  final Archivio archivio;
  @override
  late final NucleoCoach nucleo;
  @override
  String indirizzo;
  @override
  late final GestioneBackup backup;
  final stati = StreamController<StatoTor>.broadcast();
  @override
  StatoTor statoTor = const StatoTor(FaseTor.raggiungibile, avanzamento: 100);
  var identitaReimpostate = 0;

  @override
  Stream<StatoTor> get cambiamentiStatoTor => stati.stream;

  @override
  String get cartellaDati => 'dati-di-prova';

  @override
  Future<void> reimpostaIdentita() async => identitaReimpostate++;

  @override
  Future<void> chiudi() async {}

  /// Un telefono si abbina all'atleta e invia [log], [pesi] e [risposte] ai
  /// questionari, come farebbe l'app.
  Future<void> riceviLog(
    String atletaId,
    List<Map<String, Object?>> log, {
    List<Map<String, Object?>> pesi = const [],
    List<Map<String, Object?>> risposte = const [],
    List<Map<String, Object?>> messaggi = const [],
  }) async {
    final invito = await nucleo.inviti.crea(atletaId);
    final uri = invito.uri!;
    nucleo.abbinamento.abbina(
      RichiestaAbbinamento(
        invitoId: uri.id,
        segreto: uri.segreto,
        chiaveDispositivo: (await CoppiaX25519.genera()).pubblicaBase32,
        dispositivo: const DatiDispositivo(nome: 'Pixel 8', piattaforma: 'android', versioneApp: '1.3.0'),
      ),
    );
    final dispositivo = nucleo.dispositivi.attivo(atletaId)!;
    nucleo.abbinamento.conferma(dispositivo);
    nucleo.sincronizzazione.sincronizza(
      dispositivo,
      RichiestaSync(
        epoca: null,
        cursore: null,
        log: log,
        pesi: pesi,
        risposte: risposte,
        messaggi: messaggi,
        versioneApp: '1.3.0',
      ),
    );
  }
}

/// Integrazione desktop finta: registra le chiamate.
class DesktopFinto implements Desktop {
  final chiamate = <String>[];
  final notifiche = <String>[];
  var avvio = false;
  var sospensioneImpedita = false;
  String? fileDaSalvare;

  @override
  Future<void> prepara({
    required TestiDesktop testi,
    required bool nascosto,
    required VoidCallback richiestaUscita,
  }) async => chiamate.add('prepara');

  @override
  Future<void> mostraFinestra() async => chiamate.add('mostra');

  @override
  Future<void> aggiornaStato(String descrizione) async => chiamate.add('stato: $descrizione');

  @override
  Future<bool> avvioAutomatico() async => avvio;

  @override
  Future<void> impostaAvvioAutomatico(bool attivo) async => avvio = attivo;

  @override
  Future<void> impedisciSospensione(bool attivo) async => sospensioneImpedita = attivo;

  @override
  Future<void> notifica(String titolo, String testo) async => notifiche.add('$titolo: $testo');

  @override
  Future<String?> scegliCartella() async => null;

  @override
  Future<String?> scegliDoveSalvare(String nomeSuggerito, String estensione) async => fileDaSalvare;

  @override
  Future<String?> scegliFile(String estensione) async => null;

  @override
  Future<void> apriFile(String percorso) async => chiamate.add('apri: $percorso');

  @override
  Future<void> esci() async => chiamate.add('esci');
}

Map<String, Object?> contenutoScheda(String titolo, {String? sedutaId}) => {
  'titolo': titolo,
  'sedute': [
    {
      'id': sedutaId ?? nuovoUuid(),
      'nome': 'Giorno A',
      'esercizi': [
        {
          'id': nuovoUuid(),
          'nome': 'Squat',
          'prescrizione': [
            {'serie': 4, 'ripetizioni': '6-8', 'carico': '75% 1RM', 'recupero_s': 150},
          ],
        },
      ],
    },
  ],
};

/// Avvia l'interfaccia su uno schermo da desktop.
Future<void> avviaApp(WidgetTester tester, CoachDiProva coach, DesktopFinto desktop) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppCoach(
      coach: coach,
      desktop: desktop,
      ripristina: (file, passphrase) async => throw UnimplementedError(),
    ),
  );
  await tester.pumpAndSettle();
}
