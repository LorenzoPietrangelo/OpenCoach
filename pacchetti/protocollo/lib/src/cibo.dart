import 'date.dart';

// Il diario del cibo (§8.8): l'atleta registra cosa mangia, il coach fissa
// un obiettivo di calorie e macronutrienti. Le classi sono condivise da app e
// programma, così i totali si calcolano allo stesso modo.

/// I pasti di una giornata, nell'ordine in cui si mostrano.
const pastiCibo = ['colazione', 'pranzo', 'cena', 'spuntini'];

/// Da dove vengono i valori di una voce.
abstract final class FonteCibo {
  static const openFoodFacts = 'open_food_facts';
  static const atleta = 'atleta';
  static const tutte = {openFoodFacts, atleta};
}

/// Limiti del diario del cibo (§8.8).
abstract final class LimitiCibo {
  static const giornatePerRichiesta = 100;
  static const giornataMassima = 64 * 1024;
  static const vociPerGiornata = 200;
  static const nomeMassimo = 200;
  static const marcaMassima = 100;
  static const grammiMinimi = 0.1;
  static const grammiMassimi = 5000;
  static const kcalPer100gMassime = 900;
  static const kcalObiettivoMinime = 500;
  static const kcalObiettivoMassime = 8000;
  static const grammiObiettivoMassimi = 1000;
}

/// Calorie e macronutrienti. I macronutrienti sono null quando non si
/// conoscono.
class ValoriCibo {
  const ValoriCibo({required this.kcal, this.proteine, this.carboidrati, this.grassi});

  static const zero = ValoriCibo(kcal: 0, proteine: 0, carboidrati: 0, grassi: 0);

  /// Valori per 100 g come li scrive il protocollo, senza controlli: vanno
  /// prima validati.
  factory ValoriCibo.fromJson(Map<String, Object?> m) => ValoriCibo(
    kcal: (m['kcal']! as num).toDouble(),
    proteine: (m['proteine'] as num?)?.toDouble(),
    carboidrati: (m['carboidrati'] as num?)?.toDouble(),
    grassi: (m['grassi'] as num?)?.toDouble(),
  );

  final double kcal;
  final double? proteine;
  final double? carboidrati;
  final double? grassi;

  /// I valori moltiplicati per [fattore], per esempio grammi / 100.
  ValoriCibo per(double fattore) => ValoriCibo(
    kcal: kcal * fattore,
    proteine: proteine == null ? null : proteine! * fattore,
    carboidrati: carboidrati == null ? null : carboidrati! * fattore,
    grassi: grassi == null ? null : grassi! * fattore,
  );

  /// Somma per i totali: un macronutriente che non si conosce vale zero.
  ValoriCibo operator +(ValoriCibo altro) => ValoriCibo(
    kcal: kcal + altro.kcal,
    proteine: (proteine ?? 0) + (altro.proteine ?? 0),
    carboidrati: (carboidrati ?? 0) + (altro.carboidrati ?? 0),
    grassi: (grassi ?? 0) + (altro.grassi ?? 0),
  );

  Map<String, Object?> toJson() => {
    'kcal': _arrotonda(kcal),
    if (proteine != null) 'proteine': _arrotonda(proteine!),
    if (carboidrati != null) 'carboidrati': _arrotonda(carboidrati!),
    if (grassi != null) 'grassi': _arrotonda(grassi!),
  };

  /// Un decimale basta: le etichette non sono più precise di così.
  static num _arrotonda(double v) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.round() : r;
  }
}

/// Un alimento mangiato: copia nome e valori, così la giornata resta giusta
/// anche se il prodotto cambia (§8.8).
class VoceCibo {
  const VoceCibo({
    required this.id,
    required this.pasto,
    required this.nome,
    required this.fonte,
    required this.grammi,
    required this.per100g,
    this.marca,
    this.codice,
  });

  /// Da una voce già validata.
  factory VoceCibo.fromJson(Map<String, Object?> m) => VoceCibo(
    id: m['id']! as String,
    pasto: m['pasto']! as String,
    nome: m['nome']! as String,
    marca: m['marca'] as String?,
    codice: m['codice'] as String?,
    fonte: m['fonte']! as String,
    grammi: (m['grammi']! as num).toDouble(),
    per100g: ValoriCibo.fromJson(m['per_100g']! as Map<String, Object?>),
  );

  final String id;
  final String pasto;
  final String nome;
  final String? marca;

  /// Codice a barre, se l'alimento viene da una confezione.
  final String? codice;
  final String fonte;
  final double grammi;
  final ValoriCibo per100g;

  /// Calorie e macronutrienti della porzione mangiata.
  ValoriCibo get valori => per100g.per(grammi / 100);

  Map<String, Object?> toJson() => {
    'id': id,
    'pasto': pasto,
    'nome': nome,
    'marca': ?marca,
    'codice': ?codice,
    'fonte': fonte,
    'grammi': ValoriCibo._arrotonda(grammi),
    'per_100g': per100g.toJson(),
  };
}

/// Il diario del cibo di un giorno (§8.8).
class GiornataCibo {
  const GiornataCibo({required this.giorno, required this.voci});

  /// Da una giornata non eliminata e già validata.
  factory GiornataCibo.fromJson(Map<String, Object?> m) => GiornataCibo(
    giorno: analizzaData(m['giorno'])!,
    voci: [
      for (final voce in m['voci']! as List<Object?>) VoceCibo.fromJson(voce! as Map<String, Object?>),
    ],
  );

  final DateTime giorno;
  final List<VoceCibo> voci;

  ValoriCibo get totali => voci.fold(ValoriCibo.zero, (somma, v) => somma + v.valori);

  /// Le voci di un pasto, nell'ordine in cui l'atleta le ha aggiunte.
  List<VoceCibo> delPasto(String pasto) => [
    for (final v in voci)
      if (v.pasto == pasto) v,
  ];
}

/// Obiettivo di calorie e macronutrienti fissato dal coach (§8.8): indicativo,
/// non una dieta.
class ObiettivoCibo {
  const ObiettivoCibo({required this.kcal, this.proteineG, this.carboidratiG, this.grassiG});

  /// Da un obiettivo già validato.
  factory ObiettivoCibo.fromJson(Map<String, Object?> m) => ObiettivoCibo(
    kcal: (m['kcal']! as num).round(),
    proteineG: (m['proteine_g'] as num?)?.round(),
    carboidratiG: (m['carboidrati_g'] as num?)?.round(),
    grassiG: (m['grassi_g'] as num?)?.round(),
  );

  final int kcal;
  final int? proteineG;
  final int? carboidratiG;
  final int? grassiG;

  Map<String, Object?> toJson() => {
    'kcal': kcal,
    'proteine_g': ?proteineG,
    'carboidrati_g': ?carboidratiG,
    'grassi_g': ?grassiG,
  };

  @override
  bool operator ==(Object other) =>
      other is ObiettivoCibo &&
      other.kcal == kcal &&
      other.proteineG == proteineG &&
      other.carboidratiG == carboidratiG &&
      other.grassiG == grassiG;

  @override
  int get hashCode => Object.hash(kcal, proteineG, carboidratiG, grassiG);
}

/// Un prodotto del catalogo dei cibi che il programma del coach tiene sul PC
/// (§10.3): i prodotti venduti in Italia di Open Food Facts, con le calorie.
class ProdottoCibo {
  const ProdottoCibo({
    required this.codice,
    required this.nome,
    required this.per100g,
    this.marca,
    this.porzioneG,
  });

  /// Da un prodotto già validato con `validaProdottoCibo`.
  factory ProdottoCibo.fromJson(Map<String, Object?> m) => ProdottoCibo(
    codice: m['codice']! as String,
    nome: m['nome']! as String,
    marca: m['marca'] as String?,
    porzioneG: (m['porzione_g'] as num?)?.toDouble(),
    per100g: ValoriCibo.fromJson(m['per_100g']! as Map<String, Object?>),
  );

  /// Codice a barre, da 8 a 14 cifre.
  final String codice;
  final String nome;
  final String? marca;

  /// La porzione indicata sulla confezione, se c'è.
  final double? porzioneG;
  final ValoriCibo per100g;

  Map<String, Object?> toJson() => {
    'codice': codice,
    'nome': nome,
    'marca': ?marca,
    'porzione_g': ?porzioneG,
    'per_100g': per100g.toJson(),
  };
}

/// Converte un prodotto di Open Food Facts, come lo danno la sua API o una
/// riga della sua esportazione CSV. Null se manca il nome, il codice a barre
/// o le calorie; i valori fuori dagli intervalli del §8.8 si scartano.
ProdottoCibo? prodottoDaOff(Map<String, Object?> p) {
  String? testo(Object? v) => switch (v) {
    final String s when s.trim().isNotEmpty => s.trim(),
    _ => null,
  };
  double? numero(Object? v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s.trim().replaceAll(',', '.')),
    _ => null,
  };
  double? entro(Object? v, num massimo) => switch (numero(v)) {
    final double n when n >= 0 && n <= massimo => n,
    _ => null,
  };
  String taglia(String s, int massimo) => s.length > massimo ? s.substring(0, massimo) : s;

  final nome = testo(p['product_name_it']) ?? testo(p['product_name']);
  final codice = testo(p['code']);
  if (nome == null || codice == null || !RegExp(r'^\d{8,14}$').hasMatch(codice)) return null;
  // `brands` è un testo separato da virgole, o una lista.
  final marca = switch (p['brands']) {
    final List<Object?> marche => marche.map(testo).nonNulls.firstOrNull,
    final Object? altro => testo(testo(altro)?.split(',').first),
  };
  final nutrienti = switch (p['nutriments']) {
    final Map<String, Object?> m => m,
    _ => const <String, Object?>{},
  };
  final kj = numero(nutrienti['energy-kj_100g']) ?? numero(nutrienti['energy_100g']);
  final kcal =
      entro(nutrienti['energy-kcal_100g'], LimitiCibo.kcalPer100gMassime) ??
      (kj == null ? null : entro((kj / 4.184).roundToDouble(), LimitiCibo.kcalPer100gMassime));
  if (kcal == null) return null;
  final porzione = numero(p['serving_quantity']);
  return ProdottoCibo(
    codice: codice,
    nome: taglia(nome, LimitiCibo.nomeMassimo),
    marca: marca == null ? null : taglia(marca, LimitiCibo.marcaMassima),
    porzioneG: porzione != null && porzione >= LimitiCibo.grammiMinimi && porzione <= LimitiCibo.grammiMassimi
        ? porzione
        : null,
    per100g: ValoriCibo(
      kcal: kcal,
      proteine: entro(nutrienti['proteins_100g'], 100),
      carboidrati: entro(nutrienti['carbohydrates_100g'], 100),
      grassi: entro(nutrienti['fat_100g'], 100),
    ),
  );
}
