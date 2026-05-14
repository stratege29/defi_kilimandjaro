import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typographie officielle Kilimandjaro — refonte 2026.
///
/// Triade :
/// - **Fraunces** (variable, axes `wght/SOFT/WONK`) — display didone moderne
///   pour les écrans d'accomplissement, mots-réponses, altitudes. Remplace
///   Playfair Display (datée DTP-2015).
/// - **Barlow Condensed** (variable, axe `wght` 100-900) — grotesque
///   condensée pour titres, boutons, chips, navigation. Remplace Bebas Neue
///   (devenue le "Comic Sans du sport mobile 2018-2022").
/// - **Crimson Pro** (variable, axe `wght`) — serif littéraire à grande
///   x-height pour le corps de texte : proverbes, devinettes, explications.
///   Conservée (la meilleure des trois originales).
///
/// ## Deux APIs cohabitent
///
/// 1. **Tokens 2026** (recommandé) — `display{Xl,Lg,Md,Sm}`,
///    `heading{Xl,Lg,Md,Sm}`, `body{Lg,Md,Sm}`, `label{Sm,Xs}`.
///    Tailles, poids, line-height et couleur sémantiques pré-réglés.
///    Override via `.copyWith(color: ...)` si besoin.
///
/// 2. **Helpers legacy** — `bebas()`, `playfair()`, `crimson()`,
///    `taglineItalic()`. Conservés pour compat ; **reroutés** vers les
///    nouvelles fontes (Barlow/Fraunces) pour aligner globalement le
///    visuel sans refacto par site.
abstract final class AppTypography {
  // ============================================================
  // TOKENS 2026 — type scale tokenisée (13 styles)
  //
  // Usage : `AppTypography.headingMd` puis `.copyWith(color: ...)` si
  // une couleur sémantique différente est nécessaire.
  // ============================================================

  // ---- DISPLAY (Fraunces) — écrans d'accomplissement, moments solennels.

  /// Logo splash uniquement — 64pt Fraunces w900.
  static TextStyle get displayXl => GoogleFonts.fraunces(
    fontSize: 64,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.5,
    height: 1,
    color: AppColors.orJour,
  );

  /// Altitude en gros (MountainList, ConquestView) — 48pt Fraunces w800.
  static TextStyle get displayLg => GoogleFonts.fraunces(
    fontSize: 48,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
    height: 1.05,
    color: AppColors.orJour,
  );

  /// Mot-réponse VictoryView — 40pt Fraunces w700.
  /// Moment éditorial fort : la fonte la plus noble du design system.
  static TextStyle get displayMd => GoogleFonts.fraunces(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.1,
    color: AppColors.orJour,
  );

  /// Nom de montagne ConquestView — 32pt Fraunces w700.
  static TextStyle get displaySm => GoogleFonts.fraunces(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.15,
    color: AppColors.orJour,
  );

  // ---- HEADING (Barlow Condensed) — titres sections, AppBars, CTA.

  /// Titres écrans, sections — 28pt Barlow Cond w700.
  static TextStyle get headingXl => GoogleFonts.barlowCondensed(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    height: 1.2,
    color: AppColors.textePrimaire,
  );

  /// AppBar titles, section headers — 22pt Barlow Cond w700.
  static TextStyle get headingLg => GoogleFonts.barlowCondensed(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 1,
    height: 1.25,
    color: AppColors.textePrimaire,
  );

  /// Boutons primaires, CTA principaux — 18pt Barlow Cond w600.
  static TextStyle get headingMd => GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: 1,
    height: 1.3,
    color: AppColors.textePrimaire,
  );

  /// Boutons secondaires, action buttons — 15pt Barlow Cond w600.
  static TextStyle get headingSm => GoogleFonts.barlowCondensed(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.35,
    color: AppColors.textePrimaire,
  );

  // ---- BODY (Crimson Pro) — lectures longues, proverbes.

  /// Proverbes, citations principales — 18pt Crimson w400, italic.
  static TextStyle get bodyLg => GoogleFonts.crimsonPro(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: AppColors.textePrimaire,
  );

  /// Devinettes (RiddleCard), corps explicatif — 15pt Crimson w400.
  static TextStyle get bodyMd => GoogleFonts.crimsonPro(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: AppColors.textePrimaire,
  );

  /// Descriptions, captions, métadonnées — 13pt Crimson w400.
  static TextStyle get bodySm => GoogleFonts.crimsonPro(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.texteSecondaire,
  );

  // ---- LABEL (Barlow Condensed) — navigation, chips, tags.

  /// Navigation labels, chips principaux — 12pt Barlow Cond w500.
  static TextStyle get labelSm => GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    height: 1.4,
    color: AppColors.textePrimaire,
  );

  /// Graduations, badges miniatures — 10pt Barlow Cond w500.
  static TextStyle get labelXs => GoogleFonts.barlowCondensed(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    height: 1.4,
    color: AppColors.texteSecondaire,
  );

  // ============================================================
  // HELPERS LEGACY — reroutés vers les nouvelles fontes.
  //
  // Le nom historique (`bebas`, `playfair`) est conservé pour ne pas
  // casser les call sites existants ; le RENDU est désormais aligné
  // avec le design system 2026. Migrer vers les tokens ci-dessus au
  // fil des refactos de composants.
  // ============================================================

  /// **Reroute vers Barlow Condensed.** Le nom `bebas` est conservé
  /// pour compat ; les call sites existants rendent désormais en
  /// Barlow w600 (au lieu de Bebas Neue).
  static TextStyle bebas({
    double size = 16,
    Color color = AppColors.ivoire,
    double letterSpacing = 1,
    FontWeight weight = FontWeight.w600,
  }) => GoogleFonts.barlowCondensed(
    fontSize: size,
    color: color,
    letterSpacing: letterSpacing,
    fontWeight: weight,
  );

  /// **Reroute vers Fraunces.** Le nom `playfair` est conservé pour
  /// compat ; rendu désormais en Fraunces (didone optique variable).
  static TextStyle playfair({
    double size = 28,
    Color color = AppColors.orSoleil,
    FontWeight weight = FontWeight.w700,
    FontStyle? style,
  }) => GoogleFonts.fraunces(
    fontSize: size,
    color: color,
    fontWeight: weight,
    fontStyle: style,
  );

  /// Crimson Pro variable (inchangé — la meilleure des trois originales).
  static TextStyle crimson({
    double size = 16,
    Color color = AppColors.ivoire,
    FontStyle? style,
  }) => GoogleFonts.crimsonPro(fontSize: size, color: color, fontStyle: style);

  /// Tagline italique bois clair (splash screen).
  static TextStyle taglineItalic({double size = 14}) => GoogleFonts.crimsonPro(
    fontSize: size,
    color: AppColors.tagline,
    fontStyle: FontStyle.italic,
  );

  /// Logo "K" géant du splash — désormais Fraunces w900.
  static TextStyle logoK = GoogleFonts.fraunces(
    fontSize: 96,
    color: AppColors.orJour,
    fontWeight: FontWeight.w900,
    height: 1,
  );

  /// Titre KILIMANDJARO sous le logo — désormais Barlow Condensed w700.
  static TextStyle logoTitle = GoogleFonts.barlowCondensed(
    fontSize: 18,
    color: AppColors.textePrimaire,
    letterSpacing: 4,
    fontWeight: FontWeight.w700,
  );
}
