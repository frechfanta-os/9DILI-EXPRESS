import 'package:flutter/material.dart';

/// Modes de navigation et d'interface de l'application 9DILI EXPRESS.
enum AppMode {
  client,
  shopper,
}

/// Thème visuel officiel 9DILI EXPRESS — Stitch UI/UX V2.
/// - Mode Client  : Vert Émeraude (#10B981) — Focus catalogue, panier, courses
/// - Mode Shopper : Orange Vif (#FF6D00)    — Focus radar, commandes, livraisons
/// - Validation / Succès : Vert (#10B981)
/// - Surfaces Secondaires : Violet clair (#EDE9FE / #8B5CF6)
/// - Fond : Blanc cassé moderne (#F8FAFC)
/// - Cartes arrondies (r=18)
class AppTheme {
  // Couleurs principales par mode
  static const Color clientGreen = Color(0xFF10B981); // Vert officiel Mode Client
  static const Color shopperOrange = Color(0xFFFF6D00); // Orange officiel Mode Shopper

  // Rétrocompatibilité
  static const Color primaryOrange = shopperOrange;
  static const Color accentGreen = clientGreen;

  static const Color violetSurface = Color(0xFFEDE9FE);
  static const Color violetAccent = Color(0xFF8B5CF6);
  static const Color secondaryNavy = Color(0xFF1E293B);
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color errorRed = Color(0xFFEF4444);
  static const Color warningOrange = Color(0xFFF59E0B);

  /// Renvoie la couleur principale correspondant au mode actif
  static Color primaryFor(AppMode mode) =>
      mode == AppMode.shopper ? shopperOrange : clientGreen;

  /// Renvoie la teinte de fond conteneur pour le mode actif
  static Color surfaceTintFor(AppMode mode) =>
      primaryFor(mode).withValues(alpha: 0.12);

  /// Génère le thème complet de l'application selon le mode actif.
  static ThemeData themeFor(AppMode mode) {
    final primary = primaryFor(mode);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: violetAccent,
        surface: surfaceWhite,
        error: errorRed,
      ),
      scaffoldBackgroundColor: backgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceWhite,
        foregroundColor: textDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceWhite,
        indicatorColor: primary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: primary,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: primary);
          }
          return const IconThemeData(color: textMuted);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceWhite,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: errorRed),
        ),
        labelStyle: const TextStyle(color: textMuted, fontSize: 14),
        hintStyle: const TextStyle(color: textMuted, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textDark,
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFF1F5F9), width: 1.5),
        ),
      ),
    );
  }

  static ThemeData get lightTheme => themeFor(AppMode.client);
}
