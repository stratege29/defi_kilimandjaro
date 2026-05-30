import 'package:flutter/widgets.dart';

/// Tokens d'espacement Kilimandjaro — grille 4pt stricte.
///
/// Règle d'usage : tout padding, margin, gap ou SizedBox doit utiliser
/// l'un de ces tokens. Les valeurs intermédiaires (10, 14, 18…) ne sont
/// pas autorisées — elles brisent le rythme visuel.
///
/// Mapping mémorisable :
/// - `xs`   (4) — gap inter-éléments serrés (icon + label)
/// - `sm`   (8) — gap standard entre composants liés
/// - `md`  (16) — padding interne de cards, marges horizontales screens
/// - `lg`  (24) — séparation entre sections d'un même écran
/// - `xl`  (32) — padding interne d'overlays / dialogs
/// - `xxl` (48) — séparation entre groupes majeurs (ex: header / contenu)
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  // ---- Rayons de coin (refonte 2026). ----
  // Échelle mémorisable : chips/inputs (sm), boutons (md), cards (lg),
  // cards héros / overlays (xl), pilules entièrement arrondies (pill).

  /// Rayon serré — chips, inputs, petites tuiles.
  static const double radiusSm = 12;

  /// Rayon standard — boutons, tuiles-lettres.
  static const double radiusMd = 16;

  /// Rayon large — cards de contenu, dialogs.
  static const double radiusLg = 20;

  /// Rayon héros — cards d'accomplissement, overlays premium.
  static const double radiusXl = 24;

  /// Pilule entièrement arrondie — badges, chips, CTA arrondis.
  static const double radiusPill = 999;

  // ---- Helpers SizedBox prêts à l'emploi pour les gaps verticaux. ----

  /// Gap vertical de 4pt.
  static const SizedBox gapXs = SizedBox(height: xs);

  /// Gap vertical de 8pt.
  static const SizedBox gapSm = SizedBox(height: sm);

  /// Gap vertical de 16pt.
  static const SizedBox gapMd = SizedBox(height: md);

  /// Gap vertical de 24pt.
  static const SizedBox gapLg = SizedBox(height: lg);

  /// Gap vertical de 32pt.
  static const SizedBox gapXl = SizedBox(height: xl);

  /// Gap vertical de 48pt.
  static const SizedBox gapXxl = SizedBox(height: xxl);

  // ---- Helpers SizedBox pour les gaps horizontaux (rows). ----

  /// Gap horizontal de 4pt.
  static const SizedBox hGapXs = SizedBox(width: xs);

  /// Gap horizontal de 8pt.
  static const SizedBox hGapSm = SizedBox(width: sm);

  /// Gap horizontal de 16pt.
  static const SizedBox hGapMd = SizedBox(width: md);

  /// Gap horizontal de 24pt.
  static const SizedBox hGapLg = SizedBox(width: lg);

  // ---- EdgeInsets composés courants. ----

  /// Padding écran standard : 16pt horizontal, sans vertical.
  static const EdgeInsets screenH = EdgeInsets.symmetric(horizontal: md);

  /// Padding écran complet : 16pt sur 4 côtés.
  static const EdgeInsets screenAll = EdgeInsets.all(md);

  /// Padding interne d'une card standard : 16pt sur 4 côtés.
  static const EdgeInsets cardAll = EdgeInsets.all(md);

  /// Padding interne d'un dialog / overlay : 24pt horizontal, 32pt vertical.
  static const EdgeInsets dialogAll = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: xl,
  );
}
