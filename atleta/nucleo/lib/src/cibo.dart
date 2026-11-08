import 'dart:convert';

import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'errori.dart';

/// Un alimento da aggiungere al diario: nome e valori, senza il pasto e la
/// porzione. Viene dal catalogo del coach, dai cibi già usati o lo scrive
/// l'atleta.
class AlimentoCibo {
  const AlimentoCibo({
    required this.nome,
    required this.per100g,
    required this.fonte,
    this.marca,
    this.codice,
    this.porzioneG,
  });

  final String nome;
  final String? marca;
  final String? codice;
  final String fonte;
  final ValoriCibo per100g;

  /// La porzione della confezione, se la si conosce.
  final double? porzioneG;

  /// Un prodotto del catalogo del coach (§10.3).
  factory AlimentoCibo.daProdotto(ProdottoCibo p) => AlimentoCibo(
    nome: p.nome,
    marca: p.marca,
    codice: p.codice,
    porzioneG: p.porzioneG,
    fonte: FonteCibo.openFoodFacts,
    per100g: p.per100g,
  );

  /// Lo stesso alimento con valori scritti o corretti dall'atleta.
  AlimentoCibo conValori(ValoriCibo valori) => AlimentoCibo(
    nome: nome,
    marca: marca,
    codice: codice,
    porzioneG: porzioneG,
    fonte: FonteCibo.atleta,
    per100g: valori,
  );
}

/// Il diario del cibo dell'atleta, una giornata al giorno (§8.8).
///
/// Come il peso, il cibo è dell'atleta e non di un coach: l'atleta sceglie
/// con quali coach condividerlo, e per ognuno l'app ricorda l'ultima `rev` di
/// ogni giornata che il coach ha confermato.
class RegistroCibo {
  RegistroCibo(this._c, {required void Function(int coachId) cambiato}) : _cambiato = cambiato;

  final ContestoAtleta _c;
  final void Function(int coachId) _cambiato;

  Database get _db => _c.db;

  /// La giornata del [giorno], vuota se l'atleta non ha registrato niente.
  GiornataCibo giornata(DateTime giorno) {
    final riga = _db.select('SELECT voci FROM giornate WHERE giorno = ? AND eliminato = 0', [
      formattaData(giorno),
    ]).firstOrNull;
    return GiornataCibo(giorno: _soloGiorno(giorno), voci: riga == null ? const [] : _voci(riga));
  }

  /// Le giornate registrate, dalla più vecchia.
  List<GiornataCibo> elenco() => [
    for (final riga in _db.select('SELECT giorno, voci FROM giornate WHERE eliminato = 0 ORDER BY giorno'))
      GiornataCibo(giorno: analizzaData(riga['giorno'])!, voci: _voci(riga)),
  ];

  /// I cibi già usati, dal più recente: ogni alimento aggiunto al diario
  /// resta sul telefono, con l'ultima porzione, e si ritrova senza chiederlo
  /// al coach.
  List<AlimentoCibo> recenti({int massimo = 30}) => [
    for (final riga in _db.select('SELECT * FROM alimenti ORDER BY uso DESC LIMIT ?', [massimo])) _alimento(riga),
  ];

  /// I cibi già usati che contengono tutte le parole di [testo], anche come
  /// inizio di parola, senza badare ad accenti e maiuscole.
  List<AlimentoCibo> cercaSalvati(String testo, {int massimo = 30}) {
    final parole = _parole(testo);
    if (parole.isEmpty) return const [];
    final trovati = <AlimentoCibo>[];
    for (final riga in _db.select('SELECT * FROM alimenti ORDER BY uso DESC')) {
      final sue = _parole('${riga['nome']} ${riga['marca'] ?? ''}');
      if (parole.every((p) => sue.any((s) => s.startsWith(p)))) {
        trovati.add(_alimento(riga));
        if (trovati.length >= massimo) break;
      }
    }
    return trovati;
  }

  /// Il cibo già usato con il codice a barre [codice], o null.
  AlimentoCibo? salvatoPerCodice(String codice) {
    final riga = _db.select('SELECT * FROM alimenti WHERE codice = ? ORDER BY uso DESC LIMIT 1', [
      codice,
    ]).firstOrNull;
    return riga == null ? null : _alimento(riga);
  }

  /// Aggiunge [grammi] di [alimento] al [pasto] del [giorno]. Lancia
  /// [OperazioneNonAmmessa] se i valori sono fuori dagli intervalli del
  /// protocollo, il giorno è nel futuro o la giornata è piena.
  void aggiungi(DateTime giorno, String pasto, AlimentoCibo alimento, double grammi) {
    final voce = VoceCibo(
      id: nuovoUuid(),
      pasto: pasto,
      nome: alimento.nome.trim(),
      marca: switch (alimento.marca?.trim()) {
        final String m when m.isNotEmpty => m,
        _ => null,
      },
      codice: alimento.codice,
      fonte: alimento.fonte,
      grammi: (grammi * 10).round() / 10,
      per100g: alimento.per100g,
    );
    _scrivi(giorno, [...giornata(giorno).voci, voce]);
    _ricorda(voce);
  }

  /// Salva l'alimento della [voce] tra i cibi già usati, con la sua porzione.
  void _ricorda(VoceCibo voce) {
    final chiave = voce.codice ?? 'n:${voce.nome.toLowerCase()}|${(voce.marca ?? '').toLowerCase()}';
    _db.execute(
      'INSERT OR REPLACE INTO alimenti (chiave, nome, marca, codice, fonte, per_100g, porzione, uso) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, (SELECT COALESCE(MAX(uso), 0) + 1 FROM alimenti))',
      [
        chiave,
        voce.nome,
        voce.marca,
        voce.codice,
        voce.fonte,
        jsonEncode(voce.per100g.toJson()),
        voce.grammi,
      ],
    );
  }

  /// Cambia i grammi di una voce.
  void cambiaGrammi(DateTime giorno, String voceId, double grammi) => _scrivi(giorno, [
    for (final v in giornata(giorno).voci)
      v.id == voceId
          ? VoceCibo(
              id: v.id,
              pasto: v.pasto,
              nome: v.nome,
              marca: v.marca,
              codice: v.codice,
              fonte: v.fonte,
              grammi: (grammi * 10).round() / 10,
              per100g: v.per100g,
            )
          : v,
  ]);

  /// Toglie una voce. Una giornata senza voci si elimina, e i coach che
  /// l'avevano la cancellano alla sync successiva.
  void elimina(DateTime giorno, String voceId) =>
      _scrivi(giorno, [for (final v in giornata(giorno).voci) if (v.id != voceId) v]);

  /// L'obiettivo che il coach [coachId] ha fissato, o null.
  ObiettivoCibo? obiettivo(int coachId) {
    final testo = _db.select('SELECT obiettivo_cibo FROM coach WHERE id = ?', [
      coachId,
    ]).firstOrNull?['obiettivo_cibo'];
    return testo is String
        ? ObiettivoCibo.fromJson(jsonDecode(testo) as Map<String, Object?>)
        : null;
  }

  /// Condivide o smette di condividere il cibo con il coach. Smettendo, alla
  /// sync successiva il coach cancella le giornate che ha; ricominciando, le
  /// riceve di nuovo tutte.
  void condividi(int coachId, {required bool condividi}) {
    _c.archivio.transazione(() {
      _db.execute('UPDATE coach SET condividi_cibo = ? WHERE id = ?', [condividi ? 1 : 0, coachId]);
      _db.execute('DELETE FROM giornate_inviate WHERE coach_id = ?', [coachId]);
    });
    _c.segnala(coachId);
    _cambiato(coachId);
  }

  void _scrivi(DateTime giorno, List<VoceCibo> voci) {
    if (_soloGiorno(giorno).isAfter(_soloGiorno(_c.orologio.adesso()))) {
      throw const OperazioneNonAmmessa('Il giorno è nel futuro');
    }
    final chiave = formattaData(giorno);
    final ora = formattaDataOra(_c.orologio.adesso());
    final json = [for (final v in voci) v.toJson()];
    if (voci.isNotEmpty) {
      final prova = {
        'id': nuovoUuid(),
        'rev': 1,
        'eliminato': false,
        'giorno': chiave,
        'voci': json,
        'modificato_il': ora,
      };
      final errori = validaGiornata(prova);
      if (errori.isNotEmpty) throw OperazioneNonAmmessa('Valori non validi: ${errori.first}');
      if (dimensioneJson(prova) > LimitiCibo.giornataMassima) {
        throw const OperazioneNonAmmessa('La giornata è piena');
      }
    }
    _c.archivio.transazione(() {
      final esistente = _db.select('SELECT eliminato FROM giornate WHERE giorno = ?', [
        chiave,
      ]).firstOrNull;
      if (esistente == null) {
        if (voci.isEmpty) return;
        _db.execute(
          'INSERT INTO giornate (giorno, id, rev, eliminato, voci, modificato_il) '
          'VALUES (?, ?, 1, 0, ?, ?)',
          [chiave, nuovoUuid(), jsonEncode(json), ora],
        );
      } else {
        if (voci.isEmpty && esistente['eliminato'] == 1) return;
        // Lo stesso giorno tiene lo stesso id, anche dopo un'eliminazione.
        _db.execute(
          'UPDATE giornate SET rev = rev + 1, eliminato = ?, voci = ?, modificato_il = ? '
          'WHERE giorno = ?',
          [voci.isEmpty ? 1 : 0, voci.isEmpty ? null : jsonEncode(json), ora, chiave],
        );
      }
    });
    for (final coach in _c.coachAttivi()) {
      if (coach.condivideCibo) {
        _c.segnala(coach.id);
        _cambiato(coach.id);
      }
    }
  }

  static AlimentoCibo _alimento(Row r) => AlimentoCibo(
    nome: r['nome'] as String,
    marca: r['marca'] as String?,
    codice: r['codice'] as String?,
    fonte: r['fonte'] as String,
    porzioneG: (r['porzione'] as num?)?.toDouble(),
    per100g: ValoriCibo.fromJson(jsonDecode(r['per_100g'] as String) as Map<String, Object?>),
  );

  /// Le parole di [testo] in minuscolo e senza accenti.
  static List<String> _parole(String testo) {
    final senzaAccenti = testo.toLowerCase().split('').map((c) => _accenti[c] ?? c).join();
    return [for (final m in RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(senzaAccenti)) m[0]!];
  }

  static const _accenti = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };

  static List<VoceCibo> _voci(Row riga) => [
    for (final voce in jsonDecode(riga['voci'] as String) as List<Object?>)
      VoceCibo.fromJson(voce! as Map<String, Object?>),
  ];

  static DateTime _soloGiorno(DateTime t) => DateTime(t.year, t.month, t.day);
}

/// Giornate da mandare al coach (§8.8): quelle con una `rev` che non ha
/// ancora confermato, tranne le eliminazioni di giornate che non ha mai
/// ricevuto. Al massimo [massimo] e [byte] byte, ma sempre almeno una se ce
/// ne sono.
List<Map<String, Object?>> giornateInCoda(
  Database db,
  int coachId, {
  int massimo = LimitiCibo.giornatePerRichiesta,
  int byte = 1024 * 1024,
}) {
  final risultato = <Map<String, Object?>>[];
  var usati = 0;
  for (final riga in db.select(
    'SELECT giornate.* FROM giornate LEFT JOIN giornate_inviate inviate '
    'ON inviate.coach_id = ? AND inviate.giornata_id = giornate.id '
    'WHERE giornate.rev > COALESCE(inviate.rev, 0) '
    'AND NOT (giornate.eliminato = 1 AND inviate.rev IS NULL) '
    'ORDER BY giornate.giorno LIMIT ?',
    [coachId, massimo],
  )) {
    final giornata = riga['eliminato'] == 1
        ? <String, Object?>{'id': riga['id'], 'rev': riga['rev'], 'eliminato': true}
        : <String, Object?>{
            'id': riga['id'],
            'rev': riga['rev'],
            'eliminato': false,
            'giorno': riga['giorno'],
            'voci': jsonDecode(riga['voci'] as String),
            'modificato_il': riga['modificato_il'],
          };
    final dimensione = dimensioneJson(giornata);
    if (risultato.isNotEmpty && usati + dimensione > byte) break;
    risultato.add(giornata);
    usati += dimensione;
  }
  return risultato;
}
