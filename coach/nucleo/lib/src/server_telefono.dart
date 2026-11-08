part of 'server_http.dart';

/// Gli endpoint riservati al telefono del coach (§16.3).
const _prefissoCoach = '/v1/coach/';

/// Ogni quanto un'attesa del telefono controlla se l'impronta è cambiata: i
/// cambiamenti arrivano anche dal PC, che non li annuncia tutti con un evento.
const _controlloImpronta = Duration(seconds: 1);

extension _ApiTelefonoCoach on ServerCoach {
  Future<void> _instradaTelefono(HttpRequest richiesta) async {
    final metodo = richiesta.method;
    final parti = richiesta.uri.path.substring(_prefissoCoach.length).split('/');
    final telefono = _nucleo.telefonoCoach;
    final vista = _nucleo.vistaTelefono;

    if (metodo == 'POST' && parti.length == 1 && parti.first == 'abbinamento') {
      final attesa = _limiteAbbinamenti.registra('abbinamento');
      if (attesa != null) {
        throw ErroreHttp(429, CodiceErrore.troppeRichieste, riprovaTra: attesa);
      }
      final corpo = await _leggiJson(richiesta);
      final risposta = telefono.abbina(_analizza(() => RichiestaAbbinamento.fromJson(corpo)));
      return _rispondi(richiesta, 200, risposta.toJson());
    }

    final autenticato = _autenticaTelefono(richiesta);
    final prima = richiesta.uri.queryParameters['prima'];
    switch ((metodo, parti)) {
      case ('POST', ['abbinamento', 'conferma']):
        await _leggiCorpo(richiesta);
        telefono.conferma(autenticato);
        await _rispondi(richiesta, 204, null);

      case ('DELETE', ['telefono']):
        await _leggiCorpo(richiesta);
        telefono.revoca();
        await _rispondi(richiesta, 204, null);

      case ('GET', ['atleti']):
        await _rispondi(richiesta, 200, vista.elenco());

      case ('GET', ['atleti', final id]):
        await _rispondi(richiesta, 200, vista.atleta(id));

      case ('GET', ['atleti', final id, 'messaggi']):
        await _rispondi(richiesta, 200, vista.messaggi(id, prima: prima));

      case ('POST', ['atleti', final id, 'messaggi']):
        final corpo = await _leggiJson(richiesta);
        final (idMessaggio, testo) = _analizza(() => _nuovoMessaggio(corpo));
        await _rispondi(richiesta, 200, vista.inviaMessaggio(id, idMessaggio, testo));

      case ('POST', ['atleti', final id, 'messaggi', 'letti']):
        await _leggiCorpo(richiesta);
        vista.segnaLetti(id);
        await _rispondi(richiesta, 204, null);

      case ('GET', ['atleti', final id, 'allenamenti']):
        await _rispondi(richiesta, 200, vista.allenamenti(id, prima: prima));

      case ('GET', ['atleti', final id, 'pesi']):
        await _rispondi(richiesta, 200, vista.pesi(id));

      case ('GET', ['atleti', final id, 'cibo']):
        await _rispondi(richiesta, 200, vista.cibo(id, prima: prima));

      case ('GET', ['atleti', final id, 'questionari']):
        await _rispondi(richiesta, 200, vista.questionari(id));

      case ('POST', ['questionari', final id, 'letto']):
        await _leggiCorpo(richiesta);
        vista.segnaQuestionarioLetto(id);
        await _rispondi(richiesta, 204, null);

      case ('GET', ['foto', final id]):
        final jpeg = _nucleo.questionari.foto(id);
        if (jpeg == null) throw const ErroreHttp(404, CodiceErrore.nonTrovato);
        await _rispondiJpeg(richiesta, jpeg);

      case ('POST', ['attendi']):
        final corpo = await _leggiJson(richiesta);
        final (impronta, attesaS) = _analizza(() => _richiestaAttesa(corpo));
        final novita = await _attendiImpronta(autenticato, impronta, attesaS);
        await _rispondi(richiesta, 200, {'novita': novita});

      default:
        throw const ErroreHttp(404, CodiceErrore.nonTrovato);
    }
  }

  TelefonoCoach _autenticaTelefono(HttpRequest richiesta) {
    final telefono = _nucleo.telefonoCoach.autentica(
      richiesta.headers.value(HttpHeaders.authorizationHeader),
    );
    if (telefono == null) {
      throw const ErroreHttp(401, CodiceErrore.tokenRevocato);
    }
    final attesa = _limiteTelefonoCoach.registra(telefono.id);
    if (attesa != null) {
      throw ErroreHttp(429, CodiceErrore.troppeRichieste, riprovaTra: attesa);
    }
    return telefono;
  }

  (String, String) _nuovoMessaggio(Object? json) {
    if (json case {'id': final String id, 'testo': final String testo} when uuidValido(id)) {
      return (id, testo);
    }
    throw const FormatException('Servono "id" e "testo"');
  }

  (String, int) _richiestaAttesa(Object? json) {
    if (json case {'impronta': final String impronta, 'attesa_s': final int attesaS}
        when impronta.length <= 1000 && attesaS >= 0) {
      return (impronta, attesaS);
    }
    throw const FormatException('Servono "impronta" e "attesa_s"');
  }

  /// Vero appena l'impronta è diversa da [impronta], falso dopo l'attesa. Una
  /// sola per telefono: quella nuova conclude la precedente, come `attendi`
  /// degli atleti.
  Future<bool> _attendiImpronta(TelefonoCoach telefono, String impronta, int attesaS) async {
    final vista = _nucleo.vistaTelefono;
    if (vista.impronta() != impronta) return true;
    final esito = Completer<bool>();
    void concludi(bool novita) {
      if (!esito.isCompleted) esito.complete(novita);
    }

    void senzaNovita() => concludi(false);
    final controllo = Timer.periodic(_controlloImpronta, (_) {
      if (vista.impronta() != impronta) concludi(true);
    });
    final scadenza = Timer(Duration(seconds: min(attesaS, Limiti.attesaNovitaS)), senzaNovita);
    final chiave = 'telefono_coach:${telefono.id}';
    _inSospeso[chiave]?.call();
    _inSospeso[chiave] = senzaNovita;
    try {
      return await esito.future;
    } finally {
      controllo.cancel();
      scadenza.cancel();
      if (identical(_inSospeso[chiave], senzaNovita)) _inSospeso.remove(chiave);
    }
  }

  Future<void> _rispondiJpeg(HttpRequest richiesta, Uint8List jpeg) async {
    final risposta = richiesta.response;
    try {
      risposta.statusCode = 200;
      risposta.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      risposta.headers.contentType = ContentType('image', 'jpeg');
      risposta.contentLength = jpeg.length;
      risposta.add(jpeg);
      await risposta.close();
    } catch (e) {
      _registra('Risposta non inviata: $e');
    }
  }
}
