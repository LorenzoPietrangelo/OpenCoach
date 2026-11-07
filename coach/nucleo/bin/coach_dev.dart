import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:path/path.dart' as p;
import 'package:protocollo/protocollo.dart';

const _uso = '''
Programma del coach senza interfaccia, per lo sviluppo.

  dart run coach_nucleo:coach_dev --dati <cartella> [--tor <eseguibile tor>]
                                  [--nome <nome del coach>] [--verboso]

Comandi:
  atleta <nome>    crea l'atleta e mostra il suo invito
  invito <nome>    nuovo invito per un atleta esistente
  scheda <nome>    pubblica una scheda di prova per l'atleta
  video <esercizio> <link>
                   mette il video nella libreria e aggiorna le schede
  elenco           atleti, telefoni e inviti
  log <nome>       allenamenti ricevuti dall'atleta
  pesi <nome>      pesi che l'atleta condivide
  chat <nome>      la chat con l'atleta, con i video ricevuti
  scrivi <nome> <testo>
                   manda un messaggio all'atleta (nome di una parola)
  questionario <nome>
                   manda all'atleta un questionario di prova con 2 foto
  risposte <nome>  risposte ai questionari, con il peso delle foto
  telefono         nuovo QR del telefono del coach, come testo
  esci''';

Future<void> main(List<String> argomenti) async {
  final opzioni = _leggiOpzioni(argomenti);
  if (opzioni.containsKey('aiuto')) {
    stdout.writeln(_uso);
    return;
  }
  final dati = opzioni['dati'] ?? 'dati_dev';
  // Solo per lo sviluppo: le chiavi stanno in un file, non nel portachiavi.
  final programma = await ProgrammaCoach.avvia(
    cartellaDati: dati,
    portachiavi: PortachiaviFile(p.join(dati, 'portachiavi')),
    eseguibileTor: opzioni['tor'],
    registra: opzioni.containsKey('verboso') ? stdout.writeln : null,
  );
  final nucleo = programma.nucleo;
  if (opzioni['nome'] case final nome?) nucleo.nomeCoach = nome;
  if (nucleo.nomeCoach.isEmpty) nucleo.nomeCoach = 'Coach di prova';

  stdout
    ..writeln('Coach:      ${nucleo.nomeCoach}')
    ..writeln('Indirizzo:  ${programma.indirizzo}.onion')
    ..writeln('Porta HTTP: 127.0.0.1:${programma.portaLocale}')
    ..writeln(opzioni['tor'] == null ? 'Tor:        non avviato (manca --tor)' : '')
    ..writeln('Scrivi "aiuto" per i comandi.');
  programma.cambiamentiStatoTor.listen((s) => stdout.writeln('[tor] $s'));
  nucleo.eventi.listen((e) => stdout.writeln('[evento] ${_descrivi(nucleo, e)}'));

  unawaited(
    ProcessSignal.sigint.watch().first.then((_) async {
      await programma.chiudi();
      exit(0);
    }),
  );
  final righe = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final riga in righe) {
    final parole = riga.trim().split(RegExp(r'\s+'));
    final comando = parole.first;
    final nome = parole.skip(1).join(' ');
    if (comando == 'esci') break;
    try {
      switch (comando) {
        case '':
          break;
        case 'atleta':
          final atleta = nucleo.atleti.crea(nome);
          await _mostraInvito(nucleo, atleta.id);
        case 'invito':
          await _mostraInvito(nucleo, _atleta(nucleo, nome).id);
        case 'scheda':
          final atleta = _atleta(nucleo, nome);
          final id = nucleo.schede.crea(atleta.id, contenuto: _schedaDiProva());
          stdout.writeln('Pubblicata la revisione ${nucleo.schede.pubblica(id)}');
        case 'video' when parole.length >= 3:
          final esercizio = parole.sublist(1, parole.length - 1).join(' ');
          nucleo.libreria.salva(
            id: nucleo.libreria.perNome(esercizio)?.id,
            nome: esercizio,
            note: nucleo.libreria.perNome(esercizio)?.note ?? '',
            video: parole.last,
          );
          for (final scheda in nucleo.schede.conVideoDaAggiornare()) {
            stdout.writeln(
              '${scheda.titolo}: revisione ${nucleo.schede.aggiornaVideo(scheda.id)}',
            );
          }
        case 'elenco':
          for (final r in nucleo.atleti.elenco()) {
            final d = r.dispositivo;
            stdout.writeln(
              '- ${r.atleta.nome}: '
              '${d == null ? 'nessun telefono' : '${d.nome} (app ${d.versioneApp}, '
                        'ultimo contatto ${d.ultimoContatto?.toLocal() ?? 'mai'})'}'
              '${r.invito == null ? '' : ', invito ${r.invito!.stato.nome}'}',
            );
          }
        case 'questionario':
          final atleta = _atleta(nucleo, nome);
          final modello = nucleo.questionari.modelli().firstOrNull?.id ??
              nucleo.questionari.creaModello(_questionarioDiProva());
          stdout.writeln('Mandato il questionario ${nucleo.questionari.invia(modello, atleta.id)}');
        case 'risposte':
          for (final q in nucleo.questionari.inviati(_atleta(nucleo, nome).id)) {
            stdout.writeln(
              '- ${q.titolo}: ${q.stato.name}'
              '${q.risposta == null ? '' : ' ${jsonEncode(q.risposta!['risposte'])}'}'
              '${q.foto.isEmpty ? '' : ', foto ${[for (final f in q.foto) '${nucleo.questionari.foto(f)?.length} byte'].join(', ')}'}',
            );
          }
        case 'chat':
          final atleta = _atleta(nucleo, nome);
          for (final m in nucleo.messaggi.conversazione(atleta.id)) {
            final file = nucleo.messaggi.fileVideo(atleta.id, m);
            stdout.writeln(
              '- ${m.dalCoach ? 'coach' : 'atleta'}: ${m.testo}'
              '${m.video == null ? '' : ' [video ${m.durataVideoS} s, ${file?.lengthSync() ?? 'mancante'} byte'
                        '${m.riferimento == null ? '' : ', ${m.riferimento!['esercizio']} serie ${m.riferimento!['serie']}'}]'}',
            );
          }
        case 'scrivi' when parole.length >= 3:
          nucleo.messaggi.invia(_atleta(nucleo, parole[1]).id, parole.skip(2).join(' '));
          stdout.writeln('Messaggio mandato');
        case 'pesi':
          final pesi = nucleo.pesi.elenco(_atleta(nucleo, nome).id);
          stdout.writeln(
            pesi.isEmpty
                ? 'Nessun peso condiviso'
                : [for (final p in pesi) '${formattaData(p.giorno)} ${p.kg} kg'].join(', '),
          );
        case 'telefono':
          final invito = await nucleo.telefonoCoach.creaInvito();
          stdout
            ..writeln('Valido fino a ${invito.scadeIl.toLocal()}:')
            ..writeln(invito.uri);
        case 'log':
          final atleta = _atleta(nucleo, nome);
          for (final a in nucleo.allenamenti.elenco(atleta.id)) {
            stdout.writeln('- ${a.eseguitoIl.toLocal()} rev ${a.rev}: ${jsonEncode(a.contenuto)}');
          }
        default:
          stdout.writeln(_uso);
      }
    } on OperazioneNonValida catch (e) {
      stdout.writeln('Errore: ${e.messaggio}');
    }
  }

  await programma.chiudi();
  exit(0);
}

Future<void> _mostraInvito(NucleoCoach nucleo, String atletaId) async {
  final invito = await nucleo.inviti.crea(atletaId);
  stdout
    ..writeln('Invito valido fino a ${invito.scadeIl.toLocal()}:')
    ..writeln(invito.uri);
}

Atleta _atleta(NucleoCoach nucleo, String nome) {
  for (final r in [...nucleo.atleti.elenco(), ...nucleo.atleti.elenco(archiviati: true)]) {
    if (r.atleta.nome.toLowerCase() == nome.toLowerCase()) return r.atleta;
  }
  throw OperazioneNonValida('Nessun atleta di nome "$nome"');
}

String _descrivi(NucleoCoach nucleo, EventoCoach e) {
  final atleta = nucleo.atleti.cerca(e.atletaId)?.nome ?? e.atletaId;
  return switch (e) {
    DispositivoAbbinato(:final nomeDispositivo) => '$atleta ha abbinato $nomeDispositivo',
    AbbinamentoConfermato() => '$atleta ha confermato l\'abbinamento',
    InvitoContestato() => 'ATTENZIONE: un secondo telefono ha usato l\'invito di $atleta',
    LogRicevuto(:final logId, :final eliminato) =>
      '$atleta ha ${eliminato ? 'eliminato' : 'inviato'} il log $logId',
    RevisioneRicevuta(:final revisione) => '$atleta ha ricevuto la revisione $revisione',
    DispositivoSincronizzato() => '$atleta ha sincronizzato',
    QuestionarioRisposto(:final titolo) => '$atleta ha risposto a «$titolo»',
    MessaggioRicevuto(:final conVideo) => '$atleta ha scritto in chat${conVideo ? ', con un video' : ''}',
    TelefonoCoachCollegato(:final nomeTelefono) => 'Telefono del coach collegato: $nomeTelefono',
    TelefonoCoachConfermato() => 'Il telefono del coach ha confermato il collegamento',
    TelefonoCoachContestato() => 'ATTENZIONE: un secondo telefono ha usato il QR del telefono del coach',
    ModificaDalTelefonoCoach() => 'Modifica dal telefono del coach: $atleta',
  };
}

Map<String, Object?> _schedaDiProva() => {
  'titolo': 'Scheda di prova',
  'note': 'Creata da coach_dev',
  'valida_dal': formattaData(DateTime.now()),
  'sedute': [
    {
      'id': nuovoUuid(),
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

Map<String, String> _leggiOpzioni(List<String> argomenti) {
  final opzioni = <String, String>{};
  for (var i = 0; i < argomenti.length; i++) {
    final a = argomenti[i];
    if (a == '--verboso' || a == '--aiuto' || a == '-h') {
      opzioni[a == '-h' ? 'aiuto' : a.substring(2)] = '';
    } else if (a.startsWith('--') && i + 1 < argomenti.length) {
      opzioni[a.substring(2)] = argomenti[++i];
    }
  }
  return opzioni;
}

Map<String, Object?> _questionarioDiProva() => {
  'titolo': 'Check mensile',
  'descrizione': 'Come è andato il mese? Rispondi con calma.',
  'domande': [
    {
      'id': nuovoUuid(),
      'tipo': 'scelta_singola',
      'testo': 'Quanti giorni a settimana ti sei allenato?',
      'obbligatoria': true,
      'opzioni': ['2 giorni', '3 giorni', '4 giorni'],
      'altro': true,
    },
    {
      'id': nuovoUuid(),
      'tipo': 'numero',
      'testo': 'Quanto pesi?',
      'obbligatoria': true,
      'unita': 'kg',
      'peso_corporeo': true,
    },
    {'id': nuovoUuid(), 'tipo': 'scala', 'testo': 'Energia durante gli allenamenti', 'obbligatoria': false},
    {'id': nuovoUuid(), 'tipo': 'testo_lungo', 'testo': 'Infortuni o fastidi?', 'obbligatoria': false},
  ],
  'foto': {'numero': 2, 'istruzioni': 'Corpo intero, di fronte e di schiena.'},
};
