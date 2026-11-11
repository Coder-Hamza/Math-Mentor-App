import 'package:flutter/material.dart';

/// Bundled font family (see `fonts:` in pubspec.yaml).
const String appFontFamily = 'Poppins';

/// Shorthand for re-weighting (and optionally re-colouring) a theme text style.
extension TextStyleWeight on TextStyle? {
  TextStyle weight(FontWeight weight, {Color? color}) =>
      (this ?? const TextStyle()).copyWith(fontWeight: weight, color: color);
}

/// Every colour of the glassmorphism design, for one brightness.
///
/// Lives in [ThemeData.extensions] so that switching theme animates (lerps) every
/// glass colour together with the Material colours. Read it with `context.palette`.
@immutable
class GlassPalette extends ThemeExtension<GlassPalette> {
  const GlassPalette({
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.glass,
    required this.glassBorder,
    required this.accent,
    required this.secondary,
    required this.success,
    required this.error,
    required this.textPrimary,
    required this.textSecondary,
    required this.gradientEnd,
    required this.surface,
    required this.shadow,
  });

  /// Default theme: deep blue-black with electric blue.
  static const GlassPalette dark = GlassPalette(
    backgroundTop: Color(0xFF0A0E21),
    backgroundBottom: Color(0xFF1A1F3A),
    glass: Color(0x14FFFFFF), // white 8%
    glassBorder: Color(0x26FFFFFF), // white 15%
    accent: Color(0xFF4FC3F7), // electric blue
    secondary: Color(0xFFFFB74D), // amber
    success: Color(0xFF69F0AE),
    error: Color(0xFFFF5252),
    textPrimary: Colors.white,
    textSecondary: Color(0xB3FFFFFF), // white 70%
    gradientEnd: Color(0xFF7C4DFF), // purple
    surface: Color(0xFF1A1F3A),
    shadow: Color(0x66000000),
  );

  static const GlassPalette light = GlassPalette(
    backgroundTop: Color(0xFFF0F4FF),
    backgroundBottom: Color(0xFFE8F0FE),
    glass: Color(0x99FFFFFF), // white 60%
    glassBorder: Color(0xCCFFFFFF), // white 80%
    accent: Color(0xFF1565C0), // deep blue
    secondary: Color(0xFFF57C00), // amber
    success: Color(0xFF2E7D32),
    error: Color(0xFFC62828),
    textPrimary: Color(0xFF1A1A2E),
    textSecondary: Color(0xFF4A4A6A),
    gradientEnd: Color(0xFF6A1B9A), // purple
    surface: Color(0xFFF7F9FF),
    shadow: Color(0x1F1A1A2E),
  );

  final Color backgroundTop;
  final Color backgroundBottom;
  final Color glass;
  final Color glassBorder;
  final Color accent;
  final Color secondary;
  final Color success;
  final Color error;
  final Color textPrimary;
  final Color textSecondary;

  /// Purple end of the accent -> purple button / heading gradient.
  final Color gradientEnd;

  /// Opaque fallback surface (dialogs, menus, snack bars).
  final Color surface;
  final Color shadow;

  /// Electric blue -> purple: buttons, badges, gradient headings.
  LinearGradient get accentGradient => LinearGradient(
    colors: <Color>[accent, gradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  LinearGradient get backgroundGradient => LinearGradient(
    colors: <Color>[backgroundTop, backgroundBottom],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  @override
  GlassPalette copyWith({Color? accent, Color? glass}) => GlassPalette(
    backgroundTop: backgroundTop,
    backgroundBottom: backgroundBottom,
    glass: glass ?? this.glass,
    glassBorder: glassBorder,
    accent: accent ?? this.accent,
    secondary: secondary,
    success: success,
    error: error,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    gradientEnd: gradientEnd,
    surface: surface,
    shadow: shadow,
  );

  @override
  GlassPalette lerp(covariant GlassPalette? other, double t) {
    if (other == null) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return GlassPalette(
      backgroundTop: mix(backgroundTop, other.backgroundTop),
      backgroundBottom: mix(backgroundBottom, other.backgroundBottom),
      glass: mix(glass, other.glass),
      glassBorder: mix(glassBorder, other.glassBorder),
      accent: mix(accent, other.accent),
      secondary: mix(secondary, other.secondary),
      success: mix(success, other.success),
      error: mix(error, other.error),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      gradientEnd: mix(gradientEnd, other.gradientEnd),
      surface: mix(surface, other.surface),
      shadow: mix(shadow, other.shadow),
    );
  }
}

extension PaletteContext on BuildContext {
  GlassPalette get palette =>
      Theme.of(this).extension<GlassPalette>() ?? GlassPalette.dark;

  /// True when the OS asks for less motion. Also used as the low-end fallback:
  /// no blur, no ambient animation.
  bool get reduceEffects => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}

/// Fade between screens (300 ms, the [MaterialPageRoute] default duration).
class FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  );
}

/// How long the dark <-> light switch takes.
const Duration themeSwitchDuration = Duration(milliseconds: 400);

ThemeData buildDarkTheme() => buildAppTheme(GlassPalette.dark, Brightness.dark);

ThemeData buildLightTheme() =>
    buildAppTheme(GlassPalette.light, Brightness.light);

/// Material theme built from a [GlassPalette]: transparent scaffolds and app bars
/// (the [GradientBackground] shows through), glass inputs, Poppins type scale.
ThemeData buildAppTheme(GlassPalette p, Brightness brightness) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: brightness,
    primary: p.accent,
    onPrimary: brightness == Brightness.dark ? p.backgroundTop : Colors.white,
    secondary: p.secondary,
    error: p.error,
    surface: p.surface,
    onSurface: p.textPrimary,
  );
  final ThemeData base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: appFontFamily,
  );
  final BorderRadius radius = BorderRadius.circular(16);
  final TextTheme text = base.textTheme
      .copyWith(
        // Heading: Bold 24, tight tracking.
        headlineSmall: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        // Subheading: SemiBold 18.
        titleLarge: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        // Body: Regular 14, airy line height.
        bodyMedium: const TextStyle(fontSize: 14, height: 1.5),
        // Caption: Regular 12 at 70%.
        bodySmall: TextStyle(fontSize: 12, color: p.textSecondary),
      )
      .apply(
        fontFamily: appFontFamily,
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      );

  return base.copyWith(
    textTheme: text.copyWith(
      bodySmall: text.bodySmall?.copyWith(color: p.textSecondary),
    ),
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: p.surface,
    extensions: <ThemeExtension<dynamic>>[p],
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadePageTransitionsBuilder(),
        TargetPlatform.iOS: FadePageTransitionsBuilder(),
        TargetPlatform.windows: FadePageTransitionsBuilder(),
        TargetPlatform.linux: FadePageTransitionsBuilder(),
        TargetPlatform.macOS: FadePageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadePageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: appFontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: p.textPrimary,
      ),
    ),
    iconTheme: IconThemeData(color: p.textPrimary),
    dividerTheme: DividerThemeData(color: p.glassBorder),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.glass,
      labelStyle: TextStyle(color: p.textSecondary),
      hintStyle: TextStyle(color: p.textSecondary),
      helperStyle: TextStyle(color: p.textSecondary),
      prefixIconColor: p.textSecondary,
      suffixIconColor: p.textSecondary,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: p.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: p.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: p.accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: p.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: p.error, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: p.accent,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.accent,
        side: BorderSide(color: p.glassBorder),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accent),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: p.glass,
      side: BorderSide(color: p.glassBorder),
      labelStyle: TextStyle(color: p.textPrimary, fontFamily: appFontFamily),
      shape: const StadiumBorder(),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: p.glassBorder),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: p.accent,
      collapsedIconColor: p.textSecondary,
      textColor: p.textPrimary,
      collapsedTextColor: p.textPrimary,
      shape: const Border(),
      collapsedShape: const Border(),
    ),
  );
}
