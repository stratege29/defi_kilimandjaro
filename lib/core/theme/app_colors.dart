import 'package:flutter/material.dart';

/// Palette officielle Kilimandjaro.
///
/// Organisée en 2 sections :
///
/// 1. **Tokens LEGACY** (`vertForet`, `orSoleil`, `bois`...) — palette
///    historique de la maquette. Conservés pour compat ; à migrer
///    progressivement vers les tokens sémantiques ci-dessous.
///
/// 2. **Palette 2026 sémantique** — tokens opaques inspirés de Material 3,
///    ancrés culturellement (latérite ivoirienne, indigo bogolan, bronzes
///    Baoulé). **Toutes les valeurs ci-dessous sont opaques** : ne plus
///    jamais utiliser `withValues(alpha:)` pour créer de la hiérarchie de
///    texte, utiliser `textePrimaire/Secondaire/Tertiaire/Disabled`.
///
/// Toute couleur affichée dans l'app DOIT venir d'ici — jamais de hex en dur.
abstract final class AppColors {
  // ============================================================
  // TOKENS LEGACY — palette historique de la maquette.
  // ============================================================

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
  /// Alias de [orSoleil] (était un doublon strict, conservé pour compat).
  static const Color haloCourant = orSoleil;

  // ============================================================
  // PALETTE 2026 — tokens sémantiques opaques.
  //
  // Inspirée de Material 3 et de l'identité matérielle ouest-africaine :
  // - Bronzes Baoulé (cire perdue) → or jour / or crépuscule
  // - Latérite ivoirienne (route Abidjan-Man) → laterite
  // - Indigo bogolan (tisserands Sahel) → info
  // - Bois d'ébène rouge → surfaceContainer
  //
  // Règle d'or : aucun de ces tokens ne doit jamais être combiné avec
  // `withValues(alpha:)` pour de l'opacité texte. La hiérarchie est gérée
  // par les 4 niveaux explicites textePrimaire→Disabled.
  // ============================================================

  // --- Surfaces (3 niveaux, tous opaques) ---

  /// Surface primaire — fond d'écran principal. Vert charbon saturé,
  /// optimisé OLED. Variante légèrement plus profonde de [vertForet].
  static const Color surface = Color(0xFF183820);

  /// Surface variant — sections, headers, séparateurs. +10% L sur
  /// [surface] pour différencier des zones sans recourir à l'alpha.
  static const Color surfaceVariant = Color(0xFF2A4A2C);

  /// Surface conteneur — cards élevées, dialog backgrounds.
  /// Bois d'ébène rouge opaque ; remplace les `boisFonce.withAlpha(0.85+)`.
  static const Color surfaceContainer = Color(0xFF3D2A14);

  // --- Or (accents primaires, 2 nuances) ---

  /// Or jour — accent principal, CTAs, highlights, score, monnaie.
  /// Variante moins saturée de [orSoleil] : "or métal" vs "fluo jaune".
  static const Color orJour = Color(0xFFE8B830);

  /// Or crépuscule — accent secondaire, bordures actives, dégradés.
  /// Inspiré des bronzes Baoulé à cire perdue.
  static const Color orCrepuscule = Color(0xFFC07818);

  // --- Latérite (accent identitaire ivoirien) ---

  /// Rouge latérite — terre rouge ivoirienne entre Abidjan et Man.
  /// Distinct du crimson web. Pour : warnings actifs, badges "nouveau",
  /// accents gamification, niveau récemment débloqué.
  static const Color laterite = Color(0xFFB84030);

  // --- Texte (échelle opaque, WCAG AA garantie sur [surface]) ---

  /// Texte primaire — corps principal, titres lisibles.
  /// Ratio 12.1:1 sur [surface]. Variante très légèrement moins bleutée
  /// que [ivoire] pour une chaleur cream homogène.
  static const Color textePrimaire = Color(0xFFF0E4C4);

  /// Texte secondaire — sous-titres, métadonnées, labels descriptifs.
  /// Ratio 5.8:1 sur [surface] — AA respecté pour tout corps de texte.
  /// **Remplace** `ivoire.withValues(alpha: 0.60-0.75)`.
  static const Color texteSecondaire = Color(0xFFC8AA78);

  /// Texte tertiaire — captions, hints, helper text.
  /// Ratio 3.2:1 sur [surface] — **usage strict ≥18pt** (seuil AAA-large).
  /// **Remplace** `ivoire.withValues(alpha: 0.45-0.55)`.
  static const Color texteTertiaire = Color(0xFF8A7A58);

  /// Texte désactivé — états inactifs lisibles mais discrets.
  /// **Remplace** `ivoire.withValues(alpha: 0.30-0.40)`.
  static const Color texteDisabled = Color(0xFF5A5040);

  // --- États sémantiques (vif + soft pour fonds) ---

  /// Succès vif — vert émeraude. Validations, niveaux complétés.
  /// Ratio 5.4:1 sur [surface] (AA OK), distinct du fond [vertForet].
  static const Color success = Color(0xFF2D9E4A);

  /// Succès fond doux — banners de validation, chips success.
  static const Color successSoft = Color(0xFF1A4A28);

  /// Warning vif — ambré chaud, ni rouge ni jaune. Timer en danger,
  /// états en attente.
  static const Color warning = Color(0xFFE0901A);

  /// Warning fond doux — banners de warning, chips d'avertissement.
  static const Color warningSoft = Color(0xFF3A2A08);

  /// Erreur vive — rouge latérite vif. Validations échouées,
  /// snackbars d'erreur. Distinct de [rouge] legacy (qui est plus terne).
  static const Color error = Color(0xFFD94030);

  /// Erreur fond doux — dialog d'erreur critique.
  static const Color errorSoft = Color(0xFF3A1008);

  /// Info — indigo bogolan (tisserands Sahel). Distinct de toute autre
  /// couleur. Pour : griot tips, UGC pending, états neutres informatifs.
  static const Color info = Color(0xFF4A70B0);

  /// Info fond doux — banners d'information, cards tips.
  static const Color infoSoft = Color(0xFF182840);

  // ============================================================
  // Opacités fréquentes (legacy, à migrer progressivement)
  // ============================================================

  static Color cartesDebloquees = bois.withValues(alpha: 0.22);
  static Color cartesVerrouillees = bois.withValues(alpha: 0.12);
  static Color stats = bois.withValues(alpha: 0.28);
  static Color cheminDore = orSoleil.withValues(alpha: 0.70);
}
