import 'dart:convert';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:protocollo/protocollo.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../servizi.dart';

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
      final revisione = widget.nucleo.schede.pubblica(widget.schedaId);
      widget.aggiornamenti.segnala();
      setState(() {});
      avviso(context, t.pubblicataRevisione(revisione));
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

  Future<void> _scegliData(String chiave) async {
    final attuale = analizzaData(_bozza[chiave]);
    final scelta = await showDatePicker(
      context: context,
      initialDate: attuale ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (scelta != null) _cambia(() => _bozza[chiave] = formattaData(scelta));
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
        body: ListView(
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _CampoData(
                  etichetta: t.validaDal,
                  valore: _bozza['valida_dal'] as String?,
                  scegli: () => _scegliData('valida_dal'),
                  togli: () => _cambia(() => _bozza.remove('valida_dal')),
                ),
                _CampoData(
                  etichetta: t.validaAl,
                  valore: _bozza['valida_al'] as String?,
                  scegli: () => _scegliData('valida_al'),
                  togli: () => _cambia(() => _bozza.remove('valida_al')),
                ),
              ],
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
        ),
      ),
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

  Widget _esercizio(
    Testi t,
    Map<String, Object?> seduta,
    Map<String, Object?> esercizio,
    int indice,
    int totale,
  ) {
    final righe = _mappe(esercizio, 'prescrizione');
    final esercizi = _lista(seduta, 'esercizi');
    return Container(
      key: _chiave(esercizio),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: esercizio['nome'] as String? ?? '',
                  decoration: InputDecoration(labelText: t.nomeEsercizio),
                  onChanged: (v) => _cambia(() => esercizio['nome'] = v),
                ),
              ),
              _Spostamenti(
                su: indice > 0 ? () => _sposta(esercizi, esercizio, -1) : null,
                giu: indice < totale - 1 ? () => _sposta(esercizi, esercizio, 1) : null,
                togli: () => _cambia(() => esercizi.remove(esercizio)),
                etichettaTogli: t.togliEsercizio,
              ),
            ],
          ),
          TextFormField(
            initialValue: esercizio['note'] as String? ?? '',
            decoration: InputDecoration(labelText: t.noteEsercizio),
            onChanged: (v) => _cambia(() => esercizio['note'] = v),
          ),
          for (final riga in righe)
            Padding(
              key: _chiave(riga),
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  _campoRiga(riga, 'serie', t.serie, 90, intero: true),
                  _campoRiga(riga, 'ripetizioni', t.ripetizioni, 140),
                  _campoRiga(riga, 'carico', t.carico, 160),
                  _campoRiga(riga, 'recupero_s', t.recuperoSecondi, 130, intero: true),
                  IconButton(
                    tooltip: t.togliRiga,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => _cambia(() => _lista(esercizio, 'prescrizione').remove(riga)),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _cambia(
                () => _lista(esercizio, 'prescrizione').add(<String, Object?>{}),
              ),
              icon: const Icon(Icons.add),
              label: Text(t.aggiungiRiga),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoRiga(
    Map<String, Object?> riga,
    String chiave,
    String etichetta,
    double larghezza, {
    bool intero = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: larghezza,
        child: TextFormField(
          initialValue: riga[chiave]?.toString() ?? '',
          decoration: InputDecoration(labelText: etichetta, isDense: true),
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

class _CampoData extends StatelessWidget {
  const _CampoData({
    required this.etichetta,
    required this.valore,
    required this.scegli,
    required this.togli,
  });

  final String etichetta;
  final String? valore;
  final VoidCallback scegli;
  final VoidCallback togli;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final giorno = analizzaData(valore);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: scegli,
          icon: const Icon(Icons.event),
          label: Text('$etichetta: ${giorno == null ? t.nessunaData : soloData(giorno)}'),
        ),
        if (giorno != null)
          IconButton(tooltip: t.togliData, icon: const Icon(Icons.clear), onPressed: togli),
      ],
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
          'valida_dal' => t.validaDal,
          'valida_al' => t.validaAl,
          'serie' => t.serie,
          'ripetizioni' => t.ripetizioni,
          'carico' => t.carico,
          'recupero_s' => t.recuperoSecondi,
          _ => parte,
        },
      },
  ];
  return '${parti.join(', ')}: $messaggio';
}
