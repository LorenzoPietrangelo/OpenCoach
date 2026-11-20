import 'package:flutter/material.dart';

// Lo stesso aspetto dell'app dell'atleta (atleta/app/lib/tema.dart): il teal
// di sempre, superfici chiare con bordo invece delle ombre, cifre tabellari.
// Il file è uguale in coach/app e coach/mobile: se cambia, cambia in tutti e due.

/// I colori fuori dallo schema di Material: lo stato «in attesa» in arancio,
/// distinto dall'errore anche per luminosità.
class ColoriCoach extends ThemeExtension<ColoriCoach> {
  const ColoriCoach({
    required this.attesa,
    required this.attesaContenitore,
    required this.suAttesaContenitore,
  });

  static const chiari = ColoriCoach(
    attesa: Color(0xFF8A4300),
    attesaContenitore: Color(0xFFFDEBD8),
    suAttesaContenitore: Color(0xFF4D2600),
  );

  static const scuri = ColoriCoach(
    attesa: Color(0xFFFFB77C),
    attesaContenitore: Color(0xFF4D2A08),
    suAttesaContenitore: Color(0xFFFFDCC2),
  );

  final Color attesa;
  final Color attesaContenitore;
  final Color suAttesaContenitore;

  static ColoriCoach of(BuildContext context) =>
      Theme.of(context).extension<ColoriCoach>() ?? chiari;

  @override
  ColoriCoach copyWith({Color? attesa, Color? attesaContenitore, Color? suAttesaContenitore}) =>
      ColoriCoach(
        attesa: attesa ?? this.attesa,
        attesaContenitore: attesaContenitore ?? this.attesaContenitore,
        suAttesaContenitore: suAttesaContenitore ?? this.suAttesaContenitore,
      );

  @override
  ColoriCoach lerp(ColoriCoach? altro, double t) {
    if (altro == null) return this;
    return ColoriCoach(
      attesa: Color.lerp(attesa, altro.attesa, t)!,
      attesaContenitore: Color.lerp(attesaContenitore, altro.attesaContenitore, t)!,
      suAttesaContenitore: Color.lerp(suAttesaContenitore, altro.suAttesaContenitore, t)!,
    );
  }
}

/// Il tema delle app del coach, chiaro o scuro.
ThemeData temaCoach({Brightness luminosita = Brightness.light}) {
  final scuro = luminosita == Brightness.dark;
  final base = ColorScheme.fromSeed(seedColor: Colors.teal, brightness: luminosita);
  final schema = scuro
      ? base.copyWith(
          primary: const Color(0xFF5FD3C1),
          onPrimary: const Color(0xFF00382F),
          primaryContainer: const Color(0xFF0F4F47),
          onPrimaryContainer: const Color(0xFFBFF0E7),
          secondaryContainer: const Color(0xFF0F4F47),
          onSecondaryContainer: const Color(0xFFBFF0E7),
          surface: const Color(0xFF17211F),
          onSurface: const Color(0xFFE3ECE9),
          onSurfaceVariant: const Color(0xFFA6B8B3),
          surfaceContainerLowest: const Color(0xFF17211F),
          surfaceContainerLow: const Color(0xFF0F1715),
          surfaceContainer: const Color(0xFF22302D),
          surfaceContainerHigh: const Color(0xFF22302D),
          surfaceContainerHighest: const Color(0xFF2A3936),
          outline: const Color(0xFF52625E),
          outlineVariant: const Color(0xFF2C3B38),
        )
      : base.copyWith(
          primary: const Color(0xFF0A6B60),
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFD3EEE9),
          onPrimaryContainer: const Color(0xFF053D37),
          secondaryContainer: const Color(0xFFD3EEE9),
          onSecondaryContainer: const Color(0xFF053D37),
          surface: Colors.white,
          onSurface: const Color(0xFF10201D),
          onSurfaceVariant: const Color(0xFF4A5B57),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF3F6F5),
          surfaceContainer: const Color(0xFFE9EFED),
          surfaceContainerHigh: const Color(0xFFE9EFED),
          surfaceContainerHighest: const Color(0xFFE2EAE8),
          outline: const Color(0xFFC9D4D1),
          outlineVariant: const Color(0xFFDCE4E2),
          error: const Color(0xFFA3231B),
          errorContainer: const Color(0xFFFBE3E1),
        );
  final sfondo = schema.surfaceContainerLow;
  final dati = ThemeData(colorScheme: schema);
  const tabellari = [FontFeature.tabularFigures()];
  TextStyle? cifre(TextStyle? stile, {FontWeight? peso}) =>
      stile?.copyWith(fontFeatures: tabellari, fontWeight: peso);
  final testi = dati.textTheme;
  final textTheme = testi.copyWith(
    displaySmall: cifre(testi.displaySmall, peso: FontWeight.w700),
    headlineMedium: cifre(testi.headlineMedium, peso: FontWeight.w700),
    headlineSmall: cifre(testi.headlineSmall, peso: FontWeight.w700),
    titleLarge: cifre(testi.titleLarge, peso: FontWeight.w700),
    titleMedium: cifre(testi.titleMedium, peso: FontWeight.w600),
    titleSmall: cifre(testi.titleSmall, peso: FontWeight.w600),
    bodyLarge: cifre(testi.bodyLarge),
    bodyMedium: cifre(testi.bodyMedium),
    bodySmall: cifre(testi.bodySmall)?.copyWith(color: schema.onSurfaceVariant),
    labelLarge: cifre(testi.labelLarge, peso: FontWeight.w600),
    labelMedium: cifre(testi.labelMedium, peso: FontWeight.w600),
    labelSmall: cifre(testi.labelSmall, peso: FontWeight.w600),
  );
  final arrotondato = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return dati.copyWith(
    scaffoldBackgroundColor: sfondo,
    textTheme: textTheme,
    extensions: [if (scuro) ColoriCoach.scuri else ColoriCoach.chiari],
    appBarTheme: AppBarTheme(
      backgroundColor: sfondo,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      foregroundColor: schema.onSurface,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: schema.onSurface,
        fontSize: 22,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: schema.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: schema.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 44), shape: arrotondato),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        shape: arrotondato,
        side: BorderSide(color: schema.outlineVariant),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: schema.primary,
      foregroundColor: schema.onPrimary,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: schema.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: schema.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: schema.primary, width: 2),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: schema.surface,
      indicatorColor: schema.primaryContainer,
      selectedIconTheme: IconThemeData(color: schema.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: schema.onSurfaceVariant),
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: schema.onPrimaryContainer),
      unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: schema.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: schema.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: schema.primaryContainer,
      elevation: 0,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: schema.primary,
      unselectedLabelColor: schema.onSurfaceVariant,
      indicatorColor: schema.primary,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: schema.outlineVariant,
      labelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: schema.onPrimaryContainer,
      selectedTileColor: schema.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(color: schema.outlineVariant, space: 1),
    expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
    badgeTheme: BadgeThemeData(backgroundColor: schema.primary, textColor: schema.onPrimary),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: schema.surface,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: schema.surface,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

/// L'iniziale dell'atleta in un cerchio: piena quando l'atleta è scelto o ha
/// qualcosa da leggere.
class InizialeAtleta extends StatelessWidget {
  const InizialeAtleta(this.nome, {super.key, this.piena = false, this.diametro = 40});

  final String nome;
  final bool piena;
  final double diametro;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Container(
      width: diametro,
      height: diametro,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: piena ? schema.primary : schema.surfaceContainer,
      ),
      child: Text(
        nome.isEmpty ? '?' : nome.characters.first.toUpperCase(),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: diametro * 0.4,
          fontWeight: FontWeight.w700,
          color: piena ? schema.onPrimary : schema.onSurface,
        ),
      ),
    );
  }
}

/// Il contatore di cose da leggere, a destra di una riga.
class Contatore extends StatelessWidget {
  const Contatore(this.numero, {super.key});

  final int numero;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: schema.primary, borderRadius: BorderRadius.circular(11)),
      // Center con widthFactor: largo quanto il numero, non quanto la riga.
      child: Center(
        widthFactor: 1,
        child: Text(
          '$numero',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: schema.onPrimary),
        ),
      ),
    );
  }
}

/// Una fascia arancio con un avviso e, se serve, un bottone.
class FasciaAvviso extends StatelessWidget {
  const FasciaAvviso({super.key, required this.icona, required this.testo, this.azione});

  final IconData icona;
  final String testo;
  final Widget? azione;

  @override
  Widget build(BuildContext context) {
    final colori = ColoriCoach.of(context);
    return Material(
      color: colori.attesaContenitore,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          children: [
            Icon(icona, color: colori.attesa),
            const SizedBox(width: 12),
            Expanded(
              child: Text(testo, style: TextStyle(color: colori.suAttesaContenitore)),
            ),
            if (azione case final azione?) ...[const SizedBox(width: 12), azione],
          ],
        ),
      ),
    );
  }
}
