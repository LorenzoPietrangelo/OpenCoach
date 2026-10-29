import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:protocollo/protocollo.dart';

import '../l10n/testi.dart';
import '../piattaforma/foto.dart';
import 'avvisi.dart';
import 'formati.dart';

/// Un questionario del coach (§8.6): l'atleta risponde anche in più volte,
/// perché ogni risposta si salva subito, allega le foto richieste e invia.
/// Inviato, si legge soltanto.
class SchermataQuestionario extends StatefulWidget {
  const SchermataQuestionario({
    super.key,
    required this.nucleo,
    required this.coachId,
    required this.questionarioId,
    this.scegliFoto = scegliFotoDalTelefono,
  });

  final NucleoAtleta nucleo;
  final int coachId;
  final String questionarioId;
  final ScegliFoto scegliFoto;

  @override
  State<SchermataQuestionario> createState() => _SchermataQuestionarioState();
}

class _SchermataQuestionarioState extends State<SchermataQuestionario> {
  late QuestionarioRicevuto _q;
  late Map<int, Uint8List> _foto;

  /// Dopo un tentativo di invio, le domande obbligatorie senza risposta si
  /// segnano in rosso.
  var _mostraMancanti = false;
  var _preparandoFoto = false;

  QuestionariRicevuti get _questionari => widget.nucleo.questionari;

  bool get _modificabile => _q.stato == StatoQuestionario.daCompilare;

  @override
  void initState() {
    super.initState();
    _leggi();
    if (_modificabile) _precompilaPeso();
  }

  void _leggi() {
    _q = _questionari.cerca(widget.coachId, widget.questionarioId)!;
    _foto = _questionari.foto(widget.coachId, widget.questionarioId);
  }

  /// Le domande sul peso corporeo partono dall'ultimo peso registrato.
  void _precompilaPeso() {
    final pesi = widget.nucleo.pesi.elenco();
    if (pesi.isEmpty) return;
    for (final d in _q.domande) {
      if (d['peso_corporeo'] == true && !_q.bozza.containsKey(d['id'])) {
        _questionari.rispondi(widget.coachId, _q.id, d['id']! as String, pesi.last.kg);
      }
    }
    _leggi();
  }

  void _rispondi(String domandaId, Object? valore) {
    _questionari.rispondi(widget.coachId, _q.id, domandaId, valore);
    setState(_leggi);
  }

  Future<void> _aggiungiFoto(int posizione) async {
    final testi = Testi.of(context);
    final origine = await showModalBottomSheet<OrigineFoto>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(testi.scattaFoto),
              onTap: () => Navigator.pop(context, OrigineFoto.fotocamera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(testi.scegliDallaGalleria),
              onTap: () => Navigator.pop(context, OrigineFoto.galleria),
            ),
          ],
        ),
      ),
    );
    if (origine == null || !mounted) return;
    setState(() => _preparandoFoto = true);
    try {
      final jpeg = await widget.scegliFoto(origine);
      if (jpeg != null) {
        _questionari.allegaFoto(widget.coachId, _q.id, posizione, jpeg);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).avvisa(
          e.code == 'camera_access_denied' ? testi.fotocameraNegata : testi.fotoNonRiuscita,
        );
      }
    } on Exception {
      if (mounted) ScaffoldMessenger.of(context).avvisa(testi.fotoNonRiuscita);
    } finally {
      if (mounted) {
        setState(() {
          _preparandoFoto = false;
          _leggi();
        });
      }
    }
  }

  Future<void> _invia() async {
    final testi = Testi.of(context);
    final mancano = _domandeMancanti().isNotEmpty || _foto.length < _q.fotoRichieste;
    if (mancano) {
      setState(() => _mostraMancanti = true);
      ScaffoldMessenger.of(context).avvisa(testi.questionarioIncompleto);
      return;
    }
    final sicuro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(testi.inviaQuestionarioTitolo),
        content: Text(testi.inviaQuestionarioTesto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(testi.annulla)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(testi.invia)),
        ],
      ),
    );
    if (sicuro != true || !mounted) return;
    try {
      _questionari.invia(widget.coachId, _q.id);
    } on RispostaNonValida {
      setState(() => _mostraMancanti = true);
      ScaffoldMessenger.of(context).avvisa(testi.questionarioIncompleto);
      return;
    }
    final messaggi = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messaggi.avvisa(testi.questionarioInviato);
  }

  Set<Object?> _domandeMancanti() => {
    for (final d in _q.domande)
      if (d['obbligatoria'] == true && !_q.bozza.containsKey(d['id'])) d['id'],
  };

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final mancanti = _mostraMancanti ? _domandeMancanti() : const <Object?>{};
    final valori = _modificabile
        ? _q.bozza
        : {
            for (final r in (_q.risposta?['risposte'] as List<Object?>?) ?? const [])
              if (r is Map<String, Object?>) r['domanda_id']! as String: r['valore'],
          };
    return Scaffold(
      appBar: AppBar(title: Text(_q.titolo)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_q.rifiuto != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(testi.questionarioRifiutato)),
            ),
          if (!_modificabile)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _q.stato == StatoQuestionario.inviato ? testi.questionarioArrivato : testi.questionarioInCoda,
                style: tema.bodySmall,
              ),
            ),
          if (_q.descrizione.isNotEmpty) Text(_q.descrizione),
          for (final d in _q.domande)
            _Domanda(
              domanda: d,
              valore: valori[d['id']],
              modificabile: _modificabile,
              mancante: mancanti.contains(d['id']),
              cambia: (valore) => _rispondi(d['id']! as String, valore),
            ),
          if (_q.fotoRichieste > 0) ...[
            const SizedBox(height: 24),
            Text(testi.fotoRichieste(_q.fotoRichieste), style: tema.titleMedium),
            if (_q.istruzioniFoto.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_q.istruzioniFoto),
            ],
            const SizedBox(height: 4),
            Text(testi.fotoPrivacy, style: tema.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _q.fotoRichieste; i++)
                  _Foto(
                    numero: i + 1,
                    dati: _foto[i],
                    mancante: _mostraMancanti && _foto[i] == null,
                    aggiungi: _modificabile && !_preparandoFoto ? () => _aggiungiFoto(i) : null,
                    togli: _modificabile
                        ? () {
                            _questionari.togliFoto(widget.coachId, _q.id, i);
                            setState(_leggi);
                          }
                        : null,
                  ),
              ],
            ),
            if (_preparandoFoto) const LinearProgressIndicator(),
          ],
          if (_modificabile) ...[
            const SizedBox(height: 32),
            Text(testi.bozzaSalvata, style: tema.bodySmall),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _preparandoFoto ? null : _invia,
              icon: const Icon(Icons.send),
              label: Text(testi.inviaAlCoach),
            ),
          ],
        ],
      ),
    );
  }
}

/// Una domanda, con il campo adatto al suo tipo.
class _Domanda extends StatelessWidget {
  const _Domanda({
    required this.domanda,
    required this.valore,
    required this.modificabile,
    required this.mancante,
    required this.cambia,
  });

  final Map<String, Object?> domanda;
  final Object? valore;
  final bool modificabile;
  final bool mancante;
  final ValueChanged<Object?> cambia;

  List<String> get _opzioni => [
    for (final o in (domanda['opzioni'] as List<Object?>?) ?? const [])
      if (o is String) o,
  ];

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context);
    final obbligatoria = domanda['obbligatoria'] == true;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${domanda['testo']}${obbligatoria ? ' *' : ''}',
            style: tema.textTheme.titleSmall?.copyWith(color: mancante ? tema.colorScheme.error : null),
          ),
          if (mancante) Text(testi.rispostaObbligatoria, style: TextStyle(color: tema.colorScheme.error)),
          const SizedBox(height: 8),
          _campo(testi),
        ],
      ),
    );
  }

  Widget _campo(Testi testi) {
    switch (domanda['tipo']) {
      case TipoDomanda.testoBreve || TipoDomanda.testoLungo:
        final lungo = domanda['tipo'] == TipoDomanda.testoLungo;
        return _CampoTesto(
          iniziale: valore is String ? valore! as String : '',
          righe: lungo ? 4 : 1,
          massimo: lungo ? LimitiQuestionario.testoLungo : LimitiQuestionario.testoBreve,
          abilitato: modificabile,
          cambia: (testo) => cambia(testo.trim().isEmpty ? null : testo),
        );
      case TipoDomanda.numero:
        return _CampoNumero(
          iniziale: valore is num ? numero(valore! as num) : '',
          unita: domanda['unita'] as String?,
          abilitato: modificabile,
          cambia: cambia,
        );
      case TipoDomanda.scala:
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var n = 1; n <= 10; n++)
              ChoiceChip(
                label: Text('$n'),
                selected: valore == n,
                onSelected: modificabile ? (si) => cambia(si ? n : null) : null,
              ),
          ],
        );
      case TipoDomanda.sceltaSingola:
        return _SceltaSingola(
          opzioni: _opzioni,
          altroAmmesso: domanda['altro'] == true,
          valore: valore,
          abilitato: modificabile,
          cambia: cambia,
        );
      default:
        return _SceltaMultipla(
          opzioni: _opzioni,
          altroAmmesso: domanda['altro'] == true,
          valore: valore,
          abilitato: modificabile,
          cambia: cambia,
        );
    }
  }
}

class _CampoTesto extends StatefulWidget {
  const _CampoTesto({
    required this.iniziale,
    required this.righe,
    required this.massimo,
    required this.abilitato,
    required this.cambia,
  });

  final String iniziale;
  final int righe;
  final int massimo;
  final bool abilitato;
  final ValueChanged<String> cambia;

  @override
  State<_CampoTesto> createState() => _CampoTestoState();
}

class _CampoTestoState extends State<_CampoTesto> {
  late final _testo = TextEditingController(text: widget.iniziale);

  @override
  void dispose() {
    _testo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _testo,
    enabled: widget.abilitato,
    minLines: widget.righe,
    maxLines: widget.righe == 1 ? 1 : null,
    maxLength: widget.massimo,
    decoration: const InputDecoration(border: OutlineInputBorder(), counterText: ''),
    onChanged: widget.cambia,
  );
}

class _CampoNumero extends StatefulWidget {
  const _CampoNumero({
    required this.iniziale,
    required this.unita,
    required this.abilitato,
    required this.cambia,
  });

  final String iniziale;
  final String? unita;
  final bool abilitato;
  final ValueChanged<Object?> cambia;

  @override
  State<_CampoNumero> createState() => _CampoNumeroState();
}

class _CampoNumeroState extends State<_CampoNumero> {
  late final _testo = TextEditingController(text: widget.iniziale);
  var _valido = true;

  @override
  void dispose() {
    _testo.dispose();
    super.dispose();
  }

  void _cambiato(String testo) {
    num? valore;
    var valido = true;
    try {
      valore = leggiDecimale(testo, massimo: LimitiQuestionario.numeroMassimo);
    } on FormatException {
      valido = false;
    }
    setState(() => _valido = valido);
    if (valido) widget.cambia(valore);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: TextField(
      controller: _testo,
      enabled: widget.abilitato,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        suffixText: widget.unita,
        errorText: _valido ? null : Testi.of(context).numeroNonValido,
      ),
      onChanged: _cambiato,
    ),
  );
}

class _SceltaSingola extends StatelessWidget {
  const _SceltaSingola({
    required this.opzioni,
    required this.altroAmmesso,
    required this.valore,
    required this.abilitato,
    required this.cambia,
  });

  final List<String> opzioni;
  final bool altroAmmesso;
  final Object? valore;
  final bool abilitato;
  final ValueChanged<Object?> cambia;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final scelta = switch (valore) {
      {'scelta': final String s} => s,
      _ => null,
    };
    final altro = switch (valore) {
      {'altro': final String a} => a,
      _ => null,
    };
    return RadioGroup<String>(
      groupValue: altro != null ? '\u0000altro' : scelta,
      onChanged: (v) {
        if (!abilitato || v == null) return;
        cambia(v == '\u0000altro' ? {'altro': altro ?? ''} : {'scelta': v});
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final o in opzioni)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(o),
              value: o,
              enabled: abilitato,
            ),
          if (altroAmmesso) ...[
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(testi.altro),
              value: '\u0000altro',
              enabled: abilitato,
            ),
            if (altro != null)
              _CampoTesto(
                iniziale: altro,
                righe: 1,
                massimo: LimitiQuestionario.opzione,
                abilitato: abilitato,
                // Un «Altro» ancora vuoto non è una risposta: si tiene la
                // scelta, ma non vale finché non si scrive.
                cambia: (testo) => cambia({'altro': testo}),
              ),
          ],
        ],
      ),
    );
  }
}

class _SceltaMultipla extends StatelessWidget {
  const _SceltaMultipla({
    required this.opzioni,
    required this.altroAmmesso,
    required this.valore,
    required this.abilitato,
    required this.cambia,
  });

  final List<String> opzioni;
  final bool altroAmmesso;
  final Object? valore;
  final bool abilitato;
  final ValueChanged<Object?> cambia;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final scelte = <String>[
      if (valore case {'scelte': final List<Object?> lista})
        for (final s in lista)
          if (s is String) s,
    ];
    final altro = switch (valore) {
      {'altro': final String a} => a,
      _ => null,
    };
    void aggiorna(List<String> scelte, String? altro) => cambia(
      scelte.isEmpty && altro == null ? null : {'scelte': scelte, 'altro': ?altro},
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final o in opzioni)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(o),
            value: scelte.contains(o),
            onChanged: abilitato
                ? (si) => aggiorna(
                    [for (final x in opzioni) if (x == o ? si == true : scelte.contains(x)) x],
                    altro,
                  )
                : null,
          ),
        if (altroAmmesso) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(testi.altro),
            value: altro != null,
            onChanged: abilitato ? (si) => aggiorna(scelte, si == true ? '' : null) : null,
          ),
          if (altro != null)
            _CampoTesto(
              iniziale: altro,
              righe: 1,
              massimo: LimitiQuestionario.opzione,
              abilitato: abilitato,
              cambia: (testo) => aggiorna(scelte, testo),
            ),
        ],
      ],
    );
  }
}

/// Lo spazio per una foto: vuoto con il pulsante, o la miniatura.
class _Foto extends StatelessWidget {
  const _Foto({
    required this.numero,
    required this.dati,
    required this.mancante,
    required this.aggiungi,
    required this.togli,
  });

  final int numero;
  final Uint8List? dati;
  final bool mancante;
  final VoidCallback? aggiungi;
  final VoidCallback? togli;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    final dati = this.dati;
    return SizedBox(
      width: 104,
      height: 136,
      child: dati == null
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: BorderSide(color: mancante ? schema.error : schema.outline),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: aggiungi,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_a_photo_outlined),
                  const SizedBox(height: 4),
                  Text(Testi.of(context).fotoNumero(numero)),
                ],
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(dati, fit: BoxFit.cover),
                ),
                if (togli != null)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton.filledTonal(
                      tooltip: Testi.of(context).togliFoto,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: togli,
                    ),
                  ),
              ],
            ),
    );
  }
}
