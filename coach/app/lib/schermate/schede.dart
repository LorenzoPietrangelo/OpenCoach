import 'package:coach_nucleo/coach_nucleo.dart';
import 'package:flutter/material.dart';

import '../comuni.dart';
import '../l10n/testi.dart';
import '../tema.dart';
import '../servizi.dart';
import 'editor_scheda.dart';

/// Schede dell'atleta con lo stato di pubblicazione e di consegna (§9.3).
class PannelloSchede extends StatelessWidget {
  const PannelloSchede({
    super.key,
    required this.atleta,
    required this.coach,
    required this.aggiornamenti,
  });

  final Atleta atleta;
  final Coach coach;
  final Aggiornamenti aggiornamenti;

  NucleoCoach get _nucleo => coach.nucleo;

  Future<void> _apri(BuildContext context, String schedaId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScheda(
          schedaId: schedaId,
          atleta: atleta,
          nucleo: _nucleo,
          aggiornamenti: aggiornamenti,
        ),
      ),
    );
    aggiornamenti.segnala();
  }

  Future<void> _nuova(BuildContext context) async {
    final t = Testi.of(context);
    final id = _nucleo.schede.crea(
      atleta.id,
      contenuto: {'titolo': t.nuovaSchedaTitolo, 'note': '', 'sedute': <Object?>[]},
    );
    await _apri(context, id);
  }

  Future<void> _duplica(BuildContext context, Scheda scheda) async {
    final t = Testi.of(context);
    final destinatari = _nucleo.atleti.elenco();
    final scelto = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(t.duplicaPer),
        children: [
          for (final r in destinatari)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, r.atleta.id),
              child: Text(r.atleta.id == atleta.id ? t.stessoAtleta(r.atleta.nome) : r.atleta.nome),
            ),
        ],
      ),
    );
    if (scelto == null || !context.mounted) return;
    await esegui(context, () async {
      _nucleo.schede.duplica(scheda.id, atletaId: scelto);
      aggiornamenti.segnala();
      if (context.mounted) avviso(context, t.schedaDuplicata);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Testi.of(context);
    return ListenableBuilder(
      listenable: aggiornamenti,
      builder: (context, _) {
        final schede = _nucleo.schede.elenco(atleta.id);
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _nuova(context),
                icon: const Icon(Icons.add),
                label: Text(t.nuovaScheda),
              ),
            ),
            const SizedBox(height: 16),
            if (schede.isEmpty) Text(t.nessunaScheda),
            for (final scheda in schede)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  leading: _StatoScheda(scheda),
                  title: Text(
                    scheda.titolo.isEmpty ? t.senzaTitolo : scheda.titolo,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      descriviScheda(t, scheda),
                      style: scheda.modificheNonPubblicate
                          ? TextStyle(color: ColoriCoach.of(context).attesa, fontWeight: FontWeight.w500)
                          : null,
                    ),
                  ),
                  onTap: () => _apri(context, scheda.id),
                  trailing: PopupMenuButton<String>(
                    tooltip: t.altreAzioni,
                    onSelected: (azione) async {
                      switch (azione) {
                        case 'duplica':
                          await _duplica(context, scheda);
                        case 'archivia':
                          _nucleo.schede.archivia(scheda.id);
                        case 'ripristina':
                          _nucleo.schede.ripristina(scheda.id);
                        case 'elimina':
                          final sicuro = await conferma(
                            context,
                            titolo: t.eliminaSchedaTitolo,
                            testo: scheda.revisione > 0 ? t.eliminaSchedaPubblicata : t.eliminaBozza,
                            azione: t.elimina,
                            pericolosa: true,
                          );
                          if (sicuro) _nucleo.schede.elimina(scheda.id);
                      }
                      aggiornamenti.segnala();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'duplica', child: Text(t.duplica)),
                      if (scheda.stato == StatoScheda.pubblicata)
                        PopupMenuItem(value: 'archivia', child: Text(t.archivia)),
                      if (scheda.stato == StatoScheda.archiviata)
                        PopupMenuItem(value: 'ripristina', child: Text(t.riportaTraLeAttive)),
                      PopupMenuItem(value: 'elimina', child: Text(t.elimina)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Stato di una scheda in una riga: pubblicazione, consegna, bozza.
String descriviScheda(Testi t, Scheda scheda) {
  if (scheda.stato == StatoScheda.bozza) return t.bozzaMaiPubblicata;
  final ultima = scheda.revisioni.first;
  final parti = [
    if (scheda.stato == StatoScheda.archiviata) t.archiviata,
    t.revisione(scheda.revisione),
    ultima.ricevutaIl == null ? t.inAttesaDiConsegna : t.ricevutaIl(dataOra(ultima.ricevutaIl!)),
    if (scheda.modificheNonPubblicate) t.modificheNonPubblicate,
  ];
  return parti.join(' · ');
}

/// Lo stato della scheda in un cerchio: teal se pubblicata, arancio se ha
/// modifiche non pubblicate, grigio se bozza o archiviata.
class _StatoScheda extends StatelessWidget {
  const _StatoScheda(this.scheda);

  final Scheda scheda;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    final attesa = ColoriCoach.of(context);
    final (colore, sfondo) = switch (scheda.stato) {
      StatoScheda.pubblicata when scheda.modificheNonPubblicate => (attesa.attesa, attesa.attesaContenitore),
      StatoScheda.pubblicata => (schema.primary, schema.primaryContainer),
      _ => (schema.onSurfaceVariant, schema.surfaceContainer),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: sfondo, shape: BoxShape.circle),
      child: Icon(
        switch (scheda.stato) {
          StatoScheda.bozza => Icons.edit_note,
          StatoScheda.pubblicata => Icons.assignment_turned_in_outlined,
          StatoScheda.archiviata => Icons.inventory_2_outlined,
        },
        size: 20,
        color: colore,
      ),
    );
  }
}
