import 'package:flutter/material.dart';

/// Palette officielle Kilimandjaro (cf. maquette p.2).
///
/// Toute couleur affichée dans l'app DOIT venir d'ici — jamais de hex en dur.
abstract final class AppColors {
  /// Vert forêt — fond principal, headers.
  static const Color vertForet = Color(0xFF1A3A20);

  /// Vert clair — succès, niveaux complétés, CTA.
  static const Color vertClair = Color(0xFF4A9E58);

  /// Or soleil — titres, highlights, monnaie (Coins de Sagesse).
  static const Color orSoleil = Color(0xFFF0C040);

  /// Or chaud — accents secondaires, dégradés.
  static const Color orChaud = Color(0xFFE8A020);

  /// Bois — tuiles lettres, bordures, cartes.
  static const Color bois = Color(0xFFC8843A);

  /// Bois foncé — ombres, contours, texte bois.
  static const Color boisFonce = Color(0xFF7C4E1E);

  /// Ivoire — texte principal sur fond sombre.
  static const Color ivoire = Color(0xFFF5EAD0);

  /// Rouge — erreurs, timer danger, écran d'échec.
  static const Color rouge = Color(0xFFC0392B);

  /// Tagline color (variante chaude).
  static const Color tagline = Color(0xFFE8B06A);

  // --- Opacités fréquentes (cf. maquette) ---
  static Color cartesDebloquees = bois.withValues(alpha: 0.22);
  static Color cartesVerrouillees = bois.withValues(alpha: 0.12);
  static Color stats = bois.withValues(alpha: 0.28);
  static Color cheminDore = orSoleil.withValues(alpha: 0.70);
}
