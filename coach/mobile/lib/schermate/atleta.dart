import 'package:flutter/material.dart';

import '../dati/stato_coach.dart';
import '../l10n/testi.dart';
import 'allenamenti.dart';
import 'atleti.dart';
import 'chat.dart';
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
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(nome),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: t.sezioneChat),
              Tab(text: t.sezioneAllenamenti),
              Tab(text: t.sezionePeso),
              Tab(text: t.sezioneQuestionari),
              Tab(text: t.sezioneScheda),
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
