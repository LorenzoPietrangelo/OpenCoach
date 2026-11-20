import 'package:flutter/material.dart';

import '../dati/modelli.dart';
import '../dati/stato_coach.dart';
import '../l10n/testi.dart';
import '../tema.dart';
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
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              Card(
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  children: [
                                    for (final (i, atleta) in atleti.indexed) ...[
                                      if (i > 0) const Divider(),
                                      _RigaAtleta(atleta: atleta, apri: () => _apri(context, atleta)),
                                    ],
                                  ],
                                ),
                              ),
                            ],
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
    final senzaTelefono = atleta.ultimoMessaggio == null && !atleta.telefonoCollegato;
    return ListTile(
      onTap: apri,
      shape: const RoundedRectangleBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: InizialeAtleta(atleta.nome, piena: nuovi > 0, diametro: 44),
      title: Text(
        atleta.nome,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tema.textTheme.titleMedium?.copyWith(
          fontWeight: nuovi > 0 ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        _sottotitolo(t),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: senzaTelefono
            ? TextStyle(color: ColoriCoach.of(context).attesa, fontWeight: FontWeight.w500)
            : nuovi > 0
            ? TextStyle(color: tema.colorScheme.onSurface)
            : null,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (quando != null)
            Text(
              quandoBreve(quando),
              style: tema.textTheme.labelSmall?.copyWith(
                color: nuovi > 0 ? tema.colorScheme.primary : tema.colorScheme.onSurfaceVariant,
              ),
            ),
          if (nuovi > 0) ...[const SizedBox(height: 4), Contatore(nuovi)],
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
    final testo = stato.inCollegamento ? t.problemaInCollegamento : testoProblema(t, stato.problema);
    if (testo == null) return const SizedBox.shrink();
    final colori = ColoriCoach.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: FasciaAvviso(
        icona: Icons.schedule,
        testo: testo,
        azione: TextButton(
          style: TextButton.styleFrom(foregroundColor: colori.attesa),
          onPressed: stato.riprova,
          child: Text(t.riprova),
        ),
      ),
    );
  }
}
