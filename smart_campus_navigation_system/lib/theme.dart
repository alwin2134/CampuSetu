import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Brand Palette (Galgotias University) ──────────────────────────────
  static const Color primary = Color(0xFFB0322C);      // Deep Red
  static const Color primaryLight = Color(0xFFFDECEB); // Light Red Tint
  static const Color primaryDark = Color(0xFF8B2520);  // Dark Red
  static const Color accent = Color(0xFF3DAEE9);       // Ocean Blue (Route line)
  static const Color success = Color(0xFF10B981);      // Emerald 500
  static const Color warning = Color(0xFFF5A623);      // Sunset Orange
  static const Color danger = Color(0xFFEF4444);       // Red 500
  static const Color yellowAccent = Color(0xFFFFD24D); // Warm Yellow

  // ── Neutral Palette ───────────────────────────────────────────────────────
  static const Color ink900 = Color(0xFF0F172A);
  static const Color ink700 = Color(0xFF334155);
  static const Color ink500 = Color(0xFF64748B);
  static const Color ink300 = Color(0xFFCBD5E1);
  static const Color ink400 = Color(0xFF94A3B8);
  static const Color ink100 = Color(0xFFF8FAFC); // Slightly brighter for Maps feel
  static const Color white = Colors.white;

  // ── Category Colors ───────────────────────────────────────────────────────
  static const Color eventColor = Color(0xFFF5A623); // Sunset Orange
  static const Color buildingColor = Color(0xFF3DAEE9); // Ocean Blue
  static const Color campusColor = Color(0xFFB0322C); // Deep Red

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFB0322C), Color(0xFFD3453E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient eventGradient = LinearGradient(
    colors: [Color(0xFFF5A623), Color(0xFFFFD24D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient buildingGradient = LinearGradient(
    colors: [Color(0xFF3DAEE9), Color(0xFF5ABCF2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Shadows (Google Maps Style: Soft, diffused) ───────────────────────────
  static List<BoxShadow> get shadowSm => [
    BoxShadow(color: ink900.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
  ];
  static List<BoxShadow> get shadowMd => [
    BoxShadow(color: ink900.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 4)),
  ];
  static List<BoxShadow> get shadowLg => [
    BoxShadow(color: ink900.withValues(alpha: 0.12), blurRadius: 32, offset: const Offset(0, 10)),
  ];
  static List<BoxShadow> get shadowPrimary => [
    BoxShadow(color: primary.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 6)),
  ];

  // ── Theme ─────────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final base = GoogleFonts.interTextTheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: ink100,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
        surface: white,
        error: danger,
        onPrimary: white,
        onSecondary: white,
        onSurface: ink900,
      ),
      textTheme: base.copyWith(
        displayLarge: base.displayLarge?.copyWith(color: ink900, fontWeight: FontWeight.w800, letterSpacing: -1.5),
        displayMedium: base.displayMedium?.copyWith(color: ink900, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        displaySmall: base.displaySmall?.copyWith(color: ink900, fontWeight: FontWeight.w700),
        headlineLarge: base.headlineLarge?.copyWith(color: ink900, fontWeight: FontWeight.w700),
        headlineMedium: base.headlineMedium?.copyWith(color: ink900, fontWeight: FontWeight.w600),
        headlineSmall: base.headlineSmall?.copyWith(color: ink900, fontWeight: FontWeight.w600),
        titleLarge: base.titleLarge?.copyWith(color: ink900, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        titleMedium: base.titleMedium?.copyWith(color: ink700, fontWeight: FontWeight.w500),
        bodyLarge: base.bodyLarge?.copyWith(color: ink700, height: 1.6),
        bodyMedium: base.bodyMedium?.copyWith(color: ink500, height: 1.5),
        bodySmall: base.bodySmall?.copyWith(color: ink500),
        labelLarge: base.labelLarge?.copyWith(color: ink900, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: white,
        foregroundColor: ink900,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: ink700),
        titleTextStyle: TextStyle(
          color: ink900,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, fontFamily: 'Inter'),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: ink300, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, fontFamily: 'Inter'),
        ),
      ),
      cardTheme: CardThemeData(
        color: white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: ink300.withValues(alpha: 0.3)),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ink100,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        hintStyle: const TextStyle(color: ink400, fontFamily: 'Inter'),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: white,
        foregroundColor: primary,
        elevation: 4,
        shape: StadiumBorder(),
      ),
      dividerTheme: DividerThemeData(
        color: ink300.withValues(alpha: 0.4),
        thickness: 1,
        space: 0,
      ),
    );
  }
}
