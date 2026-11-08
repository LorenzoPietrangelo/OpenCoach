import 'dart:async';
import 'dart:typed_data';

import 'package:protocollo/protocollo.dart';
import 'package:trasporto_tor/trasporto_tor.dart';

import 'fonte_dati.dart';
import 'modelli.dart';

/// Traduce un errore di una chiamata al PC in un [ProblemaCoach]. Rilancia
/// quelli di programmazione.
ProblemaCoach problemaDa(Object errore) {
  if (errore is TorNonParte) return ProblemaCoach.torNonParte;
  final guasto = classifica(errore);
  return switch (guasto?.tipo) {
    null => throw errore,
    TipoGuasto.irraggiungibile => ProblemaCoach.irraggiungibile,
    TipoGuasto.chiaveRifiutata => ProblemaCoach.chiaveRifiutata,
    TipoGuasto.protocollo => ProblemaCoach.inatteso,
    TipoGuasto.risposta => switch (guasto!.errore!.stato) {
      401 => ProblemaCoach.revocato,
      426 => ProblemaCoach.versioneDiversa,
      429 || 503 => ProblemaCoach.occupato,
      400 || 404 || 409 || 410 || 413 => ProblemaCoach.rifiutata,
      _ => ProblemaCoach.inatteso,
    },
  };
}

/// Il telefono come telecomando del PC: ogni dato arriva dal programma del
/// coach attraverso Tor (§16.1).
class FonteRemota implements FonteDatiCoach {
  FonteRemota({
    required this.indirizzo,
    required this.token,
    required TrasportoTor tor,
    required Uint8List chiavePrivata,
    void Function(String)? registra,
  }) : _tor = tor,
       _chiave = chiavePrivata,
       _registra = registra ?? ((_) {});

  final String indirizzo;
  final String token;
  final TrasportoTor _tor;
  final Uint8List _chiave;
  final void Function(String) _registra;

  Future<void>? _avvio;
  var _chiaveImpostata = false;

  /// Avvia Tor una volta sola: ripetere l'avvio con una richiesta in corso
  /// farebbe scartare a Tor le chiavi per un attimo.
  Future<void> _preparaTor() => _avvio ??= () async {
    try {
      await _tor.avvia();
      if (!_chiaveImpostata) {
        await _tor.impostaChiave(indirizzo, _chiave);
        _chiaveImpostata = true;
      }
    } catch (_) {
      _avvio = null;
      rethrow;
    }
  }();

  Future<T> _chiama<T>(Future<T> Function(ClienteApi api) chiamata) async {
    try {
      await _preparaTor();
      final http = _tor.creaHttpClient();
      try {
        return await chiamata(ClienteApi(indirizzo: indirizzo, http: http, token: token));
      } finally {
        http.close();
      }
    } on Object catch (e) {
      final problema = problemaDa(e);
      _registra('Richiesta al PC non riuscita: ${problema.name}');
      // Tor può essersi fermato: alla prossima richiesta si riavvia.
      if (problema == ProblemaCoach.irraggiungibile || problema == ProblemaCoach.torNonParte) _avvio = null;
      throw ErroreCoach(problema);
    }
  }

  @override
  Future<ElencoAtleti> atleti() => _chiama((api) async {
    final risposta = await api.atletiCoach();
    return ElencoAtleti([for (final a in risposta.atleti) RiepilogoAtleta.daJson(a)], risposta.impronta);
  });

  @override
  Future<DettaglioAtleta> atleta(String id) =>
      _chiama((api) async => DettaglioAtleta.daJson(await api.atletaCoach(id)));

  @override
  Future<Pagina<MessaggioChat>> messaggi(String atletaId, {String? prima}) => _chiama((api) async {
    final pagina = await api.messaggiCoach(atletaId, prima: prima);
    return Pagina([for (final m in pagina.elementi) MessaggioChat.daJson(m)], altri: pagina.altri);
  });

  @override
  Future<void> inviaMessaggio(String atletaId, String id, String testo) =>
      _chiama((api) => api.inviaMessaggioCoach(atletaId, id, testo));

  @override
  Future<void> segnaLetti(String atletaId) => _chiama((api) => api.segnaLettiCoach(atletaId));

  @override
  Future<Pagina<AllenamentoAtleta>> allenamenti(String atletaId, {String? prima}) => _chiama((api) async {
    final pagina = await api.allenamentiCoach(atletaId, prima: prima);
    return Pagina([for (final a in pagina.elementi) AllenamentoAtleta.daJson(a)], altri: pagina.altri);
  });

  @override
  Future<List<PesoGiorno>> pesi(String atletaId) => _chiama((api) async {
    return [
      for (final p in await api.pesiCoach(atletaId))
        if (analizzaData(p['giorno']) case final giorno?)
          if (p['kg'] case final num kg) PesoGiorno(giorno, kg.toDouble()),
    ];
  });

  @override
  Future<CiboAtleta> cibo(String atletaId, {String? prima}) =>
      _chiama((api) async => CiboAtleta.daJson(await api.ciboCoach(atletaId, prima: prima)));

  @override
  Future<List<QuestionarioAtleta>> questionari(String atletaId) => _chiama((api) async {
    final pagina = await api.questionariCoach(atletaId);
    return [for (final q in pagina.elementi) QuestionarioAtleta.daJson(q)];
  });

  @override
  Future<void> segnaQuestionarioLetto(String id) => _chiama((api) => api.segnaQuestionarioLettoCoach(id));

  @override
  Future<Uint8List> foto(String id) => _chiama((api) => api.fotoCoach(id));

  @override
  Future<bool> attendi(String impronta) => _chiama((api) => api.attendiCoach(impronta));

  @override
  Future<void> confermaCollegamento() => _chiama((api) => api.confermaTelefonoCoach());

  @override
  Future<void> scollega() => _chiama((api) => api.scollegaTelefonoCoach());

  @override
  Future<void> fermaRete() async {
    _avvio = null;
    await _tor.ferma();
  }
}
