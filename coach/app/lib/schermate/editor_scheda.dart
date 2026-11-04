import 'dart:convert';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:protocollo/protocollo.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../servizi.dart';
import 'libreria.dart';
import 'questionari.dart';

/// Editor di una scheda (§8.1, §9.3). Si lavora sulla bozza; «Pubblica» la
/// rende una nuova revisione, che l'atleta riceve alla sync successiva.
///
/// La bozza resta una mappa JSON: i campi che l'editor non conosce non si
/// perdono.
class EditorScheda extends StatefulWidget {
  const EditorScheda({
    super.key,
    required this.schedaId,
    required this.atleta,
    required this.nucleo,
    required this.aggiornamenti,
  });

  final String schedaId;
  final Atleta atleta;
  final NucleoCoach nucleo;
  final Aggiornamenti aggiornamenti;

  @override
  State<EditorScheda> createState() => _EditorSchedaState();
}

class _EditorSchedaState extends State<EditorScheda> {
  late Map<String, Object?> _bozza;
  var _modificata = false;

  /// Chiavi stabili per sedute, esercizi e righe, così spostarli non
  /// mescola i campi di testo.
  final _chiavi = Expando<Key>();

  @override
  void initState() {
    super.initState();
    final scheda = widget.nucleo.schede.cerca(widget.schedaId)!;
    _bozza = _copia(scheda.bozza);
    _bozza['sedute'] = _lista(_bozza, 'sedute');
    // Le schede non hanno più date: quelle vecchie le perdono alla prima
    // pubblicazione.
    _bozza
      ..remove('valida_dal')
      ..remove('valida_al');
  }

  Map<String, Object?> _copia(Map<String, Object?> m) =>
      jsonDecode(jsonEncode(m)) as Map<String, Object?>;

  /// Lista modificabile in [m][chiave], creata se manca.
  List<Object?> _lista(Map<String, Object?> m, String chiave) {
    final valore = m[chiave];
    final lista = valore is List<Object?> ? valore : <Object?>[];
    m[chiave] = lista;
    return lista;
  }

  List<Map<String, Object?>> _mappe(Map<String, Object?> m, String chiave) =>
      _lista(m, chiave).whereType<Map<String, Object?>>().toList();

  Key _chiave(Object oggetto) => _chiavi[oggetto] ??= UniqueKey();

  void _cambia(VoidCallback modifica) => setState(() {
    modifica();
    _modificata = true;
  });

  bool _salva() {
    try {
      widget.nucleo.schede.salvaBozza(widget.schedaId, _bozza);
      _modificata = false;
      widget.aggiornamenti.segnala();
      return true;
    } on OperazioneNonValida catch (e) {
      avviso(context, e.messaggio);
      return false;
    }
  }

  Future<void> _pubblica() async {
    final t = Testi.of(context);
    if (!_salva()) return;
    try {
      final attuale = widget.nucleo.schede
          .elenco(widget.atleta.id)
          .where((s) => s.stato == StatoScheda.pubblicata && s.id != widget.schedaId)
          .firstOrNull;
      final revisione = widget.nucleo.schede.pubblica(widget.schedaId);
      widget.aggiornamenti.segnala();
      setState(() {});
      avviso(
        context,
        attuale == null
            ? t.pubblicataRevisione(revisione)
            : t.pubblicataEArchiviata(revisione, attuale.titolo),
      );
    } on SchedaNonValida catch (e) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.schedaIncompleta),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: [for (final errore in e.errori) Text('• ${erroreLeggibile(t, errore)}')],
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t.chiudi))],
        ),
      );
    }
  }

  Future<void> _esci() async {
    final t = Testi.of(context);
    final scarta = await conferma(
      context,
      titolo: t.modificheNonSalvateTitolo,
      testo: t.modificheNonSalvateTesto,
      azione: t.scarta,
      pericolosa: true,
    );
    if (scarta && mounted) Navigator.pop(context);
  }

  /// Revisioni pubblicate e quando l'atleta le ha ricevute (§9.3). Una
  /// revisione sostituita prima della sync non arriva mai al telefono.
  Future<void> _mostraRevisioni(Scheda scheda) {
    final t = Testi.of(context);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.revisioniPubblicate),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final (i, r) in scheda.revisioni.indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.revisione(r.numero)),
                  subtitle: Text(
                    [
                      t.pubblicataIl(_quando(r.pubblicataIl)),
                      if (r.ricevutaIl != null)
                        t.ricevutaIl(dataOra(r.ricevutaIl!))
                      else if (i == 0)
                        t.inAttesaDiConsegna
                      else
                        t.sostituitaPrimaDiArrivare,
                    ].join(' · '),
                  ),
                ),
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t.chiudi))],
      ),
    );
  }

  String _quando(String dataOraProtocollo) {
    final istante = analizzaDataOra(dataOraProtocollo);
    return istante == null ? dataOraProtocollo : dataOra(istante);
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final scheda = widget.nucleo.schede.cerca(widget.schedaId);
    final sedute = _mappe(_bozza, 'sedute');
    return PopScope(
      canPop: !_modificata,
      onPopInvokedWithResult: (uscito, _) {
        if (!uscito) _esci();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.schedaDi(widget.atleta.nome)),
          actions: [
            IconButton(
              tooltip: t.risposteAtleta,
              isSelected: _risposteAperte,
              icon: const Icon(Icons.assignment_outlined),
              selectedIcon: const Icon(Icons.assignment),
              onPressed: () => setState(() => _risposteAperte = !_risposteAperte),
            ),
            if (scheda != null && scheda.revisione > 0)
              TextButton.icon(
                onPressed: () => _mostraRevisioni(scheda),
                icon: const Icon(Icons.history),
                label: Text(t.revisione(scheda.revisione)),
              ),
            TextButton(
              onPressed: _modificata ? () => setState(_salva) : null,
              child: Text(t.salvaBozza),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _pubblica,
              icon: const Icon(Icons.send),
              label: Text(t.pubblica),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _contenuto(t, sedute)),
            if (_risposteAperte) ...[
              const VerticalDivider(width: 1),
              SizedBox(width: 400, child: _PannelloRisposte(atleta: widget.atleta, nucleo: widget.nucleo)),
            ],
          ],
        ),
      ),
    );
  }

  /// Le ultime risposte dell'atleta ai questionari, accanto all'editor:
  /// aperte se ce ne sono.
  late var _risposteAperte = widget.nucleo.questionari.risposte(widget.atleta.id).isNotEmpty;

  Widget _contenuto(Testi t, List<Map<String, Object?>> sedute) {
    return ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
          children: [
            TextFormField(
              initialValue: _bozza['titolo'] as String? ?? '',
              decoration: InputDecoration(labelText: t.titoloScheda),
              style: Theme.of(context).textTheme.titleLarge,
              onChanged: (v) => _cambia(() => _bozza['titolo'] = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _bozza['note'] as String? ?? '',
              decoration: InputDecoration(labelText: t.noteScheda),
              minLines: 1,
              maxLines: 4,
              onChanged: (v) => _cambia(() => _bozza['note'] = v),
            ),
            for (final (i, seduta) in sedute.indexed)
              _seduta(t, seduta, i, sedute.length),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _cambia(
                  () => _lista(_bozza, 'sedute').add({
                    'id': nuovoUuid(),
                    'nome': t.sedutaPredefinita(sedute.length + 1),
                    'esercizi': <Object?>[],
                  }),
                ),
                icon: const Icon(Icons.add),
                label: Text(t.aggiungiSeduta),
              ),
            ),
          ],
        );
  }

  Widget _seduta(Testi t, Map<String, Object?> seduta, int indice, int totale) {
    final esercizi = _mappe(seduta, 'esercizi');
    return Card(
      key: _chiave(seduta),
      margin: const EdgeInsets.only(top: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: seduta['nome'] as String? ?? '',
                    decoration: InputDecoration(labelText: t.nomeSeduta),
                    style: Theme.of(context).textTheme.titleMedium,
                    onChanged: (v) => _cambia(() => seduta['nome'] = v),
                  ),
                ),
                _Spostamenti(
                  su: indice > 0 ? () => _sposta(_lista(_bozza, 'sedute'), seduta, -1) : null,
                  giu: indice < totale - 1 ? () => _sposta(_lista(_bozza, 'sedute'), seduta, 1) : null,
                  togli: () => _cambia(() => _lista(_bozza, 'sedute').remove(seduta)),
                  etichettaTogli: t.togliSeduta,
                ),
              ],
            ),
            TextFormField(
              initialValue: seduta['note'] as String? ?? '',
              decoration: InputDecoration(labelText: t.noteSeduta),
              onChanged: (v) => _cambia(() => seduta['note'] = v),
            ),
            for (final (j, esercizio) in esercizi.indexed)
              _esercizio(t, seduta, esercizio, j, esercizi.length),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _cambia(
                  () => _lista(seduta, 'esercizi').add({
                    'id': nuovoUuid(),
                    'nome': '',
                    'prescrizione': <Object?>[<String, Object?>{}],
                  }),
                ),
                icon: const Icon(Icons.add),
                label: Text(t.aggiungiEsercizio),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Un esercizio su una riga: nome, serie, ripetizioni, recupero e RIR, con
  /// le note a scomparsa. La riga modifica la prima prescrizione; le altre,
  /// di schede scritte prima, restano com'erano finché il coach non le
  /// toglie.
  Widget _esercizio(
    Testi t,
    Map<String, Object?> seduta,
    Map<String, Object?> esercizio,
    int indice,
    int totale,
  ) {
    final prescrizione = _lista(esercizio, 'prescrizione');
    if (prescrizione.firstOrNull is! Map<String, Object?>) {
      prescrizione.insert(0, <String, Object?>{});
    }
    final riga = prescrizione.first! as Map<String, Object?>;
    final altre = _mappe(esercizio, 'prescrizione').skip(1).toList();
    final esercizi = _lista(seduta, 'esercizi');
    final note = esercizio['note'] as String? ?? '';
    final noteAperte = _noteAperte[esercizio] ?? note.isNotEmpty;
    return Padding(
      key: _chiave(esercizio),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _NomeEsercizio(
                  iniziale: esercizio['nome'] as String? ?? '',
                  etichetta: t.nomeEsercizio,
                  libreria: widget.nucleo.libreria,
                  cambia: (v) => _cambia(() => esercizio['nome'] = v),
                  scegli: (scelto) => _cambia(() {
                    esercizio['nome'] = scelto.nome;
                    if (note.isEmpty && scelto.note.isNotEmpty) {
                      esercizio['note'] = scelto.note;
                      _noteAperte[esercizio] = true;
                      _versioneNote[esercizio] = (_versioneNote[esercizio] ?? 0) + 1;
                    }
                  }),
                ),
              ),
              _bottoneLibreria(t, esercizio),
              _campoRiga(riga, 'serie', t.serie, 72, intero: true),
              _campoRiga(riga, 'ripetizioni', t.ripetizioni, 110, suggerimento: '6-8'),
              _CampoRecupero(
                etichetta: t.recupero,
                errore: t.recuperoNonValido,
                secondi: riga['recupero_s'],
                cambia: (secondi) => _cambia(() {
                  if (secondi == null) {
                    riga.remove('recupero_s');
                  } else {
                    riga['recupero_s'] = secondi;
                  }
                }),
              ),
              _campoRiga(riga, 'rir', t.rir, 72, suggerimento: '2'),
              IconButton(
                tooltip: t.noteEsercizio,
                isSelected: noteAperte,
                icon: Icon(note.isEmpty ? Icons.notes : Icons.sticky_note_2_outlined),
                onPressed: () => setState(() => _noteAperte[esercizio] = !noteAperte),
              ),
              _Spostamenti(
                su: indice > 0 ? () => _sposta(esercizi, esercizio, -1) : null,
                giu: indice < totale - 1 ? () => _sposta(esercizi, esercizio, 1) : null,
                togli: () => _cambia(() => esercizi.remove(esercizio)),
                etichettaTogli: t.togliEsercizio,
              ),
            ],
          ),
          if (noteAperte)
            TextFormField(
              key: ValueKey(_versioneNote[esercizio] ?? 0),
              initialValue: note,
              decoration: InputDecoration(labelText: t.noteEsercizio, isDense: true),
              minLines: 1,
              maxLines: 4,
              onChanged: (v) => _cambia(() => esercizio['note'] = v),
            ),
          if (altre.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.altreRighe(altre.map(_riassunto).join(' · ')),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => _cambia(() => prescrizione.removeRange(1, prescrizione.length)),
                  child: Text(t.togliAltreRighe),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Note mostrate o nascoste per ogni esercizio; senza scelta del coach si
  /// vedono solo quelle già scritte.
  final _noteAperte = Expando<bool>();

  /// Cambia quando le note arrivano dalla libreria, per ricreare il campo.
  final _versioneNote = Expando<int>();

  /// Salva l'esercizio nella libreria, o lo apre se c'è già. L'icona dice se
  /// le schede riceveranno un video per questo esercizio.
  Widget _bottoneLibreria(Testi t, Map<String, Object?> esercizio) {
    final nome = (esercizio['nome'] as String? ?? '').trim();
    if (nome.isEmpty) return const SizedBox(width: 48);
    final presente = widget.nucleo.libreria.perNome(nome);
    final video = presente?.video;
    return IconButton(
      tooltip: presente == null
          ? t.salvaNellaLibreria
          : video == null
          ? t.nellaLibreriaSenzaVideo
          : t.videoDallaLibreria(video),
      color: video == null ? null : Theme.of(context).colorScheme.primary,
      icon: Icon(
        presente == null
            ? Icons.library_add_outlined
            : video == null
            ? Icons.video_call_outlined
            : Icons.smart_display,
      ),
      onPressed: () async {
        final salvato = await modificaEsercizioLibreria(
          context,
          widget.nucleo,
          esercizio: presente,
          nome: nome,
        );
        if (!salvato || !mounted) return;
        widget.aggiornamenti.segnala();
        setState(() {});
        await proponiAggiornamentoVideo(context, widget.nucleo, widget.aggiornamenti);
      },
    );
  }

  String _riassunto(Map<String, Object?> riga) => [
    '${riga['serie'] ?? '?'} × ${riga['ripetizioni'] ?? '?'}',
    if (riga['carico'] is String) riga['carico'] as String,
    if (riga['recupero_s'] is int) recuperoLeggibile(riga['recupero_s'] as int),
    if (riga['rir'] is String) 'RIR ${riga['rir']}',
  ].join(', ');

  Widget _campoRiga(
    Map<String, Object?> riga,
    String chiave,
    String etichetta,
    double larghezza, {
    bool intero = false,
    String? suggerimento,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: larghezza,
        child: TextFormField(
          initialValue: riga[chiave]?.toString() ?? '',
          decoration: InputDecoration(
            labelText: etichetta,
            hintText: suggerimento,
            isDense: true,
          ),
          keyboardType: intero ? TextInputType.number : TextInputType.text,
          inputFormatters: intero ? [FilteringTextInputFormatter.digitsOnly] : null,
          onChanged: (v) => _cambia(() {
            final pulito = v.trim();
            if (pulito.isEmpty) {
              riga.remove(chiave);
            } else {
              riga[chiave] = intero ? int.parse(pulito) : pulito;
            }
          }),
        ),
      ),
    );
  }

  void _sposta(List<Object?> lista, Object elemento, int verso) => _cambia(() {
    final i = lista.indexOf(elemento);
    lista
      ..removeAt(i)
      ..insert(i + verso, elemento);
  });
}

/// Le risposte dell'atleta ai questionari, dalla più recente: la prima
/// aperta, le altre da aprire.
class _PannelloRisposte extends StatelessWidget {
  const _PannelloRisposte({required this.atleta, required this.nucleo});

  final Atleta atleta;
  final NucleoCoach nucleo;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final risposte = nucleo.questionari.risposte(atleta.id);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.risposteAtleta, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (risposte.isEmpty) Text(t.nessunaRisposta),
        for (final (i, q) in risposte.indexed)
          ExpansionTile(
            initiallyExpanded: i == 0,
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 16),
            title: Text(q.titolo),
            subtitle: Text(soloData(q.rispostoIl!)),
            children: [RisposteQuestionario(questionario: q, nucleo: nucleo)],
          ),
      ],
    );
  }
}

/// Nome dell'esercizio, con i suggerimenti dalla libreria mentre si scrive.
class _NomeEsercizio extends StatelessWidget {
  const _NomeEsercizio({
    required this.iniziale,
    required this.etichetta,
    required this.libreria,
    required this.cambia,
    required this.scegli,
  });

  final String iniziale;
  final String etichetta;
  final GestioneLibreria libreria;
  final ValueChanged<String> cambia;
  final ValueChanged<EsercizioLibreria> scegli;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<EsercizioLibreria>(
      initialValue: TextEditingValue(text: iniziale),
      displayStringForOption: (esercizio) => esercizio.nome,
      optionsBuilder: (valore) {
        final cercato = chiaveEsercizio(valore.text);
        if (cercato.isEmpty) return const [];
        return libreria
            .elenco()
            .where((e) {
              final chiave = chiaveEsercizio(e.nome);
              return chiave.contains(cercato) && chiave != cercato;
            })
            .take(8);
      },
      onSelected: scegli,
      fieldViewBuilder: (context, controllo, fuoco, invia) => TextFormField(
        controller: controllo,
        focusNode: fuoco,
        decoration: InputDecoration(labelText: etichetta, isDense: true),
        onChanged: cambia,
        onFieldSubmitted: (_) => invia(),
      ),
    );
  }
}

/// Campo del recupero: accetta «90» o «1:30» e passa i secondi a [cambia],
/// null se il campo è vuoto o non si capisce.
class _CampoRecupero extends StatefulWidget {
  const _CampoRecupero({
    required this.etichetta,
    required this.errore,
    required this.secondi,
    required this.cambia,
  });

  final String etichetta;
  final String errore;
  final Object? secondi;
  final ValueChanged<int?> cambia;

  @override
  State<_CampoRecupero> createState() => _CampoRecuperoState();
}

class _CampoRecuperoState extends State<_CampoRecupero> {
  var _nonValido = false;

  @override
  Widget build(BuildContext context) {
    final secondi = widget.secondi;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 100,
        child: TextFormField(
          initialValue: secondi is int ? formattaRecupero(secondi) : '',
          decoration: InputDecoration(
            labelText: widget.etichetta,
            hintText: '1:30',
            isDense: true,
            errorText: _nonValido ? widget.errore : null,
            errorMaxLines: 2,
          ),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9:]'))],
          onChanged: (v) {
            final valore = analizzaRecupero(v);
            setState(() => _nonValido = v.trim().isNotEmpty && valore == null);
            widget.cambia(valore);
          },
        ),
      ),
    );
  }
}

class _Spostamenti extends StatelessWidget {
  const _Spostamenti({
    required this.su,
    required this.giu,
    required this.togli,
    required this.etichettaTogli,
  });

  final VoidCallback? su;
  final VoidCallback? giu;
  final VoidCallback togli;
  final String etichettaTogli;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: t.spostaSu, icon: const Icon(Icons.arrow_upward), onPressed: su),
        IconButton(tooltip: t.spostaGiu, icon: const Icon(Icons.arrow_downward), onPressed: giu),
        IconButton(tooltip: etichettaTogli, icon: const Icon(Icons.delete_outline), onPressed: togli),
      ],
    );
  }
}

/// Errore di validazione (`sedute[0].esercizi[1].nome: obbligatorio`) in una
/// forma da mostrare al coach (`Seduta 1, esercizio 2, nome: obbligatorio`).
String erroreLeggibile(Testi t, String errore) {
  final separatore = errore.indexOf(': ');
  if (separatore < 0) return errore;
  final percorso = errore.substring(0, separatore);
  final messaggio = errore.substring(separatore + 2);
  if (percorso == 'sedute' && messaggio.startsWith('servono almeno')) {
    return t.erroreServeUnaSeduta;
  }
  final parti = [
    for (final parte in percorso.split('.'))
      switch (RegExp(r'^(\w+)\[(\d+)\]$').firstMatch(parte)) {
        final m? when m[1] == 'sedute' => t.erroreSeduta(int.parse(m[2]!) + 1),
        final m? when m[1] == 'esercizi' => t.erroreEsercizio(int.parse(m[2]!) + 1),
        final m? when m[1] == 'prescrizione' => t.erroreRiga(int.parse(m[2]!) + 1),
        _ => switch (parte) {
          'titolo' => t.titoloScheda,
          'nome' => t.campoNome,
          'note' => t.campoNote,
          'serie' => t.serie,
          'ripetizioni' => t.ripetizioni,
          'carico' => t.carico,
          'recupero_s' => t.recupero,
          'rir' => t.rir,
          _ => parte,
        },
      },
  ];
  return '${parti.join(', ')}: $messaggio';
}
