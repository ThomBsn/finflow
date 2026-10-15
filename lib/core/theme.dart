import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _seed = Color(0xFF0F766E);

/// Material 3 : DM Sans pour les titres, Inter pour le texte courant.
ThemeData buildTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
  );
  final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);
  final body = GoogleFonts.interTextTheme(base.textTheme);
  final display = GoogleFonts.dmSansTextTheme(base.textTheme);

  return base.copyWith(
    textTheme: body.copyWith(
      displayLarge: display.displayLarge,
      displayMedium: display.displayMedium,
      displaySmall: display.displaySmall,
      headlineLarge: display.headlineLarge,
      headlineMedium: display.headlineMedium,
      headlineSmall: display.headlineSmall,
      titleLarge: display.titleLarge,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}
