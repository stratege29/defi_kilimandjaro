import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typographies officielles Kilimandjaro (cf. maquette p.2).
///
/// - **Bebas Neue** — titres, scores, UI labels (10–40 px)
/// - **Playfair Display** — devinettes, mots trouvés (15–42 px, Bold/Black)
/// - **Crimson Pro** — corps de texte, explications (12–22 px)
abstract final class AppTypography {
  static TextStyle bebas({
    double size = 16,
    Color color = AppColors.ivoire,
    double letterSpacing = 2,
  }) =>
      GoogleFonts.bebasNeue(
        fontSize: size,
        color: color,
        letterSpacing: letterSpacing,
      );

  static TextStyle playfair({
    double size = 28,
    Color color = AppColors.orSoleil,
    FontWeight weight = FontWeight.w700,
    FontStyle? style,
  }) =>
      GoogleFonts.playfairDisplay(
        fontSize: size,
        color: color,
        fontWeight: weight,
        fontStyle: style,
      );

  static TextStyle crimson({
    double size = 16,
    Color color = AppColors.ivoire,
    FontStyle? style,
  }) =>
      GoogleFonts.crimsonPro(
        fontSize: size,
        color: color,
        fontStyle: style,
      );

  /// Tagline italique bois clair (splash screen).
  static TextStyle taglineItalic({double size = 14}) => GoogleFonts.crimsonPro(
        fontSize: size,
        color: AppColors.tagline,
        fontStyle: FontStyle.italic,
      );

  /// Logo "K" géant du splash.
  static TextStyle logoK = GoogleFonts.playfairDisplay(
    fontSize: 96,
    color: AppColors.orSoleil,
    fontWeight: FontWeight.w900,
    height: 1,
  );

  /// Titre KILIMANDJARO sous le logo.
  static TextStyle logoTitle = GoogleFonts.bebasNeue(
    fontSize: 18,
    color: AppColors.ivoire,
    letterSpacing: 4,
  );
}
