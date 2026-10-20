import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:protocollo/protocollo.dart';

const _uso = '''
Telefono dell'atleta senza interfaccia, per provare l'app su un PC contro
coach_dev sulla rete Tor vera.

  dart run atleta_nucleo:atleta_dev --dati <cartella> --tor <eseguibile tor>
                                    [--verboso] [--log-tor <livelli>] <comando>

--verboso mostra il registro del nucleo e quello di tor; --log-tor ne sceglie
i livelli, nella sintassi dell'opzione Log di tor (predefinito "notice"; per
seguire anche i servizi onion: "[rend]info notice").

Comandi:
  invito <link>   legge l'invito e collega il telefono, fino alla prima sync
  sync            sincronizza con i coach collegati
  stato           coach collegati, ultima sync, log in attesa e problemi
  schede          schede ricevute
  allenamento     registra un allenamento sulla prima seduta ricevuta e
                  sincronizza

Ogni comando avvia tor e lo chiude alla fine. La cartella dati conserva
archivio, chiavi e stato di tor, così gli avvii successivi sono rapidi.''';

Future<void> main(List<String> argomenti) async {
  final opzioni = <String, String>{};
  final resto = <String>[];
  for (var i = 0; i < argomenti.length; i++) {
    final a = argomenti[i];
    if (a == '--verboso') {
      opzioni['verboso'] = '';
    } else if (a.startsWith('--') && i + 1 < argomenti.length) {
      opzioni[a.substring(2)] = argomenti[++i];
    } else {
      resto.add(a);
    }
  }
  final tor = opzioni['tor'];
  if (resto.isEmpty || tor == null) {
    stdout.writeln(_uso);
    exit(64);
  }
  final dati = opzioni['dati'] ?? 'dati_dev';
  final verboso = opzioni.containsKey('verboso');
  void registra(String riga) {
    if (verboso) stdout.writeln(riga);
  }

  await Directory(dati).create(recursive: true);
  final separatore = Platform.pathSeparator;
  final avviatore = AvviatoreTorProcesso(
    eseguibile: tor,
    cartellaDati: '$dati${separatore}tor',
    log: opzioni['log-tor'] ?? 'notice',
    registra: registra,
  );
  final archivio = ArchivioAtleta.apri('$dati${separatore}atleta.db');
  final nucleo = NucleoAtleta(
    archivio: archivio,
    cassaforte: _CassaforteFile('$dati${separatore}cassaforte'),
    // Su un PC il primo bootstrap, senza consenso in cache, può superare i
    // 60 s del telefono.
    tor: TrasportoTorControllato(
      avviatore,
      limiteBootstrap: const Duration(minutes: 3),
      registra: registra,
    ),
    dispositivo: const DatiDispositivo(
      nome: 'PC di prova (atleta_dev)',
      piattaforma: 'android',
      versioneApp: '1.0.0',
    ),
    registra: registra,
  );

  var codice = 0;
  try {
    codice = await _esegui(nucleo, resto.first, resto.skip(1).join(' '));
  } finally {
    await nucleo.chiudi();
    archivio.chiudi();
    await avviatore.ferma();
  }
  exit(codice);
}

final _cronometro = Stopwatch()..start();

void _tappa(String testo) {
  final t = _cronometro.elapsed;
  final minuti = t.inMinutes.toString().padLeft(2, '0');
  final secondi = (t.inSeconds % 60).toString().padLeft(2, '0');
  stdout.writeln('[$minuti:$secondi] $testo');
}

Future<int> _esegui(
  NucleoAtleta nucleo,
  String comando,
  String argomento,
) async {
  switch (comando) {
    case 'invito':
      return _collega(nucleo, argomento);
    case 'sync':
      return _sincronizza(nucleo);
    case 'stato':
      final coach = nucleo.collegamenti.elenco();
      if (coach.isEmpty) stdout.writeln('Nessun coach collegato.');
      for (final c in coach) {
        _stampaCoach(nucleo, c);
      }
      return 0;
    case 'schede':
      _schede(nucleo);
      return 0;
    case 'allenamento':
      return _allenamento(nucleo);
    default:
      stdout.writeln(_uso);
      return 64;
  }
}

Future<int> _collega(NucleoAtleta nucleo, String link) async {
  _tappa("Avvio di Tor e lettura dell'invito…");
  try {
    final invito = await nucleo.leggiInvito(link);
    _tappa(
      'Coach: ${invito.nomeCoach} (${invito.indirizzo}.onion). '
      'Collegamento in corso: la conferma può richiedere qualche minuto…',
    );
    final coach = await invito.collega();
    _tappa('Collegato come ${coach.nomeAtleta}.');
    _stampaCoach(nucleo, coach);
    return coach.problema == null ? 0 : 1;
  } on ErroreAbbinamento catch (e) {
    _tappa('Abbinamento non riuscito: ${e.messaggio}');
    return 1;
  }
}

Future<int> _sincronizza(NucleoAtleta nucleo) async {
  if (nucleo.collegamenti.attivi().isEmpty) {
    stdout.writeln('Nessun coach collegato: prima usa il comando invito.');
    return 1;
  }
  _tappa('Sync in corso…');
  final esiti = await nucleo.sync.sincronizzaTutti();
  for (final esito in esiti) {
    final coach = nucleo.collegamenti.cerca(esito.coachId)!;
    final risultato = switch (esito.problema) {
      final ProblemaSync problema => problema.messaggio,
      null => esito.completa ? 'riuscita, stato completo' : 'riuscita',
    };
    _tappa(
      '${coach.nomeCoach}: $risultato. Log confermati ${esito.logConfermati}, '
      'schede nuove ${esito.schedeNuove.length}.',
    );
  }
  return esiti.every((e) => e.riuscita) ? 0 : 1;
}

void _stampaCoach(NucleoAtleta nucleo, CoachCollegato coach) {
  stdout
    ..writeln(
      '- ${coach.nomeCoach} (${coach.stato.name}), '
      'atleta ${coach.nomeAtleta}',
    )
    ..writeln(
      '  ultima sync: ${coach.ultimaSync?.toLocal() ?? 'mai'}; '
      'log in attesa: ${coach.logInAttesa}; '
      'schede: ${nucleo.schede.elenco(coach.id).length}',
    );
  if (coach.problema case final problema?) {
    stdout.writeln('  problema: ${problema.messaggio}');
  }
}

void _schede(NucleoAtleta nucleo) {
  for (final coach in nucleo.collegamenti.elenco()) {
    stdout.writeln('${coach.nomeCoach}:');
    for (final scheda in [
      ...nucleo.schede.elenco(coach.id),
      ...nucleo.schede.elenco(coach.id, archiviate: true),
    ]) {
      final sedute = [
        for (final seduta in scheda.contenuto['sedute'] as List<Object?>)
          (seduta as Map<String, Object?>)['nome'],
      ];
      stdout.writeln(
        '  - ${scheda.titolo}, revisione ${scheda.revisione}'
        '${scheda.archiviata ? ', archiviata' : ''}: ${sedute.join(', ')}',
      );
    }
  }
}

Future<int> _allenamento(NucleoAtleta nucleo) async {
  final coach = nucleo.collegamenti.attivi().firstOrNull;
  if (coach == null) {
    stdout.writeln('Nessun coach collegato: prima usa il comando invito.');
    return 1;
  }
  final fine = DateTime.now();
  final inizio = fine.subtract(const Duration(minutes: 45));
  final scheda = nucleo.schede.elenco(coach.id).firstOrNull;
  final AllenamentoInCorso allenamento;
  if (scheda == null) {
    allenamento = AllenamentoInCorso.libero(inizio: inizio, coachId: coach.id);
    allenamento.aggiungiEsercizio('Corsa').serie.single
      ..durataS = 1800
      ..completata = true;
  } else {
    final seduta =
        (scheda.contenuto['sedute'] as List<Object?>).first
            as Map<String, Object?>;
    allenamento = AllenamentoInCorso.daSeduta(
      scheda,
      seduta['id'] as String,
      inizio: inizio,
    );
    for (final esercizio in allenamento.esercizi) {
      for (final serie in esercizio.serie) {
        serie.ripetizioni ??= 8;
        serie.completata = true;
      }
    }
  }
  allenamento
    ..note = 'Allenamento di prova da atleta_dev'
    ..rpe = 7;
  final log = nucleo.diario.salva(
    allenamento.coachId!,
    allenamento.contenuto(fine: fine),
  );
  _tappa('Salvato il log ${log.id}; sync in corso…');
  final esito = await nucleo.sync.sincronizza(coach.id);
  _tappa(
    esito.problema?.messaggio ??
        'Inviato: log confermati ${esito.logConfermati}.',
  );
  return esito.riuscita ? 0 : 1;
}

/// Cassaforte per le prove su un PC: una voce per file, in chiaro. Su un
/// telefono chiavi e token stanno nel Keystore o nel Keychain (§4).
class _CassaforteFile implements Cassaforte {
  _CassaforteFile(this._cartella);

  final String _cartella;

  File _file(String nome) =>
      File('$_cartella${Platform.pathSeparator}$nome.voce');

  @override
  Future<Uint8List?> leggi(String nome) async {
    final file = _file(nome);
    if (!await file.exists()) return null;
    return base64.decode((await file.readAsString()).trim());
  }

  @override
  Future<void> scrivi(String nome, List<int> valore) async {
    await Directory(_cartella).create(recursive: true);
    await _file(nome).writeAsString(base64.encode(valore), flush: true);
  }

  @override
  Future<void> elimina(String nome) async {
    final file = _file(nome);
    if (await file.exists()) await file.delete();
  }
}
