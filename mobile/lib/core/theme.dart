import 'package:flutter/material.dart';

import 'constants.dart';

/// Bundled font family (see `fonts:` in pubspec.yaml).
const String appFontFamily = 'Poppins';

/// Shorthand for re-weighting (and optionally re-colouring) a theme text style.
extension TextStyleWeight on TextStyle? {
  TextStyle weight(FontWeight weight, {Color? color}) =>
      (this ?? const TextStyle()).copyWith(fontWeight: weight, color: color);
}

/// App-wide theme: deep blue + amber on light grey, Poppins.
ThemeData buildAppTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    surface: Colors.white,
  );
  final ThemeData base = ThemeData(
    colorScheme: scheme,
    fontFamily: appFontFamily,
    scaffoldBackgroundColor: AppColors.background,
  );
  final BorderRadius radius = BorderRadius.circular(12);

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: radius),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.secondary.withValues(alpha: 0.15),
      side: BorderSide.none,
    ),
  );
}
