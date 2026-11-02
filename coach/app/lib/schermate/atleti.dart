import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../piattaforma/desktop.dart';
import '../servizi.dart';
import 'atleta.dart';

/// Elenco degli atleti a sinistra, dettaglio di quello scelto a destra.
class SchermataAtleti extends StatefulWidget {
  const SchermataAtleti({
    super.key,
    required this.coach,
    required this.desktop,
    required this.aggiornamenti,
  });

  final Coach coach;
  final Desktop desktop;
  final Aggiornamenti aggiornamenti;

  @override
  State<SchermataAtleti> createState() => _SchermataAtletiState();
}

class _SchermataAtletiState extends State<SchermataAtleti> {
  String? _scelto;
  var _archiviati = false;

  NucleoCoach get _nucleo => widget.coach.nucleo;

  Future<void> _nuovo() async {
    final t = Testi.of(context);
    final nome = await chiediTesto(context, titolo: t.nuovoAtleta, etichetta: t.nomeAtleta);
    if (nome == null || !mounted) return;
    await esegui(context, () async {
      final atleta = _nucleo.atleti.crea(nome);
      setState(() {
        _archiviati = false;
        _scelto = atleta.id;
      });
      widget.aggiornamenti.segnala();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return ListenableBuilder(
      listenable: widget.aggiornamenti,
      builder: (context, _) {
        final elenco = _nucleo.atleti.elenco(archiviati: _archiviati);
        if (_scelto != null && _nucleo.atleti.cerca(_scelto!) == null) _scelto = null;
        return Row(
          children: [
            SizedBox(
              width: 320,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _archiviati ? t.atletiArchiviati : t.sezioneAtleti,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: _archiviati ? t.mostraAttivi : t.mostraArchiviati,
                          icon: Icon(_archiviati ? Icons.unarchive_outlined : Icons.archive_outlined),
                          onPressed: () => setState(() => _archiviati = !_archiviati),
                        ),
                        FilledButton.icon(
                          onPressed: _nuovo,
                          icon: const Icon(Icons.person_add_alt),
                          label: Text(t.nuovo),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: elenco.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_archiviati ? t.nessunAtletaArchiviato : t.nessunAtleta),
                          )
                        : ListView(
                            children: [
                              for (final r in elenco)
                                ListTile(
                                  selected: r.atleta.id == _scelto,
                                  leading: Badge(
                                    // Messaggi della chat non ancora letti.
                                    isLabelVisible: _nucleo.messaggi.nonLetti(r.atleta.id) > 0,
                                    child: CircleAvatar(
                                      child: Text(r.atleta.nome.characters.first.toUpperCase()),
                                    ),
                                  ),
                                  title: Text(r.atleta.nome),
                                  subtitle: Text(_riassunto(t, r)),
                                  onTap: () => setState(() => _scelto = r.atleta.id),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _scelto == null
                  ? Center(child: Text(t.scegliAtleta))
                  : DettaglioAtleta(
                      key: ValueKey(_scelto),
                      atletaId: _scelto!,
                      coach: widget.coach,
                      desktop: widget.desktop,
                      aggiornamenti: widget.aggiornamenti,
                    ),
            ),
          ],
        );
      },
    );
  }

  String _riassunto(Testi t, RiepilogoAtleta r) {
    final d = r.dispositivo;
    if (d != null) {
      final contatto = d.ultimoContatto;
      return contatto == null
          ? t.telefonoMaiSincronizzato(d.nome)
          : t.telefonoUltimoContatto(d.nome, dataOra(contatto));
    }
    if (r.invito != null) return t.invitoInCorso;
    return t.nessunTelefono;
  }
}
