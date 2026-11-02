import 'dart:io';

import 'package:atleta_app/app.dart';
import 'package:atleta_app/piattaforma/video.dart';
import 'package:atleta_app/schermate/allenamento.dart';
import 'package:atleta_app/schermate/contenuto_scheda.dart';
import 'package:atleta_app/schermate/dettaglio_scheda.dart';
import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocollo/protocollo.dart';

import 'supporto.dart';

void main() {
  late TelefonoDiProva telefono;

  setUp(() => telefono = TelefonoDiProva());
  tearDown(() => telefono.chiudi());

  /// Apre la seduta «Giorno A» di una scheda nuova del coach [coach].
  Future<Map<String, Object?>> iniziaGiornoA(
    WidgetTester tester,
    int coach, {
    Map<String, Object?>? scheda,
  }) async {
    scheda ??= schedaForza();
    telefono.aggiungiScheda(coach, scheda, vista: true);
    await tester.pumpWidget(
      conTesti(
        DettaglioScheda(
          nucleo: telefono.nucleo,
          coachId: coach,
          schedaId: scheda['id']! as String,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inizia').first);
    await tester.pumpAndSettle();
    return scheda;
  }

  /// Gli esercizi di un log, con le loro serie.
  List<Map<String, Object?>> esercizi(Map<String, Object?> contenuto) => [
    for (final esercizio in contenuto['esercizi']! as List<Object?>)
      esercizio! as Map<String, Object?>,
  ];

  testWidgets('una seduta: serie dalla prescrizione, recupero e salvataggio', (
    tester,
  ) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    final scheda = await iniziaGiornoA(tester, coach);

    // Gli esercizi partono chiusi: nome, serie × ripetizioni e RIR.
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('4 × 6-8 · RIR 1-2'), findsOneWidget);
    expect(find.text('0/4'), findsOneWidget);
    expect(find.text('Pausa di 1 s in buca'), findsNothing);
    expect(
      find.descendant(of: find.byType(Card), matching: find.byType(TextField)),
      findsNothing,
    );

    // Toccato, l'esercizio si apre per registrare le serie.
    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();
    expect(find.text('75% 1RM · recupero 2:30'), findsOneWidget);
    expect(find.text('Pausa di 1 s in buca'), findsOneWidget);
    // «6-8» e «75% 1RM» non sono numeri: restano come suggerimento.
    expect(find.widgetWithText(TextField, '6-8'), findsNWidgets(4));
    expect(find.widgetWithText(TextField, '75% 1RM'), findsNWidgets(4));
    await tester.enterText(find.widgetWithText(TextField, '6-8').first, '8');
    await tester.enterText(
      find.widgetWithText(TextField, '75% 1RM').first,
      '82,5',
    );

    // Serie fatta: parte il recupero previsto dal coach.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('1/4'), findsOneWidget);
    expect(find.text('2:30'), findsOneWidget);
    telefono.orologio.avanza(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1:30'), findsOneWidget);
    telefono.orologio.avanza(const Duration(seconds: 90));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Recupero finito'), findsOneWidget);

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Allenamento salvato'), findsOneWidget);

    final log = telefono.nucleo.diario.elenco(coach).single;
    expect(log.inAttesa, isTrue);
    final contenuto = log.contenuto!;
    expect(contenuto['scheda_id'], scheda['id']);
    expect(contenuto['scheda_revisione'], 1);
    expect(contenuto['seduta_id'], idGiornoA(scheda));
    // Durata e sforzo dell'allenamento non si chiedono più.
    expect(contenuto.containsKey('durata_min'), isFalse);
    expect(contenuto.containsKey('rpe'), isFalse);
    final eseguiti = esercizi(contenuto);
    expect([for (final e in eseguiti) e['nome']], ['Squat', 'Panca', 'Plank']);
    final squat = eseguiti[0]['serie']! as List<Object?>;
    expect(squat, hasLength(4));
    expect(squat[0], {'ripetizioni': 8, 'carico_kg': 82.5, 'completata': true});
    expect(squat[1], {'completata': false});
    // Panca e plank restano come li ha precompilati la prescrizione.
    expect((eseguiti[1]['serie']! as List<Object?>).first, {
      'ripetizioni': 8,
      'carico_kg': 60,
      'completata': false,
    });
    expect((eseguiti[2]['serie']! as List<Object?>).first, {
      'durata_s': 30,
      'completata': false,
    });
  });

  testWidgets('in grigio i valori dell\'ultima volta, e il video dell\'esercizio', (
    tester,
  ) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    telefono.nucleo.diario.salva(coach, {
      'scheda_id': null,
      'scheda_revisione': null,
      'seduta_id': null,
      'eseguito_il': '2026-10-14T18:00:00+02:00',
      'note': '',
      'esercizi': [
        {
          'esercizio_id': null,
          'nome': 'panca',
          'note': '',
          'serie': [
            {'ripetizioni': 8, 'carico_kg': 62.5, 'completata': true},
            {'ripetizioni': 7, 'carico_kg': 62.5, 'completata': true},
          ],
        },
      ],
    });
    final scheda = schedaForza();
    final squat =
        (((scheda['sedute']! as List<Object?>).first! as Map<String, Object?>)['esercizi']!
                as List<Object?>)
            .first! as Map<String, Object?>;
    squat['video'] = 'https://www.youtube.com/watch?v=abcdefghijk';
    await iniziaGiornoA(tester, coach, scheda: scheda);

    // Il video si vede solo aprendo l'esercizio, e non si carica da solo.
    expect(find.text('Guarda il video'), findsNothing);
    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();
    expect(find.text('Guarda il video'), findsOneWidget);
    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();

    // La panca prescrive 8 × 60 kg, ma l'ultima volta era 8 e 7 × 62,5:
    // i campi restano vuoti e lo mostrano in grigio.
    await tester.tap(find.text('Panca'));
    await tester.pumpAndSettle();
    final campi = find.descendant(of: find.byType(Card), matching: find.byType(TextField));
    String? suggerimento(int i) => tester.widget<TextField>(campi.at(i)).decoration?.hintText;
    String testo(int i) => tester.widget<TextField>(campi.at(i)).controller!.text;
    // Serie 1: ripetizioni e carico; serie 2 lo stesso.
    expect([suggerimento(0), suggerimento(1), suggerimento(2), suggerimento(3)], [
      '8',
      '62,5',
      '7',
      '62,5',
    ]);
    expect([testo(0), testo(1)], ['', '']);

    // Segnata fatta, la serie prende i valori in grigio.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect([testo(0), testo(1)], ['8', '62,5']);
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    final log = telefono.nucleo.diario.elenco(coach).first;
    final panca = esercizi(log.contenuto!)[1]['serie']! as List<Object?>;
    expect(panca, [
      {'ripetizioni': 8, 'carico_kg': 62.5, 'completata': true},
      {'completata': false},
    ]);
  });

  testWidgets('con un valore non valido non si salva', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    await iniziaGiornoA(tester, coach);
    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '6-8').first, 'otto');
    // Chiuso l'esercizio, al salvataggio si riapre per mostrare l'errore.
    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Card), matching: find.byType(TextField)),
      findsNothing,
    );
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Correggi i valori segnati in rosso.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'otto'), findsOneWidget);
    expect(telefono.nucleo.diario.elenco(coach), isEmpty);

    // Corretto il valore, si salva. Le serie non chiedono l'RPE.
    await tester.enterText(find.byType(TextField).first, '8');
    expect(find.text('RPE'), findsNothing);
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    final squat =
        esercizi(
              telefono.nucleo.diario.elenco(coach).single.contenuto!,
            ).first['serie']!
            as List<Object?>;
    expect(squat.first, {'ripetizioni': 8, 'completata': false});
  });

  testWidgets('allenamento libero con un esercizio aggiunto e note', (
    tester,
  ) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    await tester.pumpWidget(AppAtleta(nucleo: telefono.nucleo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marco Bianchi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allenamento libero'));
    await tester.pumpAndSettle();
    expect(find.text('Aggiungi gli esercizi che fai.'), findsOneWidget);

    await tester.tap(find.text('Aggiungi esercizio'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Trazioni',
    );
    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();
    expect(find.text('Trazioni'), findsOneWidget);

    // Ripetizioni e carico della serie.
    final campi = find.descendant(
      of: find.byType(Card),
      matching: find.byType(TextField),
    );
    expect(campi, findsNWidgets(2));
    await tester.enterText(campi.at(0), '10');
    // Senza un recupero previsto il timer non parte.
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(find.text('Recupero'), findsNothing);

    // Né lo sforzo né la durata dell'allenamento si chiedono.
    expect(find.text('Sforzo percepito della seduta (RPE)'), findsNothing);
    expect(find.text('Durata in minuti'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, "Note sull'allenamento"),
      'Presa prona',
    );
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    // Si torna allo storico del coach, con l'allenamento in attesa di invio.
    expect(find.text('Allenamento salvato'), findsOneWidget);
    expect(
      find.widgetWithText(ListTile, 'Allenamento libero · Trazioni'),
      findsOneWidget,
    );
    expect(find.textContaining('In attesa di invio'), findsOneWidget);

    final adesso = formattaDataOra(telefono.orologio.ora);
    expect(telefono.nucleo.diario.elenco(coach).single.contenuto, {
      'scheda_id': null,
      'scheda_revisione': null,
      'seduta_id': null,
      'eseguito_il': adesso,
      'note': 'Presa prona',
      'esercizi': [
        {
          'esercizio_id': null,
          'nome': 'Trazioni',
          'note': '',
          'serie': [
            {'ripetizioni': 10, 'completata': true},
          ],
        },
      ],
      'modificato_il': adesso,
    });
  });

  testWidgets('il timer di recupero si avvia anche a mano', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    await iniziaGiornoA(tester, coach);

    await tester.tap(find.byTooltip('Timer di recupero'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1:30'));
    await tester.pumpAndSettle();
    expect(find.text('1:30'), findsOneWidget);
    await tester.tap(find.text('+15 s'));
    await tester.pump();
    expect(find.text('1:45'), findsOneWidget);
    await tester.tap(find.text('Salta'));
    await tester.pump();
    expect(find.text('1:45'), findsNothing);
    expect(find.text('Recupero'), findsNothing);
  });

  testWidgets('uscire senza salvare chiede conferma', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    await iniziaGiornoA(tester, coach);
    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '6-8').first, '7');
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Uscire senza salvare?'), findsOneWidget);
    await tester.tap(find.text('Resta'));
    await tester.pumpAndSettle();
    expect(find.text('Squat'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();
    expect(find.text('Giorno B'), findsOneWidget);
    expect(telefono.nucleo.diario.elenco(coach), isEmpty);
  });

  testWidgets('il video di una serie parte nella chat con l\'allenamento', (tester) async {
    final coach = telefono.aggiungiCoach('Marco Bianchi');
    final dati = schedaForza();
    telefono.aggiungiScheda(coach, dati, vista: true);
    final scheda = telefono.nucleo.schede.cerca(coach, dati['id']! as String)!;
    final seduta = scheda.sedute.first;
    final scelte = <OrigineVideo>[];
    await tester.pumpWidget(
      conTesti(
        SchermataAllenamento(
          nucleo: telefono.nucleo,
          allenamento: AllenamentoInCorso.daSeduta(scheda, seduta.id, inizio: telefono.orologio.adesso()),
          titolo: seduta.nome,
          seduta: seduta,
          preparaVideo: (origine) async {
            scelte.add(origine);
            final file = File('${telefono.cartellaVideo.path}/registrato.mp4')
              ..writeAsBytesSync(List.filled(3000, 7));
            return VideoPreparato(file.path, 9);
          },
        ),
      ),
    );
    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Video della serie 2').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('senza audio e senza la posizione'), findsOneWidget);
    await tester.tap(find.text('Registra un video'));
    await tester.pumpAndSettle();
    expect(scelte, [OrigineVideo.fotocamera]);

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    final log = telefono.nucleo.diario.elenco(coach).single;
    final video = telefono.nucleo.chat.elenco(coach).single;
    expect(video.riferimento, {'log_id': log.id, 'esercizio': 'Squat', 'serie': 2});
    expect(video.durataVideoS, 9);
    expect(video.stato, StatoMessaggio.inInvio);
    expect(File(video.fileVideo!).lengthSync(), 3000);
  });
}
