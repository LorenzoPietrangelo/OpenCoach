import 'package:flutter/material.dart';

import '../dati/modelli.dart';
import '../dati/stato_coach.dart';
import '../l10n/testi.dart';
import '../piattaforma/background.dart';
import 'atleta.dart';
import 'comuni.dart';
import 'impostazioni.dart';

/// L'elenco degli atleti, con chi ha scritto in cima (§16.3).
class SchermataAtleti extends StatelessWidget {
  const SchermataAtleti({super.key, required this.stato, this.background});

  final StatoCoach stato;
  final ControlliInBackground? background;

  void _apri(BuildContext context, RiepilogoAtleta atleta) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SchermataAtleta(stato: stato, atletaId: atleta.id, nome: atleta.nome),
    ),
  );

  /// Prima chi ha novità, dalla più recente; poi per nome, come sul PC.
  List<RiepilogoAtleta> _ordinati() {
    final conNovita = stato.atleti.where((a) => a.nonLetti + a.risposteNuove > 0).toList()
      ..sort((a, b) {
        final prima = a.ultimoMessaggio?.inviatoIl;
        final dopo = b.ultimoMessaggio?.inviatoIl;
        if (prima == null || dopo == null) return prima == dopo ? 0 : (prima == null ? 1 : -1);
        return dopo.compareTo(prima);
      });
    return [...conNovita, ...stato.atleti.where((a) => a.nonLetti + a.risposteNuove == 0)];
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.atletiTitolo),
        actions: [
          IconButton(
            tooltip: t.impostazioniTitolo,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SchermataImpostazioni(stato: stato, background: background),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: stato,
          builder: (context, _) {
            final atleti = _ordinati();
            return Column(
              children: [
                RiquadroProblema(stato: stato),
                Expanded(
                  child: !stato.caricato
                      ? _Attesa(testo: t.atletiCaricamento, conProblema: stato.problema != null || stato.inCollegamento)
                      : atleti.isEmpty
                      ? ListaVuota(t.atletiVuoto)
                      : RefreshIndicator(
                          onRefresh: () async => stato.riprova(),
                          child: ListView.separated(
                            itemCount: atleti.length,
                            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                            itemBuilder: (context, i) =>
                                _RigaAtleta(atleta: atleti[i], apri: () => _apri(context, atleti[i])),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Attesa extends StatelessWidget {
  const _Attesa({required this.testo, required this.conProblema});

  final String testo;

  /// Il riquadro sopra spiega già: basta la rotella.
  final bool conProblema;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        if (!conProblema) ...[const SizedBox(height: 16), Text(testo)],
      ],
    ),
  );
}

class _RigaAtleta extends StatelessWidget {
  const _RigaAtleta({required this.atleta, required this.apri});

  final RiepilogoAtleta atleta;
  final VoidCallback apri;

  String _sottotitolo(Testi t) {
    if (atleta.risposteNuove > 0 && atleta.nonLetti == 0) return t.risposteNuove(atleta.risposteNuove);
    final ultimo = atleta.ultimoMessaggio;
    if (ultimo == null) return atleta.telefonoCollegato ? t.atletaNessunMessaggio : t.atletaSenzaTelefono;
    final testo = ultimo.testo.isEmpty && ultimo.conVideo ? t.anteprimaVideo : ultimo.testo;
    return ultimo.dalCoach ? t.anteprimaTu(testo) : testo;
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context);
    final nuovi = atleta.nonLetti + atleta.risposteNuove;
    final quando = atleta.ultimoMessaggio?.inviatoIl;
    return ListTile(
      onTap: apri,
      leading: CircleAvatar(child: Text(atleta.nome.isEmpty ? '?' : atleta.nome.characters.first.toUpperCase())),
      title: Text(
        atleta.nome,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: nuovi > 0 ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      subtitle: Text(_sottotitolo(t), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (quando != null) Text(quandoBreve(quando), style: tema.textTheme.labelSmall),
          if (nuovi > 0) ...[const SizedBox(height: 4), Badge(label: Text('$nuovi'))],
        ],
      ),
    );
  }
}

/// Dice perché i dati possono essere vecchi. Con un problema vero si può
/// riprovare subito.
class RiquadroProblema extends StatelessWidget {
  const RiquadroProblema({super.key, required this.stato});

  final StatoCoach stato;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    final tema = Theme.of(context);
    final testo = stato.inCollegamento ? t.problemaInCollegamento : testoProblema(t, stato.problema);
    if (testo == null) return const SizedBox.shrink();
    return Material(
      color: tema.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(child: Text(testo, style: TextStyle(color: tema.colorScheme.onSecondaryContainer))),
            TextButton(onPressed: stato.riprova, child: Text(t.riprova)),
          ],
        ),
      ),
    );
  }
}
