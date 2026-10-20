import 'dart:convert';

import 'package:protocollo/protocollo.dart';

import 'contesto.dart';
import 'errori.dart';
import 'guasti.dart';
import 'modelli.dart';
import 'problemi.dart';
import 'sincronizzazione.dart';
import 'tempo.dart';
import 'trasporto.dart';

/// Voce della cassaforte con la chiave del dispositivo per l'ultimo invito
/// usato e non ancora concluso.
const _voceAbbinamento = 'abbinamento_in_corso';

/// Pause tra i tentativi quando Tor non decifra il descrittore con la chiave
/// d'invito: in tutto quasi un minuto, quanto basta al programma del coach
/// per pubblicare un invito appena creato.
const _atteseDopoRifiuto = [
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(seconds: 30),
];

/// Punti 1–3 del §5.3: legge l'invito, prepara la chiave del dispositivo e,
/// con la chiave d'invito in Tor, chiede al coach il suo nome.
Future<InvitoLetto> leggiInvito(
  ContestoAtleta c,
  MotoreSync motore,
  String testo,
) async {
  final UriInvito invito;
  try {
    invito = UriInvito.analizza(testo);
  } on InvitoNonValido {
    throw const ErroreAbbinamento(ProblemaAbbinamento.codiceNonValido);
  } on VersioneInvitoSconosciuta {
    throw const ErroreAbbinamento(ProblemaAbbinamento.versioneInvito);
  }
  final chiave = await _chiaveDispositivo(c, invito);
  final info = await _conInvito(c, invito, (api) => api.info());
  if (!info.protocollo.any(versioniProtocollo.contains) ||
      confrontaVersioni(c.versioneApp, info.versioneAppMinima) < 0) {
    throw const ErroreAbbinamento(ProblemaAbbinamento.aggiornaApp);
  }
  return InvitoLetto._(c, motore, invito, chiave, info);
}

/// La chiave del dispositivo per [invito] (§5.3, punto 2). Se l'app aveva già
/// inviato una chiave per lo stesso invito, per esempio prima di perdere la
/// risposta e chiudersi, riusa quella: ripetere l'abbinamento con la stessa
/// chiave dà un token nuovo, con un'altra chiave darebbe 409.
Future<CoppiaX25519> _chiaveDispositivo(
  ContestoAtleta c,
  UriInvito invito,
) async {
  final salvata = await c.cassaforte.leggi(_voceAbbinamento);
  if (salvata != null) {
    try {
      final json = jsonDecode(utf8.decode(salvata));
      if (json case {
        'invito': final String id,
        'chiave': final String testo,
      } when id == invito.id) {
        final privata = decodificaChiave32(testo);
        if (privata != null) return CoppiaX25519.daPrivata(privata);
      }
    } on FormatException {
      // Voce illeggibile: si genera una chiave nuova.
    }
  }
  return CoppiaX25519.genera();
}

/// Esegue [chiamata] verso il coach dell'invito, con la chiave d'invito
/// configurata in Tor, e traduce gli errori nei casi del §5.4.
///
/// La chiave d'invito resta in Tor solo durante la chiamata: mentre l'atleta
/// decide, un collegamento già attivo con lo stesso coach continua a usare
/// la propria.
Future<T> _conInvito<T>(
  ContestoAtleta c,
  UriInvito invito,
  Future<T> Function(ClienteApi api) chiamata,
) async {
  if (!await c.rete.disponibile()) {
    throw const ErroreAbbinamento(ProblemaAbbinamento.offline);
  }
  try {
    await c.tor.avvia();
  } on TorNonParte {
    throw const ErroreAbbinamento(ProblemaAbbinamento.torNonParte);
  }
  await c.usaChiaveInvito(invito.indirizzo, decodificaChiave32(invito.chiave)!);
  try {
    var rifiuti = 0;
    var attese = 0;
    while (true) {
      final http = c.tor.creaHttpClient();
      try {
        return await chiamata(
          ClienteApi(indirizzo: invito.indirizzo, http: http),
        );
      } catch (e) {
        final guasto = classifica(e);
        switch (guasto?.tipo) {
          case null:
            rethrow;
          case TipoGuasto.chiaveRifiutata:
            // Appena creato l'invito, qualche directory può avere ancora il
            // descrittore di prima, senza la chiave d'invito: al tentativo
            // successivo Tor lo chiede a un'altra. Se la chiave continua a
            // non valere, il coach ha chiuso l'invito.
            c.registra(
              "Tor non decifra il descrittore con la chiave d'invito: $e",
            );
            if (rifiuti == _atteseDopoRifiuto.length) {
              throw const ErroreAbbinamento(
                ProblemaAbbinamento.invitoNonValido,
              );
            }
            await c.orologio.attendi(_atteseDopoRifiuto[rifiuti++]);
          case TipoGuasto.irraggiungibile:
            c.registra('Coach non raggiungibile: $e');
            throw const ErroreAbbinamento(
              ProblemaAbbinamento.coachIrraggiungibile,
            );
          case TipoGuasto.protocollo:
            c.registra('Risposta del coach non conforme al protocollo: $e');
            throw const ErroreAbbinamento(ProblemaAbbinamento.erroreImprevisto);
          case TipoGuasto.risposta:
            final errore = guasto!.errore!;
            final pausa = errore.riprovaTra ?? const Duration(seconds: 5);
            if ((errore.stato == 429 || errore.stato == 503) &&
                attese < 2 &&
                pausa <= const Duration(minutes: 1)) {
              attese++;
              await c.orologio.attendi(pausa);
              continue;
            }
            throw ErroreAbbinamento(switch (errore.stato) {
              410 => ProblemaAbbinamento.invitoNonValido,
              409 => ProblemaAbbinamento.invitoInUso,
              426 => ProblemaAbbinamento.aggiornaApp,
              429 || >= 500 => ProblemaAbbinamento.coachOccupato,
              _ => ProblemaAbbinamento.erroreImprevisto,
            });
        }
      } finally {
        http.close(force: true);
      }
    }
  } finally {
    await c.lasciaChiaveInvito(invito.indirizzo);
  }
}

/// Invito letto e verificato (§5.3, punti 1–3): l'app conosce il nome del
/// coach e aspetta che l'atleta confermi «Collegarti a [nomeCoach]?».
class InvitoLetto {
  InvitoLetto._(this._c, this._motore, this.invito, this._chiave, this.info);

  final ContestoAtleta _c;
  final MotoreSync _motore;
  final UriInvito invito;
  final CoppiaX25519 _chiave;

  /// Risposta di `GET /v1/info`.
  final RispostaInfo info;

  var _inCorso = false;
  var _concluso = false;

  String get nomeCoach => info.nomeCoach;

  /// Indirizzo onion del coach, senza ".onion".
  String get indirizzo => invito.indirizzo;

  /// Collegamento attivo con lo stesso coach, se c'è: il nuovo abbinamento
  /// lo sostituisce.
  CoachCollegato? get collegamentoAttuale {
    for (final coach in _c.coachAttivi()) {
      if (coach.indirizzo == indirizzo) return coach;
    }
    return null;
  }

  /// L'atleta ha confermato: abbina il telefono (punti 4–8).
  ///
  /// Restituisce il collegamento dopo la prima sync, che è completa. Se il
  /// coach non conferma entro 10 minuti il collegamento resta con
  /// [CoachCollegato.confermaInSospeso], e la conferma si ritenta a ogni
  /// sync. Il collegamento compare tra i coach, con un avviso in
  /// `NucleoAtleta.cambiamenti`, appena il coach ha emesso il token: chi non
  /// vuole aspettare la prima sync può seguirlo da lì.
  ///
  /// Lancia [ErroreAbbinamento]; dopo un errore si può chiamare di nuovo.
  /// Se l'atleta non conferma basta lasciar perdere l'invito letto.
  Future<CoachCollegato> collega() async {
    if (_inCorso || _concluso) throw StateError('Abbinamento già avviato');
    _inCorso = true;
    try {
      // La chiave va salvata prima di inviarla: se la risposta si perde e
      // l'app si chiude, rileggendo lo stesso invito l'abbinamento si ripete
      // con la stessa chiave (§5.3).
      await _c.cassaforte.scrivi(
        _voceAbbinamento,
        utf8.encode(
          jsonEncode({'invito': invito.id, 'chiave': _chiave.privataBase32}),
        ),
      );
      final risposta = await _conInvito(
        _c,
        invito,
        (api) => api.abbina(
          RichiestaAbbinamento(
            invitoId: invito.id,
            segreto: invito.segreto,
            chiaveDispositivo: _chiave.pubblicaBase32,
            dispositivo: _c.dispositivo,
          ),
        ),
      );
      final id = await _registra(risposta);
      _concluso = true;
      await _c.cassaforte.elimina(_voceAbbinamento);
      // Conferma con la chiave del dispositivo, poi la prima sync, completa
      // perché cursore ed epoca sono vuoti (punti 6–8).
      await _motore.sincronizza(id, dopoAbbinamento: true);
      return _c.coach(id)!;
    } finally {
      _inCorso = false;
    }
  }

  /// Punto 6: salva token e chiave, poi passa Tor alla chiave del dispositivo.
  /// Il descrittore in cache Tor l'ha già scartato quando [_conInvito] ha
  /// tolto la chiave d'invito: riavviarlo, come dice il punto 6, servirebbe
  /// solo a fargli dimenticare le directory già interrogate, che per 15
  /// minuti evita. Così i tentativi della conferma vanno ad altre directory.
  ///
  /// Se lo stesso atleta era già collegato a questo coach, per esempio prima
  /// di una revoca, il collegamento si riprende: la prima sync, completa,
  /// riallinea schede e log e reinvia quelli che il coach non ha.
  Future<int> _registra(RispostaAbbinamento risposta) async {
    final db = _c.db;
    final ora = istante(_c.orologio.adesso());
    var chiusi = <int>[];
    final esistente = db.select(
      'SELECT id FROM coach WHERE indirizzo = ? AND atleta_id = ?',
      [indirizzo, risposta.atletaId],
    ).firstOrNull;
    // Un collegamento nuovo nasce nella stessa esecuzione sincrona in cui si
    // prenota: nessuna sync può usarlo prima che le credenziali siano salvate.
    final int id;
    if (esistente != null) {
      id = esistente['id'] as int;
    } else {
      id = _c.archivio.transazione(() {
        chiusi = _chiudiAltri(risposta.atletaId);
        db.execute(
          'INSERT INTO coach (indirizzo, nome_coach, nome_atleta, atleta_id, '
          'dispositivo_id, stato, conferma_in_sospeso, abbinato_il) '
          "VALUES (?, ?, ?, ?, ?, 'attivo', 1, ?)",
          [
            indirizzo,
            risposta.nomeCoach,
            risposta.nomeAtleta,
            risposta.atletaId,
            risposta.dispositivoId,
            ora,
          ],
        );
        return db.lastInsertRowId;
      });
    }
    await _motore.inEsclusiva(id, () async {
      final altri = _c.archivio.transazione(() {
        final altri = _chiudiAltri(risposta.atletaId);
        db.execute(
          'UPDATE coach SET nome_coach = ?, nome_atleta = ?, dispositivo_id = ?, '
          "stato = 'attivo', conferma_in_sospeso = 1, abbinato_il = ?, "
          'epoca = NULL, cursore = NULL, problema = NULL, problema_il = NULL, '
          'rifiuti_chiave = 0 WHERE id = ?',
          [
            risposta.nomeCoach,
            risposta.nomeAtleta,
            risposta.dispositivoId,
            ora,
            id,
          ],
        );
        return altri;
      });
      await _c.salvaCredenziali(
        id,
        Credenziali(
          dispositivoId: risposta.dispositivoId,
          chiave: _chiave.privata,
          token: risposta.token,
        ),
      );
      for (final altro in {...chiusi, ...altri}) {
        await _c.eliminaCredenziali(altro);
      }
      await _c.impostaChiave(indirizzo, _chiave.privata);
    });
    _c.segnala(id);
    return id;
  }

  /// Chiude i collegamenti attivi con lo stesso coach come un altro atleta:
  /// Tor ha una sola chiave per indirizzo, quindi il telefono non potrebbe
  /// più usarli.
  List<int> _chiudiAltri(String atletaId) {
    final altri = [
      for (final riga in _c.db.select(
        "SELECT id FROM coach WHERE indirizzo = ? AND stato = 'attivo' "
        'AND atleta_id != ?',
        [indirizzo, atletaId],
      ))
        riga['id'] as int,
    ];
    for (final altro in altri) {
      _c.db.execute(
        "UPDATE coach SET stato = 'scollegato', problema = ?, problema_il = ? "
        'WHERE id = ?',
        [ProblemaSync.scollegato.name, istante(_c.orologio.adesso()), altro],
      );
    }
    return altri;
  }
}
