import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Illustration peinte d'un sommet (`assets/images/mountains/hero_<id>.png`).
///
/// Charge l'asset hero correspondant à l'`id` de la montagne via
/// [AppAssets.mountainHero]. En cas d'asset manquant (id sans visuel généré),
/// affiche un fallback discret plutôt que l'icône d'erreur Flutter.
///
/// Usage : carte « Continuer l'ascension » (accueil), scène Sommets, fond du
/// hub Défi, etc.
class MountainHeroImage extends StatelessWidget {
  const MountainHeroImage({
    required this.mountainId,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.opacity = 1,
    this.fallback,
    super.key,
  });

  /// Identifiant de la montagne (ex. `ci_nimba`, `tz_kilimanjaro`).
  final String mountainId;

  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;

  /// Opacité globale (utile en fond atmosphérique).
  final double opacity;

  /// Widget de repli si l'asset hero n'existe pas (montagne sans visuel
  /// généré). Défaut : petite icône terrain. Passer une silhouette
  /// vectorielle ici pour un fond cohérent sur tous les sommets.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      AppAssets.mountainHero(mountainId),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      errorBuilder: (_, __, ___) =>
          fallback ?? _Fallback(width: width, height: height),
    );
    if (opacity >= 1) return image;
    return Opacity(opacity: opacity, child: image);
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: const Center(
        child: Icon(Icons.terrain_rounded, color: AppColors.texteTertiaire),
      ),
    );
  }
}
