import 'package:flutter/material.dart';

/// I colori dell'app oltre a quelli dello schema di Material: lo stato «in
/// attesa» in arancio, distinto dall'errore anche per luminosità.
abstract final class ColoriAtleta {
  static const primario = Color(0xFF0A6B60);
  static const contenitore = Color(0xFFD3EEE9);
  static const suContenitore = Color(0xFF053D37);
  static const sfondo = Color(0xFFF3F6F5);
  static const superficie = Colors.white;
  static const superficieTenue = Color(0xFFE9EFED);
  static const bordo = Color(0xFFDCE4E2);
  static const divisore = Color(0xFFEEF2F1);
  static const testo = Color(0xFF10201D);
  static const testoSecondario = Color(0xFF4A5B57);
  static const attesa = Color(0xFF8A4300);
  static const attesaContenitore = Color(0xFFFDEBD8);
  static const errore = Color(0xFFA3231B);
  static const erroreContenitore = Color(0xFFFBE3E1);

  /// Una serie registrata: la riga si tinge.
  static const serieFatta = Color(0xFFE6F4F1);
}

/// Il tema dell'app: il teal di sempre, superfici chiare con bordo invece
/// delle ombre, cifre tabellari per kg, kcal e tempi.
ThemeData temaAtleta() {
  final schema = ColorScheme.fromSeed(seedColor: Colors.teal).copyWith(
    primary: ColoriAtleta.primario,
    onPrimary: Colors.white,
    primaryContainer: ColoriAtleta.contenitore,
    onPrimaryContainer: ColoriAtleta.suContenitore,
    secondaryContainer: ColoriAtleta.contenitore,
    onSecondaryContainer: ColoriAtleta.suContenitore,
    surface: ColoriAtleta.superficie,
    onSurface: ColoriAtleta.testo,
    onSurfaceVariant: ColoriAtleta.testoSecondario,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: ColoriAtleta.sfondo,
    surfaceContainer: ColoriAtleta.superficieTenue,
    surfaceContainerHighest: ColoriAtleta.superficieTenue,
    outline: const Color(0xFFC9D4D1),
    outlineVariant: ColoriAtleta.bordo,
    error: ColoriAtleta.errore,
    errorContainer: ColoriAtleta.erroreContenitore,
  );
  final base = ThemeData(colorScheme: schema);
  const tabellari = [FontFeature.tabularFigures()];
  TextStyle? cifre(TextStyle? stile, {FontWeight? peso}) =>
      stile?.copyWith(fontFeatures: tabellari, fontWeight: peso);
  final testi = base.textTheme;
  final textTheme = testi.copyWith(
    displaySmall: cifre(testi.displaySmall, peso: FontWeight.w700),
    headlineMedium: cifre(testi.headlineMedium, peso: FontWeight.w700),
    headlineSmall: cifre(testi.headlineSmall, peso: FontWeight.w700),
    titleLarge: cifre(testi.titleLarge, peso: FontWeight.w700),
    titleMedium: cifre(testi.titleMedium, peso: FontWeight.w600),
    titleSmall: cifre(testi.titleSmall, peso: FontWeight.w600),
    bodyLarge: cifre(testi.bodyLarge),
    bodyMedium: cifre(testi.bodyMedium),
    bodySmall: cifre(testi.bodySmall)?.copyWith(color: ColoriAtleta.testoSecondario),
    labelLarge: cifre(testi.labelLarge, peso: FontWeight.w600),
    labelMedium: cifre(testi.labelMedium, peso: FontWeight.w600),
    labelSmall: cifre(testi.labelSmall, peso: FontWeight.w600),
  );
  final arrotondato = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return base.copyWith(
    scaffoldBackgroundColor: ColoriAtleta.sfondo,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: ColoriAtleta.sfondo,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      foregroundColor: ColoriAtleta.testo,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: ColoriAtleta.testo,
        fontSize: 22,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: ColoriAtleta.superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: ColoriAtleta.bordo),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 52), shape: arrotondato),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        side: const BorderSide(color: ColoriAtleta.bordo),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: ColoriAtleta.primario,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ColoriAtleta.superficie,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFC9D4D1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ColoriAtleta.primario, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ColoriAtleta.superficie,
      surfaceTintColor: Colors.transparent,
      indicatorColor: ColoriAtleta.contenitore,
      elevation: 0,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (stati) => textTheme.labelMedium?.copyWith(
          color: stati.contains(WidgetState.selected)
              ? ColoriAtleta.suContenitore
              : ColoriAtleta.testoSecondario,
        ),
      ),
    ),
    badgeTheme: const BadgeThemeData(backgroundColor: ColoriAtleta.errore),
    dividerTheme: const DividerThemeData(color: ColoriAtleta.divisore, space: 1),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ColoriAtleta.superficie,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

/// Il titolo in maiuscoletto sopra un gruppo di card.
class TitoloSezione extends StatelessWidget {
  const TitoloSezione(this.testo, {super.key});

  final String testo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
    child: Text(
      testo.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: ColoriAtleta.testoSecondario,
        letterSpacing: 0.6,
      ),
    ),
  );
}

/// Un'icona in un cerchio colorato, per lo stato di una riga.
class IconaInCerchio extends StatelessWidget {
  const IconaInCerchio(
    this.icona, {
    super.key,
    required this.colore,
    required this.sfondo,
    this.diametro = 36,
  });

  final IconData icona;
  final Color colore;
  final Color sfondo;
  final double diametro;

  @override
  Widget build(BuildContext context) => Container(
    width: diametro,
    height: diametro,
    decoration: BoxDecoration(color: sfondo, shape: BoxShape.circle),
    child: Icon(icona, size: diametro / 2, color: colore),
  );
}

/// La riga in fondo a Cibo e Peso: condividere o no con il coach.
class RigaCondivisione extends StatelessWidget {
  const RigaCondivisione({
    super.key,
    required this.titolo,
    required this.valore,
    required this.cambia,
    this.nonSupportata,
  });

  final String titolo;
  final bool valore;
  final ValueChanged<bool> cambia;

  /// Il motivo, se il programma del coach è troppo vecchio per riceverli.
  final String? nonSupportata;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    // Material e non un Container colorato: l'interruttore disegna lì il suo
    // effetto al tocco.
    child: Material(
      color: ColoriAtleta.superficieTenue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        dense: nonSupportata == null,
        contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        title: Text(titolo, style: Theme.of(context).textTheme.titleSmall),
        subtitle: nonSupportata == null ? null : Text(nonSupportata!),
        value: valore,
        onChanged: cambia,
      ),
    ),
  );
}
