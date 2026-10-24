import 'package:atleta_nucleo/atleta_nucleo.dart';
import 'package:protocollo/protocollo.dart';

/// Seduta di una scheda (§8.1), come l'ha scritta il coach.
class Seduta {
  const Seduta({
    required this.id,
    required this.nome,
    required this.note,
    required this.esercizi,
  });

  final String id;
  final String nome;
  final String note;
  final List<EsercizioPrevisto> esercizi;
}

/// Esercizio di una seduta, con la prescrizione del coach.
class EsercizioPrevisto {
  const EsercizioPrevisto({
    required this.id,
    required this.nome,
    required this.note,
    required this.prescrizione,
  });

  /// Stabile tra le revisioni: i log lo citano (§8.1).
  final String id;
  final String nome;
  final String note;
  final List<RigaPrescrizione> prescrizione;
}

/// Una riga della prescrizione. Tutti i campi sono facoltativi; ripetizioni,
/// carico e RIR sono testo libero, come «6-8», «75% 1RM» o «1-2» (§8.1).
class RigaPrescrizione {
  const RigaPrescrizione({
    this.serie,
    this.ripetizioni,
    this.carico,
    this.recupero,
    this.rir,
  });

  final int? serie;
  final String? ripetizioni;
  final String? carico;
  final Duration? recupero;

  /// Ripetizioni da lasciare in riserva, testo libero come «2» o «1-2».
  final String? rir;
}

/// Note, validità e sedute di una scheda ricevuta, lette dal JSON del coach
/// che il nucleo ha già validato all'arrivo.
extension ContenutoScheda on SchedaRicevuta {
  String get note => _testo(contenuto['note']) ?? '';

  DateTime? get validaDal => analizzaData(contenuto['valida_dal']);

  DateTime? get validaAl => analizzaData(contenuto['valida_al']);

  List<Seduta> get sedute => [
    for (final seduta in _oggetti(contenuto['sedute']))
      Seduta(
        id: _testo(seduta['id']) ?? '',
        nome: _testo(seduta['nome']) ?? '',
        note: _testo(seduta['note']) ?? '',
        esercizi: [
          for (final esercizio in _oggetti(seduta['esercizi']))
            EsercizioPrevisto(
              id: _testo(esercizio['id']) ?? '',
              nome: _testo(esercizio['nome']) ?? '',
              note: _testo(esercizio['note']) ?? '',
              prescrizione: [
                for (final riga in _oggetti(esercizio['prescrizione']))
                  RigaPrescrizione(
                    serie: _intero(riga['serie']),
                    ripetizioni: _testo(riga['ripetizioni']),
                    carico: _testo(riga['carico']),
                    recupero: switch (_intero(riga['recupero_s'])) {
                      final int secondi => Duration(seconds: secondi),
                      null => null,
                    },
                    rir: _testo(riga['rir']),
                  ),
              ],
            ),
        ],
      ),
  ];

  Seduta? seduta(String? id) =>
      id == null ? null : sedute.where((s) => s.id == id).firstOrNull;
}

/// Nomi delle sedute delle schede, per id: i log citano la seduta solo con
/// l'id (§8.2).
Map<String, String> nomiSedute(Iterable<SchedaRicevuta> schede) => {
  for (final scheda in schede)
    for (final seduta in scheda.sedute) seduta.id: seduta.nome,
};

List<Map<String, Object?>> _oggetti(Object? valore) => [
  if (valore is List<Object?>)
    for (final elemento in valore)
      if (elemento is Map<String, Object?>) elemento,
];

String? _testo(Object? valore) => valore is String ? valore : null;

int? _intero(Object? valore) => valore is int ? valore : null;
