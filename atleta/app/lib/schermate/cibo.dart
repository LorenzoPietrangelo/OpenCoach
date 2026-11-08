import 'dart:async';

import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:protocollo/protocollo.dart';

import '../l10n/testi.dart';
import 'avvisi.dart';
import 'formati.dart';
import 'scansione_codice.dart';

/// Il diario del cibo (§8.8, §10.2): i pasti di un giorno con le loro voci,
/// i totali e l'obiettivo del coach. Nelle sezioni dell'app la barra in alto
/// è una sola.
class SezioneCibo extends StatefulWidget {
  const SezioneCibo({super.key, required this.nucleo, required this.coachId});

  final NucleoAtleta nucleo;
  final int coachId;

  @override
  State<SezioneCibo> createState() => _SezioneCiboState();
}

class _SezioneCiboState extends State<SezioneCibo> {
  late DateTime _giorno = _oggi;
  late final StreamSubscription<int> _cambiamenti;

  RegistroCibo get _cibo => widget.nucleo.cibo;

  DateTime get _oggi {
    final ora = widget.nucleo.contesto.orologio.adesso().toLocal();
    return DateTime(ora.year, ora.month, ora.day);
  }

  @override
  void initState() {
    super.initState();
    // Una sync può portare l'obiettivo del coach o dire che non riceve il cibo.
    _cambiamenti = widget.nucleo.cambiamenti.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_cambiamenti.cancel());
    super.dispose();
  }

  void _sposta(int giorni) => setState(() {
    final nuovo = DateTime(_giorno.year, _giorno.month, _giorno.day + giorni);
    if (!nuovo.isAfter(_oggi)) _giorno = nuovo;
  });

  Future<void> _scegliGiorno() async {
    final scelto = await showDatePicker(
      context: context,
      initialDate: _giorno,
      firstDate: DateTime(2000),
      lastDate: _oggi,
    );
    if (scelto != null) setState(() => _giorno = scelto);
  }

  Future<void> _aggiungi(String pasto) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SchermataAggiungiCibo(nucleo: widget.nucleo, giorno: _giorno, pasto: pasto),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _modifica(VoceCibo voce) async {
    final testi = Testi.of(context);
    final esito = await showDialog<_EsitoVoce>(
      context: context,
      builder: (_) => _DialogoVoce(voce: voce),
    );
    if (esito == null || !mounted) return;
    if (esito.elimina) {
      _cibo.elimina(_giorno, voce.id);
      setState(() {});
      final giorno = _giorno;
      final alimento = AlimentoCibo(
        nome: voce.nome,
        marca: voce.marca,
        codice: voce.codice,
        fonte: voce.fonte,
        per100g: voce.per100g,
      );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(testi.voceEliminata(voce.nome)),
            action: SnackBarAction(
              label: testi.annulla,
              onPressed: () {
                _cibo.aggiungi(giorno, voce.pasto, alimento, voce.grammi);
                if (mounted) setState(() {});
              },
            ),
          ),
        );
    } else if (esito.grammi case final grammi?) {
      _cibo.cambiaGrammi(_giorno, voce.id, grammi);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final giornata = _cibo.giornata(_giorno);
    final totali = giornata.totali;
    final obiettivo = _cibo.obiettivo(widget.coachId);
    final coach = widget.nucleo.collegamenti.attivi();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: testi.giornoPrecedente,
              onPressed: () => _sposta(-1),
            ),
            Expanded(
              child: TextButton(
                onPressed: _scegliGiorno,
                child: Text(
                  _giorno == _oggi ? testi.oggi : giornoEMese(context, _giorno),
                  style: tema.titleMedium,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: testi.giornoSuccessivo,
              onPressed: _giorno == _oggi ? null : () => _sposta(1),
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('${intero(totali.kcal)} kcal', style: tema.headlineSmall),
                    if (obiettivo != null) ...[
                      const SizedBox(width: 8),
                      Text('/ ${intero(obiettivo.kcal)}', style: tema.titleMedium),
                    ],
                  ],
                ),
                if (obiettivo != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (totali.kcal / obiettivo.kcal).clamp(0, 1).toDouble(),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  [
                    _macro('P', totali.proteine, obiettivo?.proteineG),
                    _macro('C', totali.carboidrati, obiettivo?.carboidratiG),
                    _macro('G', totali.grassi, obiettivo?.grassiG),
                  ].join(' · '),
                ),
                if (obiettivo == null) ...[
                  const SizedBox(height: 4),
                  Text(testi.senzaObiettivo, style: tema.bodySmall),
                ],
              ],
            ),
          ),
        ),
        for (final pasto in pastiCibo)
          _Pasto(
            nome: nomePasto(testi, pasto),
            voci: giornata.delPasto(pasto),
            aggiungi: () => _aggiungi(pasto),
            modifica: _modifica,
          ),
        if (coach.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(testi.condividiCiboCon, style: tema.titleMedium),
          const SizedBox(height: 4),
          Text(testi.condividiCiboSpiegazione, style: tema.bodySmall),
          for (final c in coach)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(c.nomeCoach),
              subtitle: Text(
                c.ciboSupportato == false
                    ? testi.ciboNonSupportato
                    : c.condivideCibo
                    ? testi.ciboCondiviso
                    : testi.ciboNonCondiviso,
              ),
              value: c.condivideCibo,
              onChanged: (valore) => setState(() => _cibo.condividi(c.id, condividi: valore)),
            ),
        ],
        const SizedBox(height: 16),
        Text(testi.fonteDatiOff, style: tema.bodySmall),
      ],
    );
  }

  static String _macro(String lettera, double? valore, int? obiettivo) =>
      '$lettera ${intero(valore ?? 0)}${obiettivo == null ? '' : '/$obiettivo'} g';
}

/// `1.850`: arrotondato, con il punto delle migliaia.
String intero(num valore) {
  final cifre = valore.round().abs().toString();
  final gruppi = <String>[];
  for (var fine = cifre.length; fine > 0; fine -= 3) {
    gruppi.insert(0, cifre.substring(fine - 3 < 0 ? 0 : fine - 3, fine));
  }
  return '${valore < -0.5 ? '−' : ''}${gruppi.join('.')}';
}

String nomePasto(Testi testi, String pasto) => switch (pasto) {
  'colazione' => testi.pastoColazione,
  'pranzo' => testi.pastoPranzo,
  'cena' => testi.pastoCena,
  _ => testi.pastoSpuntini,
};

class _Pasto extends StatelessWidget {
  const _Pasto({
    required this.nome,
    required this.voci,
    required this.aggiungi,
    required this.modifica,
  });

  final String nome;
  final List<VoceCibo> voci;
  final VoidCallback aggiungi;
  final void Function(VoceCibo) modifica;

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final kcal = voci.fold(0.0, (s, v) => s + v.valori.kcal);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(nome, style: tema.titleMedium)),
                if (voci.isNotEmpty) Text('${intero(kcal)} kcal', style: tema.bodyMedium),
                const SizedBox(width: 8),
              ],
            ),
            for (final v in voci)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(v.nome),
                subtitle: Text('${numero(v.grammi)} g'),
                trailing: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('${intero(v.valori.kcal)} kcal'),
                ),
                onTap: () => modifica(v),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: aggiungi,
                icon: const Icon(Icons.add),
                label: Text(testi.aggiungiCibo),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EsitoVoce {
  const _EsitoVoce({this.grammi, this.elimina = false});

  final double? grammi;
  final bool elimina;
}

/// Cambia i grammi di una voce o la toglie.
class _DialogoVoce extends StatefulWidget {
  const _DialogoVoce({required this.voce});

  final VoceCibo voce;

  @override
  State<_DialogoVoce> createState() => _DialogoVoceState();
}

class _DialogoVoceState extends State<_DialogoVoce> {
  late final _grammi = TextEditingController(text: numero(widget.voce.grammi));
  String? _errore;

  @override
  void dispose() {
    _grammi.dispose();
    super.dispose();
  }

  void _salva() {
    final grammi = leggiGrammi(_grammi.text);
    if (grammi == null) {
      setState(() => _errore = Testi.of(context).grammiNonValidi);
      return;
    }
    Navigator.of(context).pop(_EsitoVoce(grammi: grammi));
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    return AlertDialog(
      title: Text(widget.voce.nome),
      content: TextField(
        controller: _grammi,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: testi.grammi,
          suffixText: 'g',
          errorText: _errore,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _salva(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(const _EsitoVoce(elimina: true)),
          child: Text(testi.eliminaVoce),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(testi.annulla)),
        FilledButton(onPressed: _salva, child: Text(testi.salva)),
      ],
    );
  }
}

/// Grammi scritti dall'atleta, da 0,1 a 5000; null se non vanno bene.
double? leggiGrammi(String testo) {
  try {
    final valore = leggiDecimale(testo, massimo: LimitiCibo.grammiMassimi, passo: 0.1);
    if (valore == null || valore < LimitiCibo.grammiMinimi) return null;
    return valore.toDouble();
  } on FormatException {
    return null;
  }
}

/// Aggiunge un alimento a un pasto (§10.3): dai cibi già usati, che stanno sul
/// telefono e si trovano subito mentre si scrive; dal catalogo sul PC del
/// coach, per nome premendo invio o con il codice a barre; oppure
/// scrivendolo.
class SchermataAggiungiCibo extends StatefulWidget {
  const SchermataAggiungiCibo({
    super.key,
    required this.nucleo,
    required this.giorno,
    required this.pasto,
  });

  final NucleoAtleta nucleo;
  final DateTime giorno;
  final String pasto;

  @override
  State<SchermataAggiungiCibo> createState() => _SchermataAggiungiCiboState();
}

class _SchermataAggiungiCiboState extends State<SchermataAggiungiCibo> {
  final _testo = TextEditingController();
  var _cercando = false;

  /// I prodotti del catalogo del coach per l'ultima ricerca.
  List<ProdottoCibo>? _risultati;
  String? _avviso;

  RegistroCibo get _cibo => widget.nucleo.cibo;

  @override
  void dispose() {
    _testo.dispose();
    super.dispose();
  }

  String _messaggio(Testi testi, GuastoCibo guasto) => switch (guasto) {
    GuastoCibo.nonDisponibile => testi.ciboNonDisponibile,
    GuastoCibo.coachIrraggiungibile => testi.ciboCoachIrraggiungibile,
    GuastoCibo.senzaCatalogo => testi.ciboSenzaCatalogo,
    GuastoCibo.troppeRichieste => testi.ciboTroppeRichieste,
    GuastoCibo.altro => testi.ciboRicercaNonRiuscita,
  };

  /// Mentre si scrive bastano i cibi già usati: il catalogo si interroga
  /// solo con invio, per non consumare le richieste verso il coach.
  void _scritto(String _) => setState(() {
    _risultati = null;
    _avviso = null;
  });

  Future<void> _cerca() async {
    final testi = Testi.of(context);
    FocusScope.of(context).unfocus();
    if (_testo.text.trim().isEmpty) return;
    setState(() {
      _cercando = true;
      _avviso = null;
    });
    try {
      final risultati = await widget.nucleo.ricercaCibo.cerca(_testo.text);
      if (!mounted) return;
      setState(() {
        _risultati = risultati;
        if (risultati.isEmpty) _avviso = testi.nessunRisultato;
      });
    } on ErroreCibo catch (e) {
      if (mounted) setState(() => _avviso = _messaggio(testi, e.guasto));
    } finally {
      if (mounted) setState(() => _cercando = false);
    }
  }

  Future<void> _scansiona() async {
    final testi = Testi.of(context);
    final codice = await ScansioneCodice.apri(context);
    if (codice == null || !mounted) return;
    // Prima tra i cibi già usati, poi nel catalogo del coach.
    if (_cibo.salvatoPerCodice(codice) case final salvato?) {
      await _porzione(salvato);
      return;
    }
    setState(() {
      _cercando = true;
      _avviso = null;
    });
    ProdottoCibo? prodotto;
    String? problema;
    try {
      prodotto = await widget.nucleo.ricercaCibo.perCodice(codice);
    } on ErroreCibo catch (e) {
      problema = _messaggio(testi, e.guasto);
    }
    if (!mounted) return;
    setState(() => _cercando = false);
    if (prodotto != null) {
      await _porzione(AlimentoCibo.daProdotto(prodotto));
    } else {
      ScaffoldMessenger.of(context).avvisa(problema ?? testi.codiceSconosciuto);
      await _scrivi(codice: codice);
    }
  }

  Future<void> _scrivi({String? nome, String? marca, String? codice}) async {
    final alimento = await Navigator.of(context).push(
      MaterialPageRoute<AlimentoCibo>(
        builder: (_) => SchermataAlimento(nome: nome, marca: marca, codice: codice),
      ),
    );
    if (alimento != null && mounted) await _porzione(alimento);
  }

  Future<void> _porzione(AlimentoCibo alimento) async {
    final scelta = await Navigator.of(context).push(
      MaterialPageRoute<(double, String)>(
        builder: (_) => SchermataPorzione(alimento: alimento, pasto: widget.pasto),
      ),
    );
    if (scelta == null || !mounted) return;
    widget.nucleo.cibo.aggiungi(widget.giorno, scelta.$2, alimento, scelta.$1);
    Navigator.of(context).pop();
  }

  Widget _riga(Testi testi, AlimentoCibo a) => ListTile(
    title: Text(a.nome),
    subtitle: Text(
      [
        ?a.marca,
        if (a.porzioneG case final g?) '${numero(g)} g',
        testi.kcalPer100(intero(a.per100g.kcal)),
      ].join(' · '),
    ),
    trailing: const Icon(Icons.add),
    onTap: () => _porzione(a),
  );

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final testo = _testo.text.trim();
    final salvati = testo.isEmpty ? _cibo.recenti() : _cibo.cercaSalvati(testo);
    final codiciSalvati = {for (final a in salvati) ?a.codice};
    final dalCoach = [
      for (final p in _risultati ?? const <ProdottoCibo>[])
        if (!codiciSalvati.contains(p.codice)) AlimentoCibo.daProdotto(p),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(testi.aggiungiA(nomePasto(testi, widget.pasto).toLowerCase()))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _testo,
                    textInputAction: TextInputAction.search,
                    onChanged: _scritto,
                    onSubmitted: (_) => _cerca(),
                    decoration: InputDecoration(
                      hintText: testi.cercaCibo,
                      helperText: testi.cercaCiboAiuto,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: testi.scansionaCodice,
                  onPressed: _cercando ? null : _scansiona,
                ),
              ],
            ),
          ),
          if (_cercando) const LinearProgressIndicator(),
          if (_avviso case final avviso?)
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text(avviso)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _Titolo(testo.isEmpty ? testi.recenti : testi.giaUsati),
                if (salvati.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(testo.isEmpty ? testi.nessunRecente : testi.nessunoGiaUsato, style: tema.bodySmall),
                  ),
                for (final a in salvati) _riga(testi, a),
                if (dalCoach.isNotEmpty) ...[
                  _Titolo(testi.dalCatalogoCoach),
                  for (final a in dalCoach) _riga(testi, a),
                ],
                const SizedBox(height: 8),
                _Titolo(testi.nonLoTrovi),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _scrivi(nome: testo.isEmpty ? null : testo),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(testi.scriviAlimento),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Titolo extends StatelessWidget {
  const _Titolo(this.testo);

  final String testo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(testo, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// Quanto ne ha mangiato l'atleta e in quale pasto, con i valori ricalcolati.
/// Si chiude con i grammi e il pasto.
class SchermataPorzione extends StatefulWidget {
  const SchermataPorzione({super.key, required this.alimento, required this.pasto});

  final AlimentoCibo alimento;
  final String pasto;

  @override
  State<SchermataPorzione> createState() => _SchermataPorzioneState();
}

class _SchermataPorzioneState extends State<SchermataPorzione> {
  late final _grammi = TextEditingController(text: numero(widget.alimento.porzioneG ?? 100));
  late String _pasto = widget.pasto;
  String? _errore;

  @override
  void dispose() {
    _grammi.dispose();
    super.dispose();
  }

  void _imposta(double grammi) => setState(() {
    _grammi.text = numero(grammi);
    _errore = null;
  });

  void _aggiungi() {
    final grammi = leggiGrammi(_grammi.text);
    if (grammi == null) {
      setState(() => _errore = Testi.of(context).grammiNonValidi);
      return;
    }
    Navigator.of(context).pop((grammi, _pasto));
  }

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final a = widget.alimento;
    final grammi = leggiGrammi(_grammi.text);
    final valori = grammi == null ? null : a.per100g.per(grammi / 100);
    String macro(double? v) => v == null ? '–' : numero((v * 10).round() / 10);
    return Scaffold(
      appBar: AppBar(title: Text(a.nome)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (a.marca case final marca?) Text(marca, style: tema.bodyMedium),
          Text(
            '${testi.valoriPer100}: ${intero(a.per100g.kcal)} kcal · '
            'P ${macro(a.per100g.proteine)} · C ${macro(a.per100g.carboidrati)} · '
            'G ${macro(a.per100g.grassi)}',
            style: tema.bodySmall,
          ),
          const SizedBox(height: 16),
          Text(testi.quantoNeHai, style: tema.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _grammi,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
            onChanged: (_) => setState(() => _errore = null),
            decoration: InputDecoration(
              labelText: testi.grammi,
              suffixText: 'g',
              errorText: _errore,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if (a.porzioneG case final porzione? when porzione != 100)
                ActionChip(
                  label: Text('${testi.porzioneConfezione} ${numero(porzione)} g'),
                  onPressed: () => _imposta(porzione),
                ),
              ActionChip(label: const Text('100 g'), onPressed: () => _imposta(100)),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Valore('kcal', valori == null ? '–' : intero(valori.kcal)),
                  _Valore('P g', macro(valori?.proteine)),
                  _Valore('C g', macro(valori?.carboidrati)),
                  _Valore('G g', macro(valori?.grassi)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(testi.pasto, style: tema.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final p in pastiCibo)
                ChoiceChip(
                  label: Text(nomePasto(testi, p)),
                  selected: _pasto == p,
                  onSelected: (_) => setState(() => _pasto = p),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _aggiungi,
            child: Text(testi.aggiungiA(nomePasto(testi, _pasto).toLowerCase())),
          ),
        ],
      ),
    );
  }
}

class _Valore extends StatelessWidget {
  const _Valore(this.etichetta, this.valore);

  final String etichetta;
  final String valore;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(valore, style: tema.titleLarge),
        Text(etichetta, style: tema.bodySmall),
      ],
    );
  }
}

/// L'atleta scrive un alimento: nome e valori per 100 g dall'etichetta. Si
/// chiude con l'alimento, che ha `fonte: atleta`.
class SchermataAlimento extends StatefulWidget {
  const SchermataAlimento({super.key, this.nome, this.marca, this.codice});

  final String? nome;
  final String? marca;
  final String? codice;

  @override
  State<SchermataAlimento> createState() => _SchermataAlimentoState();
}

class _SchermataAlimentoState extends State<SchermataAlimento> {
  late final _nome = TextEditingController(text: widget.nome ?? '');
  late final _marca = TextEditingController(text: widget.marca ?? '');
  final _kcal = TextEditingController();
  final _proteine = TextEditingController();
  final _carboidrati = TextEditingController();
  final _grassi = TextEditingController();
  var _errore = false;

  @override
  void dispose() {
    for (final c in [_nome, _marca, _kcal, _proteine, _carboidrati, _grassi]) {
      c.dispose();
    }
    super.dispose();
  }

  void _continua() {
    double? valore(TextEditingController c, num massimo) {
      try {
        return leggiDecimale(c.text, massimo: massimo)?.toDouble();
      } on FormatException {
        return double.nan;
      }
    }

    final kcal = valore(_kcal, LimitiCibo.kcalPer100gMassime);
    final macro = [for (final c in [_proteine, _carboidrati, _grassi]) valore(c, 100)];
    final nome = _nome.text.trim();
    if (nome.isEmpty || nome.length > LimitiCibo.nomeMassimo || kcal == null || kcal.isNaN || macro.any((m) => m?.isNaN ?? false)) {
      setState(() => _errore = true);
      return;
    }
    Navigator.of(context).pop(
      AlimentoCibo(
        nome: nome,
        marca: _marca.text.trim().isEmpty ? null : _marca.text.trim(),
        codice: widget.codice,
        fonte: FonteCibo.atleta,
        per100g: ValoriCibo(kcal: kcal, proteine: macro[0], carboidrati: macro[1], grassi: macro[2]),
      ),
    );
  }

  Widget _campo(TextEditingController c, String etichetta, {String? unita, bool numerico = true}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: numerico ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          textCapitalization: numerico ? TextCapitalization.none : TextCapitalization.sentences,
          onChanged: (_) => setState(() => _errore = false),
          decoration: InputDecoration(labelText: etichetta, suffixText: unita, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final testi = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(testi.scriviAlimento)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _campo(_nome, testi.nomeAlimento, numerico: false),
          _campo(_marca, testi.marcaFacoltativa, numerico: false),
          Text(testi.valoriPer100, style: tema.titleMedium),
          const SizedBox(height: 8),
          _campo(_kcal, testi.calorie, unita: 'kcal'),
          _campo(_proteine, '${testi.proteine} (${testi.facoltativo})', unita: 'g'),
          _campo(_carboidrati, '${testi.carboidrati} (${testi.facoltativo})', unita: 'g'),
          _campo(_grassi, '${testi.grassi} (${testi.facoltativo})', unita: 'g'),
          if (_errore)
            Text(testi.alimentoNonValido, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _continua, child: Text(testi.continua)),
        ],
      ),
    );
  }
}
