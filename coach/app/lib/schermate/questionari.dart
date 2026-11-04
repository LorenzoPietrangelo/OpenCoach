import 'dart:convert';

import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:protocollo/protocollo.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../servizi.dart';

/// I modelli di questionario (§8.6, §9.3), dalla chat con un atleta: anamnesi,
/// check mensili, tutto quello che il coach vuole chiedere. Qui si manda quello
/// scelto, si scrive uno nuovo e si modificano quelli che ci sono.
class SceltaQuestionario extends StatelessWidget {
  const SceltaQuestionario({
    super.key,
    required this.atleta,
    required this.coach,
    required this.aggiornamenti,
  });

  final Atleta atleta;
  final Coach coach;
  final Aggiornamenti aggiornamenti;

  NucleoCoach get _nucleo => coach.nucleo;

  Future<void> _apri(BuildContext context, [String? id]) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => EditorQuestionario(nucleo: _nucleo, modelloId: id)),
    );
    aggiornamenti.segnala();
  }

  Future<void> _manda(BuildContext context, ModelloQuestionario modello) async {
    final t = Testi.of(context);
    await esegui(context, () async {
      _nucleo.questionari.invia(modello.id, atleta.id);
      aggiornamenti.segnala();
      if (!context.mounted) return;
      avviso(context, t.questionarioMandato);
      Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.mandaQuestionarioA(atleta.nome)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: () => _apri(context),
              icon: const Icon(Icons.add),
              label: Text(t.nuovoQuestionario),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: aggiornamenti,
        builder: (context, _) {
          final modelli = _nucleo.questionari.modelli();
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(t.questionariSpiegazione),
              const SizedBox(height: 16),
              if (modelli.isEmpty) Text(t.nessunQuestionario),
              for (final m in modelli)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.assignment_outlined),
                    title: Text(m.titolo),
                    subtitle: Text(descriviModello(t, m.contenuto)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton(onPressed: () => _manda(context, m), child: Text(t.manda)),
                        PopupMenuButton<String>(
                          tooltip: t.altreAzioni,
                          onSelected: (azione) async {
                            if (azione == 'modifica') {
                              await _apri(context, m.id);
                              return;
                            }
                            if (azione == 'duplica') {
                              _nucleo.questionari.duplicaModello(m.id);
                            } else {
                              final sicuro = await conferma(
                                context,
                                titolo: t.eliminaQuestionarioTitolo(m.titolo),
                                testo: t.eliminaQuestionarioTesto,
                                azione: t.elimina,
                                pericolosa: true,
                              );
                              if (sicuro) _nucleo.questionari.eliminaModello(m.id);
                            }
                            aggiornamenti.segnala();
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(value: 'modifica', child: Text(t.modifica)),
                            PopupMenuItem(value: 'duplica', child: Text(t.duplica)),
                            PopupMenuItem(value: 'elimina', child: Text(t.elimina)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// «12 domande · 5 foto».
String descriviModello(Testi t, Map<String, Object?> contenuto) {
  final domande = (contenuto['domande'] as List<Object?>?)?.length ?? 0;
  final foto = switch (contenuto['foto']) {
    {'numero': final int n} => n,
    _ => 0,
  };
  return [t.numeroDomande(domande), if (foto > 0) t.numeroFoto(foto)].join(' · ');
}

String etichettaTipo(Testi t, Object? tipo) => switch (tipo) {
  TipoDomanda.testoBreve => t.tipoTestoBreve,
  TipoDomanda.testoLungo => t.tipoTestoLungo,
  TipoDomanda.numero => t.tipoNumero,
  TipoDomanda.sceltaSingola => t.tipoSceltaSingola,
  TipoDomanda.sceltaMultipla => t.tipoSceltaMultipla,
  _ => t.tipoScala,
};

/// Editor di un modello. Le domande restano mappe JSON, come nel protocollo.
class EditorQuestionario extends StatefulWidget {
  const EditorQuestionario({super.key, required this.nucleo, required this.modelloId});

  final NucleoCoach nucleo;

  /// Null per un questionario nuovo, che esiste solo dopo il primo
  /// salvataggio.
  final String? modelloId;

  @override
  State<EditorQuestionario> createState() => _EditorQuestionarioState();
}

class _EditorQuestionarioState extends State<EditorQuestionario> {
  late String? _id = widget.modelloId;
  late final Map<String, Object?> _q;
  var _modificato = false;
  final _chiavi = Expando<Key>();

  @override
  void initState() {
    super.initState();
    final esistente = _id == null ? null : widget.nucleo.questionari.modello(_id!);
    _q = esistente == null
        ? {
            'titolo': '',
            'domande': <Object?>[_nuovaDomanda(TipoDomanda.testoBreve)],
          }
        : jsonDecode(jsonEncode(esistente.contenuto)) as Map<String, Object?>;
  }

  Map<String, Object?> _nuovaDomanda(String tipo) => {
    'id': nuovoUuid(),
    'tipo': tipo,
    'testo': '',
    'obbligatoria': false,
  };

  List<Map<String, Object?>> get _domande => [
    for (final d in _q['domande']! as List<Object?>) d! as Map<String, Object?>,
  ];

  void _cambia(VoidCallback modifica) => setState(() {
    modifica();
    _modificato = true;
  });

  Future<void> _salva() async {
    final t = Testi.of(context);
    try {
      if (_id == null) {
        _id = widget.nucleo.questionari.creaModello(_q);
      } else {
        widget.nucleo.questionari.salvaModello(_id!, _q);
      }
      setState(() => _modificato = false);
      avviso(context, t.questionarioSalvato);
    } on QuestionarioNonValido catch (e) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.questionarioIncompleto),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: [for (final errore in e.errori) Text('• ${_erroreLeggibile(t, errore)}')],
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t.chiudi))],
        ),
      );
    }
  }

  String _erroreLeggibile(Testi t, String errore) => errore
      .replaceAllMapped(RegExp(r'domande\[(\d+)\]\.?'), (m) => '${t.domandaNumero(int.parse(m[1]!) + 1)} ')
      .replaceFirst('titolo:', '${t.titoloQuestionario}:');

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

  void _sposta(Map<String, Object?> domanda, int verso) => _cambia(() {
    final lista = _q['domande']! as List<Object?>;
    final i = lista.indexOf(domanda);
    lista
      ..removeAt(i)
      ..insert(i + verso, domanda);
  });

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final domande = _domande;
    final foto = _q['foto'] as Map<String, Object?>?;
    return PopScope(
      canPop: !_modificato,
      onPopInvokedWithResult: (uscito, _) {
        if (!uscito) _esci();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_id == null ? t.nuovoQuestionario : t.modificaQuestionario),
          actions: [
            FilledButton.icon(onPressed: _salva, icon: const Icon(Icons.save), label: Text(t.salva)),
            const SizedBox(width: 16),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
          children: [
            TextFormField(
              initialValue: _q['titolo'] as String? ?? '',
              decoration: InputDecoration(labelText: t.titoloQuestionario),
              style: Theme.of(context).textTheme.titleLarge,
              onChanged: (v) => _cambia(() => _q['titolo'] = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _q['descrizione'] as String? ?? '',
              decoration: InputDecoration(labelText: t.descrizioneQuestionario, helperText: t.descrizioneAiuto),
              minLines: 2,
              maxLines: 8,
              onChanged: (v) => _cambia(() => _q['descrizione'] = v),
            ),
            for (final (i, d) in domande.indexed) _domanda(t, d, i, domande.length),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _cambia(
                  () => (_q['domande']! as List<Object?>).add(_nuovaDomanda(TipoDomanda.testoBreve)),
                ),
                icon: const Icon(Icons.add),
                label: Text(t.aggiungiDomanda),
              ),
            ),
            const Divider(height: 48),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.chiediFoto),
              subtitle: Text(t.chiediFotoAiuto),
              value: foto != null,
              onChanged: (si) => _cambia(() {
                if (si) {
                  _q['foto'] = <String, Object?>{'numero': 1};
                } else {
                  _q.remove('foto');
                }
              }),
            ),
            if (foto != null) ...[
              SizedBox(
                width: 200,
                child: TextFormField(
                  initialValue: '${foto['numero'] ?? 1}',
                  decoration: InputDecoration(labelText: t.quanteFoto, helperText: t.daUnoADieci),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) => _cambia(() => foto['numero'] = int.tryParse(v) ?? 0),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: foto['istruzioni'] as String? ?? '',
                decoration: InputDecoration(labelText: t.istruzioniFoto, helperText: t.istruzioniFotoAiuto),
                minLines: 2,
                maxLines: 8,
                onChanged: (v) => _cambia(() {
                  if (v.trim().isEmpty) {
                    foto.remove('istruzioni');
                  } else {
                    foto['istruzioni'] = v;
                  }
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _domanda(Testi t, Map<String, Object?> d, int indice, int totale) {
    final tipo = d['tipo'] as String;
    return Card(
      key: _chiavi[d] ??= UniqueKey(),
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: d['testo'] as String? ?? '',
                    decoration: InputDecoration(labelText: t.domandaNumero(indice + 1)),
                    onChanged: (v) => _cambia(() => d['testo'] = v),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: tipo,
                  items: [
                    for (final tipo in TipoDomanda.tutti)
                      DropdownMenuItem(value: tipo, child: Text(etichettaTipo(t, tipo))),
                  ],
                  onChanged: (nuovo) => _cambia(() {
                    d['tipo'] = nuovo;
                    if (!TipoDomanda.conScelte.contains(nuovo)) {
                      d
                        ..remove('opzioni')
                        ..remove('altro');
                    } else {
                      d['opzioni'] ??= <Object?>[];
                    }
                    if (nuovo != TipoDomanda.numero) {
                      d
                        ..remove('unita')
                        ..remove('peso_corporeo');
                    }
                  }),
                ),
                IconButton(
                  tooltip: t.spostaSu,
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: indice > 0 ? () => _sposta(d, -1) : null,
                ),
                IconButton(
                  tooltip: t.spostaGiu,
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: indice < totale - 1 ? () => _sposta(d, 1) : null,
                ),
                IconButton(
                  tooltip: t.togliDomanda,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _cambia(() => (_q['domande']! as List<Object?>).remove(d)),
                ),
              ],
            ),
            if (TipoDomanda.conScelte.contains(tipo)) ...[
              const SizedBox(height: 12),
              TextFormField(
                initialValue: [...?(d['opzioni'] as List<Object?>?)].join('\n'),
                decoration: InputDecoration(labelText: t.opzioni, helperText: t.opzioniAiuto),
                minLines: 3,
                maxLines: 12,
                onChanged: (v) => _cambia(
                  () => d['opzioni'] = [
                    for (final riga in v.split('\n'))
                      if (riga.trim().isNotEmpty) riga.trim(),
                  ],
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(t.consentiAltro),
                value: d['altro'] == true,
                onChanged: (si) => _cambia(() => d['altro'] = si ?? false),
              ),
            ],
            if (tipo == TipoDomanda.numero) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 160,
                    child: TextFormField(
                      initialValue: d['unita'] as String? ?? '',
                      decoration: InputDecoration(labelText: t.unita, hintText: 'cm, kg, ore…'),
                      onChanged: (v) => _cambia(() {
                        if (v.trim().isEmpty) {
                          d.remove('unita');
                        } else {
                          d['unita'] = v.trim();
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(t.pesoCorporeo),
                      subtitle: Text(t.pesoCorporeoAiuto),
                      value: d['peso_corporeo'] == true,
                      onChanged: (si) => _cambia(() {
                        if (si ?? false) {
                          d['peso_corporeo'] = true;
                          d['unita'] ??= 'kg';
                        } else {
                          d.remove('peso_corporeo');
                        }
                      }),
                    ),
                  ),
                ],
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.obbligatoria),
              value: d['obbligatoria'] == true,
              onChanged: (si) => _cambia(() => d['obbligatoria'] = si),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un questionario mandato all'atleta, in mezzo alla chat: si leggono le
/// risposte, si annulla quello a cui non ha ancora risposto.
class CartaQuestionario extends StatelessWidget {
  const CartaQuestionario({
    super.key,
    required this.questionario,
    required this.atleta,
    required this.coach,
    required this.aggiornamenti,
  });

  final QuestionarioInviato questionario;
  final Atleta atleta;
  final Coach coach;
  final Aggiornamenti aggiornamenti;

  NucleoCoach get _nucleo => coach.nucleo;

  Future<void> _apri(BuildContext context) async {
    final q = questionario;
    _nucleo.questionari.segnaLetto(q.id);
    aggiornamenti.segnala();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('${q.titolo} · ${atleta.nome}')),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [RisposteQuestionario(questionario: q, nucleo: _nucleo)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final q = questionario;
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            leading: Badge(
              isLabelVisible: q.stato == StatoQuestionario.risposto && !q.letto,
              child: Icon(switch (q.stato) {
                StatoQuestionario.inviato => Icons.hourglass_empty,
                StatoQuestionario.risposto => Icons.assignment_turned_in_outlined,
                StatoQuestionario.annullato => Icons.block,
              }),
            ),
            title: Text(q.titolo),
            subtitle: Text(switch (q.stato) {
              StatoQuestionario.inviato => t.inAttesaDiRisposta(dataOra(q.inviatoIl)),
              StatoQuestionario.risposto => t.rispostoIl(dataOra(q.rispostoIl!)),
              StatoQuestionario.annullato => t.questionarioAnnullato,
            }),
            onTap: q.stato == StatoQuestionario.risposto ? () => _apri(context) : null,
            trailing: q.stato == StatoQuestionario.inviato
                ? TextButton(
                    onPressed: () async {
                      final sicuro = await conferma(
                        context,
                        titolo: t.annullaQuestionarioTitolo,
                        testo: t.annullaQuestionarioTesto,
                        azione: t.annullaQuestionario,
                        pericolosa: true,
                      );
                      if (!sicuro || !context.mounted) return;
                      await esegui(context, () async => _nucleo.questionari.annulla(q.id));
                      aggiornamenti.segnala();
                    },
                    child: Text(t.annullaQuestionario),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// Le risposte a un questionario, domanda per domanda, con le foto.
class RisposteQuestionario extends StatelessWidget {
  const RisposteQuestionario({super.key, required this.questionario, required this.nucleo});

  final QuestionarioInviato questionario;
  final NucleoCoach nucleo;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context).textTheme;
    final valori = {
      for (final r in (questionario.risposta?['risposte'] as List<Object?>?) ?? const [])
        if (r is Map<String, Object?>) r['domanda_id']: r['valore'],
    };
    final domande = [
      for (final d in (questionario.contenuto['domande'] as List<Object?>?) ?? const [])
        if (d is Map<String, Object?>) d,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (questionario.rispostoIl != null)
          Text(t.rispostoIl(dataOra(questionario.rispostoIl!)), style: tema.bodySmall),
        for (final d in domande) ...[
          const SizedBox(height: 16),
          Text(d['testo'] as String? ?? '', style: tema.titleSmall),
          const SizedBox(height: 4),
          SelectableText(valoreLeggibile(t, d, valori[d['id']])),
        ],
        if (questionario.foto.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(t.fotoAllegate, style: tema.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in questionario.foto)
                if (nucleo.questionari.foto(id) case final dati?)
                  InkWell(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => Dialog(
                        child: InteractiveViewer(child: Image.memory(dati)),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(dati, height: 180, fit: BoxFit.cover),
                    ),
                  ),
            ],
          ),
        ],
      ],
    );
  }
}

/// La risposta a una domanda come testo, o «—» se l'atleta non ha risposto.
String valoreLeggibile(Testi t, Map<String, Object?> domanda, Object? valore) {
  String numero(num n) => (n == n.roundToDouble() ? n.round() : n).toString().replaceAll('.', ',');
  return switch (valore) {
    null => '—',
    final String testo => testo,
    final num n when domanda['tipo'] == TipoDomanda.scala => '${numero(n)}/10',
    final num n => [numero(n), ?domanda['unita'] as String?].join(' '),
    {'scelta': final Object? s} => '$s',
    {'altro': final Object? a} when !valore.containsKey('scelte') => t.altroValore('$a'),
    {'scelte': final List<Object?> scelte} => [
      ...scelte.map((s) => '$s'),
      if (valore['altro'] case final Object a) t.altroValore('$a'),
    ].join(', '),
    _ => '$valore',
  };
}
