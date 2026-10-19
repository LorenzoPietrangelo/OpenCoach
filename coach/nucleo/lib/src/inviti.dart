import 'package:protocollo/protocollo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'contesto.dart';
import 'errori.dart';
import 'modelli.dart';
import 'tempo.dart';

/// Inviti per abbinare un telefono a un atleta (§5.1).
class GestioneInviti {
  GestioneInviti(this._c);

  final ContestoCoach _c;

  static const durataPredefinita = Duration(days: 7);
  static const durataMinima = Duration(hours: 1);
  static const durataMassima = Duration(days: 30);

  Database get _db => _c.archivio.db;

  /// Crea un invito per [atletaId] e annulla quello precedente.
  Future<Invito> crea(
    String atletaId, {
    Duration durata = durataPredefinita,
  }) async {
    if (durata < durataMinima || durata > durataMassima) {
      throw const OperazioneNonValida(
        "La scadenza dell'invito deve essere tra 1 ora e 30 giorni",
      );
    }
    final coppia = await CoppiaX25519.genera();
    final id = codificaBase32(byteCasuali(16));
    final segreto = codificaBase32(byteCasuali(32));
    final creatoIl = _c.adesso().toUtc();
    final scadeIl = creatoIl.add(durata);

    _c.archivio.transazione(() {
      final atleta = _db.select('SELECT stato FROM atleti WHERE id = ?', [
        atletaId,
      ]).firstOrNull;
      if (atleta == null) throw const OperazioneNonValida('Atleta inesistente');
      if (atleta['stato'] == 'archiviato') {
        throw const OperazioneNonValida("L'atleta è archiviato");
      }
      _chiudi(
        "atleta_id = ? AND stato IN ('aperto', 'in_abbinamento')",
        [atletaId],
        StatoInvito.annullato,
      );
      if (contaChiaviAutorizzate() >= Limiti.chiaviAutorizzate) {
        throw const OperazioneNonValida(
          'Raggiunto il numero massimo di telefoni e inviti attivi',
        );
      }
      _db.execute(
        'INSERT INTO inviti (id, atleta_id, segreto, chiave_privata, '
        'chiave_pubblica, creato_il, scade_il, stato) '
        "VALUES (?, ?, ?, ?, ?, ?, ?, 'aperto')",
        [
          id,
          atletaId,
          segreto,
          coppia.privataBase32,
          coppia.pubblicaBase32,
          istante(creatoIl),
          istante(scadeIl),
        ],
      );
    });
    _c.segnalaChiaviCambiate();
    return Invito(
      id: id,
      atletaId: atletaId,
      stato: StatoInvito.aperto,
      creatoIl: creatoIl,
      scadeIl: scadeIl,
      uri: UriInvito(
        indirizzo: _c.indirizzo,
        id: id,
        segreto: segreto,
        chiave: coppia.privataBase32,
      ),
    );
  }

  /// Invito aperto o in abbinamento dell'atleta, se c'è e non è scaduto.
  Invito? inCorso(String atletaId) {
    final riga = _db.select(
      'SELECT * FROM inviti WHERE atleta_id = ? '
      "AND stato IN ('aperto', 'in_abbinamento') AND scade_il > ?",
      [atletaId, istante(_c.adesso())],
    ).firstOrNull;
    return riga == null ? null : _daRiga(riga);
  }

  /// Annulla l'invito. Un telefono già abbinato con esso resta collegato.
  void annulla(String invitoId) {
    final chiusi = _chiudi(
      "id = ? AND stato IN ('aperto', 'in_abbinamento')",
      [invitoId],
      StatoInvito.annullato,
    );
    if (chiusi > 0) _c.segnalaChiaviCambiate();
  }

  /// Chiude gli inviti scaduti; restituisce quanti ne ha chiusi.
  int chiudiScaduti() {
    final chiusi = _chiudi(
      "stato IN ('aperto', 'in_abbinamento') AND scade_il <= ?",
      [istante(_c.adesso())],
      StatoInvito.scaduto,
    );
    if (chiusi > 0) _c.segnalaChiaviCambiate();
    return chiusi;
  }

  /// Chiavi pubbliche X25519 che il servizio onion deve autorizzare:
  /// inviti in corso e dispositivi attivi (§6.1).
  List<String> chiaviAutorizzate() => [
    for (final riga in _db.select(
      'SELECT chiave_pubblica FROM inviti '
      "WHERE stato IN ('aperto', 'in_abbinamento') AND scade_il > ? "
      'UNION '
      "SELECT chiave_pubblica FROM dispositivi WHERE stato = 'attivo' "
      'ORDER BY chiave_pubblica',
      [istante(_c.adesso())],
    ))
      riga['chiave_pubblica'] as String,
  ];

  int contaChiaviAutorizzate() => chiaviAutorizzate().length;

  /// Chiude gli inviti che rispettano [condizione] e cancella i loro segreti.
  int _chiudi(String condizione, List<Object?> parametri, StatoInvito stato) {
    _db.execute(
      'UPDATE inviti SET stato = ?, segreto = NULL, chiave_privata = NULL '
      'WHERE $condizione',
      [stato.nome, ...parametri],
    );
    return _db.updatedRows;
  }

  Invito _daRiga(Row r) {
    final stato = StatoInvito.daNome(r['stato'] as String);
    final segreto = r['segreto'] as String?;
    final chiave = r['chiave_privata'] as String?;
    return Invito(
      id: r['id'] as String,
      atletaId: r['atleta_id'] as String,
      stato: stato,
      creatoIl: leggiIstante(r['creato_il'] as String),
      scadeIl: leggiIstante(r['scade_il'] as String),
      uri: stato == StatoInvito.aperto && segreto != null && chiave != null
          ? UriInvito(
              indirizzo: _c.indirizzo,
              id: r['id'] as String,
              segreto: segreto,
              chiave: chiave,
            )
          : null,
    );
  }
}
