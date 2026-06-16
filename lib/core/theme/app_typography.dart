import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Typographie officielle Kilimandjaro — **refonte 2026 (2 familles)**.
///
/// Duo :
/// - **Fraunces** (variable, axes `wght/SOFT/opsz`) — didone moderne à l'âme
///   éditoriale. Réservée aux moments forts : logo, mots-réponses, altitudes,
///   proverbes. C'est la signature culturelle.
/// - **Hanken Grotesk** (variable, `wght` 100-900) — grotesque humaniste
///   propre et premium pour TOUTE l'UI : titres, boutons, labels, navigation,
///   corps. Remplace Barlow Condensed (daté "mobile game") ET Crimson Pro.
///
/// Le passage condensé → grotesk humaniste est le levier n°1 du "ça fait pro".
///
/// ## Deux APIs cohabitent
/// 1. **Tokens 2026** (recommandé) — `display/heading/body/label`.
/// 2. **Helpers legacy** (`bebas/playfair/crimson/...`) — noms conservés pour
///    compat, **reroutés** vers Hanken/Fraunces.
abstract final class AppTypography {
  /// Construit un [TextStyle] sur une police **bundlée** (`Fraunces` /
  /// `Hanken Grotesk`, déclarées dans pubspec). Remplace `google_fonts` :
  /// plus aucun fetch réseau au runtime. Les polices étant variables,
  /// Flutter applique [fontWeight] sur l'axe `wght`.
  static TextStyle _styled(
    String family, {
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    Color? color,
    FontStyle? fontStyle,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
      fontStyle: fontStyle,
    );
  }

  // ============================================================
  // DISPLAY (Fraunces) — accomplissements, moments solennels.
  // ============================================================

  /// Logo splash — 64pt Fraunces w900.
  static TextStyle get displayXl => _styled('Fraunces',
    fontSize: 64,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.5,
    height: 1,
    color: AppColors.orJour,
  );

  /// Altitude en gros (MountainList, ConquestView) — 48pt Fraunces w800.
  static TextStyle get displayLg => _styled('Fraunces',
    fontSize: 48,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
    height: 1.05,
    color: AppColors.orJour,
  );

  /// Mot-réponse VictoryView — 40pt Fraunces w700.
  static TextStyle get displayMd => _styled('Fraunces',
    fontSize: 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.1,
    color: AppColors.orJour,
  );

  /// Nom de montagne ConquestView — 32pt Fraunces w700.
  static TextStyle get displaySm => _styled('Fraunces',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.15,
    color: AppColors.orJour,
  );

  // ============================================================
  // HEADING (Hanken Grotesk) — titres sections, AppBars, CTA.
  // Letter-spacing quasi nul : un grotesk n'a pas besoin d'aération.
  // ============================================================

  /// Titres écrans, sections — 28pt Hanken w800.
  static TextStyle get headingXl => _styled('Hanken Grotesk',
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    height: 1.15,
    color: AppColors.textePrimaire,
  );

  /// AppBar titles, section headers — 22pt Hanken w700.
  static TextStyle get headingLg => _styled('Hanken Grotesk',
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.2,
    color: AppColors.textePrimaire,
  );

  /// Boutons primaires, CTA — 17pt Hanken w700.
  static TextStyle get headingMd => _styled('Hanken Grotesk',
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    height: 1.25,
    color: AppColors.textePrimaire,
  );

  /// Boutons secondaires, actions — 15pt Hanken w600.
  static TextStyle get headingSm => _styled('Hanken Grotesk',
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    height: 1.3,
    color: AppColors.textePrimaire,
  );

  // ============================================================
  // BODY — proverbes en Fraunces (chaleur), reste en Hanken (lisibilité).
  // ============================================================

  /// Proverbes, citations — 18pt Fraunces italic w400. Le moment serif.
  static TextStyle get bodyLg => _styled('Fraunces',
    fontSize: 18,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    height: 1.55,
    color: AppColors.textePrimaire,
  );

  /// Devinettes, corps explicatif — 15pt Hanken w400.
  static TextStyle get bodyMd => _styled('Hanken Grotesk',
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textePrimaire,
  );

  /// Descriptions, captions, métadonnées — 13pt Hanken w400.
  static TextStyle get bodySm => _styled('Hanken Grotesk',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.texteSecondaire,
  );

  // ============================================================
  // LABEL (Hanken Grotesk) — navigation, chips, tags.
  // ============================================================

  /// Navigation labels, chips — 12pt Hanken w600.
  static TextStyle get labelSm => _styled('Hanken Grotesk',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    height: 1.35,
    color: AppColors.textePrimaire,
  );

  /// Graduations, badges miniatures — 10.5pt Hanken w600.
  static TextStyle get labelXs => _styled('Hanken Grotesk',
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    height: 1.35,
    color: AppColors.texteSecondaire,
  );

  // ============================================================
  // HELPERS LEGACY — reroutés vers les nouvelles fontes.
  // ============================================================

  /// **Reroute vers Hanken Grotesk.** Nom `bebas` conservé pour compat ;
  /// rendu désormais en grotesk humaniste w700 (au lieu de Barlow Condensed).
  /// Le `letterSpacing` historique est neutralisé (un grotesk n'en a pas
  /// besoin) pour éviter le tracking exagéré hérité du condensé.
  static TextStyle bebas({
    double size = 16,
    Color color = AppColors.textePrimaire,
    double letterSpacing = 1,
    FontWeight weight = FontWeight.w700,
  }) => _styled('Hanken Grotesk',
    fontSize: size,
    color: color,
    letterSpacing: (letterSpacing - 1).clamp(-0.5, 0.5),
    fontWeight: weight,
  );

  /// **Reroute vers Fraunces.** Nom `playfair` conservé pour compat.
  static TextStyle playfair({
    double size = 28,
    Color color = AppColors.orJour,
    FontWeight weight = FontWeight.w700,
    FontStyle? style,
  }) => _styled('Fraunces',
    fontSize: size,
    color: color,
    fontWeight: weight,
    fontStyle: style,
  );

  /// **Reroute vers Fraunces.** Nom `crimson` conservé pour compat : tout ce
  /// qui était serif littéraire (proverbes, citations, libellés italiques)
  /// reste serif, en Fraunces (optical text). L'UI neuve utilise [bodyMd].
  static TextStyle crimson({
    double size = 16,
    Color color = AppColors.textePrimaire,
    FontStyle? style,
  }) => _styled('Fraunces',fontSize: size, color: color, fontStyle: style);

  /// Tagline italique (splash) — Fraunces italic crème chaude.
  static TextStyle taglineItalic({double size = 14}) => _styled('Fraunces',
    fontSize: size,
    color: AppColors.texteSecondaire,
    fontStyle: FontStyle.italic,
  );

  /// Logo "K" géant du splash — Fraunces w900.
  static TextStyle logoK = _styled('Fraunces',
    fontSize: 96,
    color: AppColors.orJour,
    fontWeight: FontWeight.w900,
    height: 1,
  );

  /// Titre KILIMANDJARO sous le logo — Hanken Grotesk w700, tracking large.
  static TextStyle logoTitle = _styled('Hanken Grotesk',
    fontSize: 18,
    color: AppColors.textePrimaire,
    letterSpacing: 4,
    fontWeight: FontWeight.w700,
  );
}
