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

  // --- Écran Sommets : atmosphères par biome ---

  /// Savane / plaine (0–500 m) — ocre chaud.
  static const Color savanneOcre = Color(0xFFE8B86A);

  /// Savane sombre — bas du dégradé savanne.
  static const Color savanneFonce = Color(0xFFD4A857);

  /// Brume / roche (2000–4000 m) — gris bleuté.
  static const Color rocheBrume = Color(0xFF5C6770);

  /// Ciel d'altitude (4000 m+) — violet clair.
  static const Color cielHauteur = Color(0xFF7A8AC4);

  /// Blanc neige — sommet enneigé et ciel d'altitude clair.
  static const Color neigeBlanche = Color(0xFFE8E8F5);

  /// Silhouette verrouillée — gris brumeux.
  static const Color silhouetteVerrouillee = Color(0xFF4A5055);

  /// Halo du sommet en cours (pulsation dorée).
  static const Color haloCourant = Color(0xFFF0C040);

  // --- Opacités fréquentes (cf. maquette) ---
  static Color cartesDebloquees = bois.withValues(alpha: 0.22);
  static Color cartesVerrouillees = bois.withValues(alpha: 0.12);
  static Color stats = bois.withValues(alpha: 0.28);
  static Color cheminDore = orSoleil.withValues(alpha: 0.70);
}
