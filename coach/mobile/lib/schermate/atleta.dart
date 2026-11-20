import 'package:flutter/material.dart';

import '../dati/stato_coach.dart';
import '../l10n/testi.dart';
import 'allenamenti.dart';
import 'atleti.dart';
import 'chat.dart';
import 'cibo.dart';
import 'peso.dart';
import 'questionari.dart';
import 'scheda.dart';

/// Tutto di un atleta, una sezione per scheda: si apre sulla chat.
class SchermataAtleta extends StatelessWidget {
  const SchermataAtleta({super.key, required this.stato, required this.atletaId, required this.nome});

  final StatoCoach stato;
  final String atletaId;
  final String nome;

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(nome),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            // Le sezioni come pillole: più facili da toccare delle linguette.
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            dividerColor: Colors.transparent,
            indicator: const BoxDecoration(),
            splashBorderRadius: BorderRadius.circular(20),
            labelColor: Theme.of(context).colorScheme.onPrimary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurface,
            tabs: [
              for (final (i, nome) in [
                t.sezioneChat,
                t.sezioneAllenamenti,
                t.sezionePeso,
                t.sezioneCibo,
                t.sezioneQuestionari,
                t.sezioneScheda,
              ].indexed)
                _Pillola(nome, indice: i),
            ],
          ),
        ),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: stato,
            builder: (context, _) => Column(
              children: [
                RiquadroProblema(stato: stato),
                Expanded(
                  child: stato.collegato
                      ? TabBarView(
                          children: [
                            SezioneChat(stato: stato, atletaId: atletaId),
                            SezioneAllenamenti(stato: stato, atletaId: atletaId),
                            SezionePeso(stato: stato, atletaId: atletaId),
                            SezioneCibo(stato: stato, atletaId: atletaId),
                            SezioneQuestionari(stato: stato, atletaId: atletaId),
                            SezioneScheda(stato: stato, atletaId: atletaId),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una sezione dell'atleta come pillola: piena quando è quella aperta.
class _Pillola extends StatelessWidget {
  const _Pillola(this.nome, {required this.indice});

  final String nome;
  final int indice;

  @override
  Widget build(BuildContext context) {
    final controllo = DefaultTabController.of(context);
    final schema = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controllo.animation!,
      builder: (context, _) {
        final scelta = controllo.index == indice;
        return Tab(
          height: 40,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scelta ? schema.primary : schema.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scelta ? schema.primary : schema.outlineVariant),
            ),
            child: Text(nome),
          ),
        );
      },
    );
  }
}
