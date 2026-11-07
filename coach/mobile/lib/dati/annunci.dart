import 'dart:convert';

import 'cassaforte.dart';
import 'modelli.dart';

const _voce = 'annunciati';

/// Una novità da annunciare con una notifica.
class Annuncio {
  const Annuncio({required this.atletaId, required this.nome, required this.messaggi, required this.risposte});

  final String atletaId;
  final String nome;

  /// Messaggi non letti in tutto, se ce ne sono di nuovi; altrimenti 0.
  final int messaggi;

  /// Risposte non aperte in tutto, se ce ne sono di nuove; altrimenti 0.
  final int risposte;
}

/// Per ogni atleta, quanti non letti l'app ha già annunciato (§16.4): così una
/// notifica parte solo per le novità vere.
class RegistroAnnunci {
  RegistroAnnunci(this._cassaforte);

  final Cassaforte _cassaforte;

  /// Confronta [atleti] con l'ultima volta e ricorda i nuovi numeri.
  Future<List<Annuncio>> confronta(List<RiepilogoAtleta> atleti) async {
    final salvati = await _leggi();
    final annunci = <Annuncio>[
      for (final a in atleti)
        if (a.nonLetti > (salvati[a.id]?.$1 ?? 0) || a.risposteNuove > (salvati[a.id]?.$2 ?? 0))
          Annuncio(
            atletaId: a.id,
            nome: a.nome,
            messaggi: a.nonLetti > (salvati[a.id]?.$1 ?? 0) ? a.nonLetti : 0,
            risposte: a.risposteNuove > (salvati[a.id]?.$2 ?? 0) ? a.risposteNuove : 0,
          ),
    ];
    await ricorda(atleti);
    return annunci;
  }

  /// Il coach ha i numeri sotto gli occhi: non vanno annunciati dopo.
  Future<void> ricorda(List<RiepilogoAtleta> atleti) => _cassaforte.scrivi(
    _voce,
    jsonEncode({
      for (final a in atleti) a.id: [a.nonLetti, a.risposteNuove],
    }),
  );

  Future<void> cancella() => _cassaforte.elimina(_voce);

  Future<Map<String, (int, int)>> _leggi() async {
    final json = await leggiJson(_cassaforte, _voce);
    return {
      if (json is Map<String, Object?>)
        for (final MapEntry(:key, :value) in json.entries)
          if (value case [final int messaggi, final int risposte]) key: (messaggi, risposte),
    };
  }
}
