import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:protocollo/protocollo.dart';
import 'package:trasporto_tor/trasporto_tor.dart';

import 'cassaforte.dart';
import 'fonte_dati.dart';
import 'fonte_remota.dart';

const _voceCredenziali = 'telefono_coach';
const _voceInCorso = 'collegamento_in_corso';

/// Il telefono collegato al PC del coach (§16.2).
class Credenziali {
  const Credenziali({
    required this.indirizzo,
    required this.token,
    required this.chiavePrivata,
    required this.nomeCoach,
    required this.confermato,
  });

  final String indirizzo;
  final String token;

  /// Chiave privata X25519, in base32.
  final String chiavePrivata;
  final String nomeCoach;

  /// Il PC sa che il telefono usa ormai la propria chiave.
  final bool confermato;

  Uint8List get chiaveInByte => decodificaChiave32(chiavePrivata)!;

  Credenziali confermate() => Credenziali(
    indirizzo: indirizzo,
    token: token,
    chiavePrivata: chiavePrivata,
    nomeCoach: nomeCoach,
    confermato: true,
  );

  Map<String, Object?> toJson() => {
    'indirizzo': indirizzo,
    'token': token,
    'chiave': chiavePrivata,
    'nome_coach': nomeCoach,
    'confermato': confermato,
  };

  static Credenziali? daJson(Object? json) {
    if (json case {
      'indirizzo': final String indirizzo,
      'token': final String token,
      'chiave': final String chiave,
      'nome_coach': final String nomeCoach,
      'confermato': final bool confermato,
    } when decodificaChiave32(chiave) != null) {
      return Credenziali(
        indirizzo: indirizzo,
        token: token,
        chiavePrivata: chiave,
        nomeCoach: nomeCoach,
        confermato: confermato,
      );
    }
    return null;
  }
}

/// Perché il telefono non si è collegato.
enum ProblemaCollegamento {
  /// Non è un QR del programma del coach.
  codiceNonValido,

  /// Il QR o il programma chiedono un'app più recente.
  aggiornaApp,

  /// QR scaduto, annullato o già usato.
  qrNonValido,

  /// Un altro telefono ha già usato questo QR.
  qrInUso,

  /// Il telefono è offline o la rete blocca Tor.
  torNonParte,

  /// Il PC non si trova: deve essere acceso con il programma aperto.
  pcIrraggiungibile,

  inatteso,
}

class ErroreCollegamento implements Exception {
  const ErroreCollegamento(this.problema);

  final ProblemaCollegamento problema;

  @override
  String toString() => 'ErroreCollegamento(${problema.name})';
}

/// A che punto è la lettura del QR, per l'interfaccia.
enum FaseCollegamento { avvioTor, ricercaPc, attesaPc, collegamento }

/// Il QR è valido e il PC ha risposto: manca che il coach confermi il nome.
class QrLetto {
  QrLetto._(this._servizio, this._uri, this._coppia, this.nomeCoach);

  final ServizioCollegamento _servizio;
  final UriTelefonoCoach _uri;
  final CoppiaX25519 _coppia;
  final String nomeCoach;

  Future<Credenziali> conferma({void Function(FaseCollegamento)? avanzamento}) =>
      _servizio._abbina(_uri, _coppia, avanzamento);

  /// Il coach ha cambiato idea: la chiave del QR esce da Tor.
  Future<void> annulla() => _servizio._tor.rimuoviChiave(_uri.indirizzo);
}

/// Il collegamento del telefono al PC, come per il telefono di un atleta
/// (§5.3, §16.2). Un PC appena avvisato può metterci un paio di minuti a
/// pubblicare il QR: nel frattempo si ritenta.
class ServizioCollegamento {
  ServizioCollegamento({
    required Cassaforte cassaforte,
    required TrasportoTor tor,
    required this.dispositivo,
    Orologio orologio = const OrologioDiSistema(),
    this.durateTentativi = const [Duration(seconds: 30), Duration(seconds: 45), Duration(seconds: 60)],
    this.attesaMassima = const Duration(minutes: 2),
  }) : _cassaforte = cassaforte,
       _tor = tor,
       _orologio = orologio;

  final Cassaforte _cassaforte;
  final TrasportoTor _tor;
  final Orologio _orologio;
  final DatiDispositivo dispositivo;

  /// Quanto aspetta ogni tentativo: una connessione a volte resta appesa,
  /// mentre una nuova riesce in pochi secondi (§6.2).
  final List<Duration> durateTentativi;
  final Duration attesaMassima;

  static const _pause = [Duration(seconds: 5), Duration(seconds: 10), Duration(seconds: 20), Duration(seconds: 30)];

  Future<Credenziali?> caricaCredenziali() async =>
      Credenziali.daJson(await leggiJson(_cassaforte, _voceCredenziali));

  Future<void> salvaCredenziali(Credenziali credenziali) =>
      _cassaforte.scrivi(_voceCredenziali, jsonEncode(credenziali.toJson()));

  Future<void> cancellaCredenziali() async {
    await _cassaforte.elimina(_voceCredenziali);
    await _cassaforte.elimina(_voceInCorso);
  }

  /// Legge il QR e chiede al PC il nome del coach (§5.3, punti 1-3).
  Future<QrLetto> leggi(String testo, {void Function(FaseCollegamento)? avanzamento}) async {
    final UriTelefonoCoach uri;
    try {
      uri = UriTelefonoCoach.analizza(testo);
    } on InvitoNonValido {
      throw const ErroreCollegamento(ProblemaCollegamento.codiceNonValido);
    } on VersioneInvitoSconosciuta {
      throw const ErroreCollegamento(ProblemaCollegamento.aggiornaApp);
    }
    final coppia = await _chiave(uri);
    avanzamento?.call(FaseCollegamento.avvioTor);
    try {
      await _tor.avvia();
    } on TorNonParte {
      throw const ErroreCollegamento(ProblemaCollegamento.torNonParte);
    }
    await _tor.impostaChiave(uri.indirizzo, decodificaChiave32(uri.chiave)!);
    final info = await _conRitentativi(
      uri,
      (api) => api.info(),
      FaseCollegamento.ricercaPc,
      avanzamento,
    );
    if (!info.protocollo.any(versioniProtocollo.contains) ||
        confrontaVersioni(dispositivo.versioneApp, info.versioneAppMinima) < 0) {
      throw const ErroreCollegamento(ProblemaCollegamento.aggiornaApp);
    }
    return QrLetto._(this, uri, coppia, info.nomeCoach);
  }

  /// La chiave per [uri]. Se l'app ne aveva già mandata una per lo stesso QR,
  /// per esempio prima di perdere la risposta, riusa quella: con un'altra il PC
  /// risponderebbe che il QR è già in uso.
  Future<CoppiaX25519> _chiave(UriTelefonoCoach uri) async {
    final salvata = await leggiJson(_cassaforte, _voceInCorso);
    if (salvata case {'invito': final String id, 'chiave': final String chiave} when id == uri.id) {
      final privata = decodificaChiave32(chiave);
      if (privata != null) return CoppiaX25519.daPrivata(privata);
    }
    return CoppiaX25519.genera();
  }

  /// Punti 4-6 del §5.3. La conferma, che può aspettare che il PC ripubblichi
  /// il servizio, la fa poi lo stato dell'app.
  Future<Credenziali> _abbina(
    UriTelefonoCoach uri,
    CoppiaX25519 coppia,
    void Function(FaseCollegamento)? avanzamento,
  ) async {
    await _cassaforte.scrivi(_voceInCorso, jsonEncode({'invito': uri.id, 'chiave': coppia.privataBase32}));
    final risposta = await _conRitentativi(
      uri,
      (api) => api.abbinaTelefonoCoach(
        RichiestaAbbinamento(
          invitoId: uri.id,
          segreto: uri.segreto,
          chiaveDispositivo: coppia.pubblicaBase32,
          dispositivo: dispositivo,
        ),
      ),
      FaseCollegamento.collegamento,
      avanzamento,
    );
    final credenziali = Credenziali(
      indirizzo: uri.indirizzo,
      token: risposta.token,
      chiavePrivata: coppia.privataBase32,
      nomeCoach: risposta.nomeCoach,
      confermato: false,
    );
    await salvaCredenziali(credenziali);
    await _cassaforte.elimina(_voceInCorso);
    // Togliere la chiave fa scartare a Tor il descrittore in cache (§5.3, punto 6).
    await _tor.rimuoviChiave(uri.indirizzo);
    return credenziali;
  }

  Future<T> _conRitentativi<T>(
    UriTelefonoCoach uri,
    Future<T> Function(ClienteApi api) chiamata,
    FaseCollegamento fase,
    void Function(FaseCollegamento)? avanzamento,
  ) async {
    final scadenza = _orologio.adesso().add(attesaMassima);
    var assenze = 0;
    avanzamento?.call(fase);
    while (true) {
      final http = _tor.creaHttpClient();
      try {
        return await chiamata(
          ClienteApi(indirizzo: uri.indirizzo, http: http),
        ).timeout(durateTentativi[min(assenze, durateTentativi.length - 1)]);
      } on Object catch (e) {
        final problema = problemaDa(e);
        switch (problema) {
          case ProblemaCoach.irraggiungibile || ProblemaCoach.chiaveRifiutata || ProblemaCoach.occupato:
            final pausa = _pause[min(assenze, _pause.length - 1)];
            if (_orologio.adesso().add(pausa).isAfter(scadenza)) {
              throw const ErroreCollegamento(ProblemaCollegamento.pcIrraggiungibile);
            }
            assenze++;
            avanzamento?.call(FaseCollegamento.attesaPc);
            await _orologio.attendi(pausa);
            avanzamento?.call(fase);
          case ProblemaCoach.torNonParte:
            throw const ErroreCollegamento(ProblemaCollegamento.torNonParte);
          case ProblemaCoach.versioneDiversa:
            throw const ErroreCollegamento(ProblemaCollegamento.aggiornaApp);
          case ProblemaCoach.rifiutata:
            final codice = e is ErroreApi ? e.codice : '';
            throw ErroreCollegamento(
              codice == CodiceErrore.invitoInUso
                  ? ProblemaCollegamento.qrInUso
                  : codice == CodiceErrore.nonTrovato
                  ? ProblemaCollegamento.aggiornaApp
                  : ProblemaCollegamento.qrNonValido,
            );
          case ProblemaCoach.revocato || ProblemaCoach.inatteso:
            throw const ErroreCollegamento(ProblemaCollegamento.inatteso);
        }
      } finally {
        http.close();
      }
    }
  }

  /// La fonte dei dati per un telefono collegato.
  FonteRemota fonte(Credenziali credenziali, {void Function(String)? registra}) => FonteRemota(
    indirizzo: credenziali.indirizzo,
    token: credenziali.token,
    tor: _tor,
    chiavePrivata: credenziali.chiaveInByte,
    registra: registra,
  );
}
