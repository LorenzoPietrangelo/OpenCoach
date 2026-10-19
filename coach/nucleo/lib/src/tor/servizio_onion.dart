import 'dart:async';

import '../identita.dart';
import 'controllo_tor.dart';

enum FaseTor {
  /// Tor si sta collegando alla rete; vedi [StatoTor.avanzamento].
  avvio,

  /// Nessun telefono e nessun invito: il servizio non è pubblicato.
  nessunaChiave,

  /// Servizio creato, descrittore non ancora caricato.
  pubblicazione,

  /// Almeno un descrittore caricato: gli atleti possono collegarsi.
  raggiungibile,

  /// Vedi [StatoTor.motivo].
  nonRaggiungibile,
}

/// Stato mostrato nell'icona del programma (§9.1).
class StatoTor {
  const StatoTor(
    this.fase, {
    this.avanzamento = 0,
    this.motivo,
    this.versioneObsoleta = false,
  });

  final FaseTor fase;

  /// Percentuale di avvio di Tor.
  final int avanzamento;
  final String? motivo;

  /// Tor segnala che la sua versione è obsoleta: va aggiornato il programma.
  final bool versioneObsoleta;

  @override
  bool operator ==(Object other) =>
      other is StatoTor &&
      other.fase == fase &&
      other.avanzamento == avanzamento &&
      other.motivo == motivo &&
      other.versioneObsoleta == versioneObsoleta;

  @override
  int get hashCode => Object.hash(fase, avanzamento, motivo, versioneObsoleta);

  @override
  String toString() =>
      'StatoTor($fase, $avanzamento%${motivo == null ? '' : ', $motivo'}'
      '${versioneObsoleta ? ', versione obsoleta' : ''})';
}

/// Onion service del coach (§6.1, §9.2).
///
/// Il servizio autorizza solo le chiavi di inviti aperti e dispositivi
/// attivi. Quando cambiano lo ricrea: aspetta [raggruppamento] per unire i
/// cambiamenti vicini, poi la fine delle richieste in corso (al massimo
/// [attesaMassima]), perché ricrearlo chiude i circuiti aperti.
class ServizioOnion {
  ServizioOnion({
    required this.controllo,
    required this.identita,
    required this.portaLocale,
    required this.chiaviAutorizzate,
    required this.attendiRichiesteInCorso,
    this.raggruppamento = const Duration(seconds: 5),
    this.attesaMassima = const Duration(seconds: 30),
    this.attesaDopoErrore = const Duration(seconds: 30),
    void Function(String)? registra,
  }) : _registra = registra ?? ((_) {});

  final ControlloTor controllo;
  final Identita identita;
  final int portaLocale;
  final List<String> Function() chiaviAutorizzate;
  final Future<void> Function(Duration limite) attendiRichiesteInCorso;
  final Duration raggruppamento;
  final Duration attesaMassima;
  final Duration attesaDopoErrore;
  final void Function(String) _registra;

  final _cambiamenti = StreamController<StatoTor>.broadcast();
  StreamSubscription<EventoTor>? _iscrizione;
  Timer? _timer;
  Future<void> _coda = Future.value();
  var _stato = const StatoTor(FaseTor.avvio);
  var _avanzamento = 0;
  var _versioneObsoleta = false;
  var _reteAssente = false;
  String? _errore;
  List<String>? _chiaviPubblicate;
  var _pubblicato = false;
  var _caricato = false;

  StatoTor get stato => _stato;

  Stream<StatoTor> get cambiamenti => _cambiamenti.stream;

  Future<void> avvia() async {
    _iscrizione = controllo.eventi.listen(_evento);
    await controllo.iscrivi([
      'HS_DESC',
      'STATUS_CLIENT',
      'STATUS_GENERAL',
      'NETWORK_LIVENESS',
    ]);
    _avanzamento = _leggiAvanzamento(
      await controllo.leggiInfo('status/bootstrap-phase'),
    );
    final versione = await controllo.leggiInfo('status/version/current');
    _versioneObsoleta = const {'obsolete', 'unrecommended'}.contains(versione);
    _aggiornaStato();
    await _inSerie(_pubblica);
  }

  /// Le chiavi autorizzate sono cambiate: il servizio verrà ricreato.
  void chiaviCambiate() {
    _timer?.cancel();
    _timer = Timer(raggruppamento, () {
      _inSerie(() async {
        await attendiRichiesteInCorso(attesaMassima);
        await _pubblica();
      });
    });
  }

  Future<void> _inSerie(Future<void> Function() operazione) {
    final prossima = _coda.then((_) => operazione()).catchError((Object e) {
      _registra('Pubblicazione del servizio non riuscita: $e');
      _errore = 'Tor non ha accettato il servizio';
      _aggiornaStato();
      _timer?.cancel();
      _timer = Timer(attesaDopoErrore, chiaviCambiate);
    });
    _coda = prossima;
    return prossima;
  }

  Future<void> _pubblica() async {
    final chiavi = chiaviAutorizzate();
    final invariato =
        _chiaviPubblicate != null &&
        _chiaviPubblicate!.length == chiavi.length &&
        _chiaviPubblicate!.every(chiavi.contains);
    if (invariato && (_pubblicato || chiavi.isEmpty)) return;

    if (_pubblicato) {
      await controllo.rimuoviOnion(identita.indirizzo);
      _pubblicato = false;
      _caricato = false;
    }
    _chiaviPubblicate = null;
    if (chiavi.isNotEmpty) {
      final indirizzo = await controllo.aggiungiOnion(
        chiave: identita.chiaveTor,
        portaVirtuale: 80,
        destinazione: '127.0.0.1:$portaLocale',
        chiaviClient: chiavi,
      );
      if (indirizzo != identita.indirizzo) {
        await controllo.rimuoviOnion(indirizzo);
        throw StateError('Tor ha creato un indirizzo diverso: $indirizzo');
      }
      _pubblicato = true;
    }
    _chiaviPubblicate = chiavi;
    _errore = null;
    _aggiornaStato();
  }

  void _evento(EventoTor evento) {
    final parole = evento.parole;
    final secondo = parole.length > 1 ? parole[1] : '';
    final terzo = parole.length > 2 ? parole[2] : '';
    switch (parole.first) {
      case 'HS_DESC' when secondo == 'UPLOADED' && terzo == identita.indirizzo:
        _caricato = true;
      case 'STATUS_CLIENT' when terzo == 'BOOTSTRAP':
        _avanzamento = _leggiAvanzamento(evento.righe.first);
      case 'STATUS_GENERAL' when terzo == 'DANGEROUS_VERSION':
        _versioneObsoleta = true;
      case 'NETWORK_LIVENESS':
        _reteAssente = secondo == 'DOWN';
    }
    _aggiornaStato();
  }

  int _leggiAvanzamento(String testo) =>
      int.tryParse(RegExp(r'PROGRESS=(\d+)').firstMatch(testo)?[1] ?? '') ??
      _avanzamento;

  void _aggiornaStato() {
    final FaseTor fase;
    if (_avanzamento < 100) {
      fase = FaseTor.avvio;
    } else if (_reteAssente || _errore != null) {
      fase = FaseTor.nonRaggiungibile;
    } else if (_chiaviPubblicate == null) {
      fase = FaseTor.pubblicazione;
    } else if (!_pubblicato) {
      fase = FaseTor.nessunaChiave;
    } else if (!_caricato) {
      fase = FaseTor.pubblicazione;
    } else {
      fase = FaseTor.raggiungibile;
    }
    final nuovo = StatoTor(
      fase,
      avanzamento: _avanzamento,
      motivo: fase == FaseTor.nonRaggiungibile
          ? (_reteAssente ? 'Nessuna connessione a Internet' : _errore)
          : null,
      versioneObsoleta: _versioneObsoleta,
    );
    if (nuovo == _stato) return;
    _stato = nuovo;
    if (!_cambiamenti.isClosed) _cambiamenti.add(nuovo);
  }

  Future<void> chiudi() async {
    _timer?.cancel();
    await _iscrizione?.cancel();
    await _cambiamenti.close();
  }
}
