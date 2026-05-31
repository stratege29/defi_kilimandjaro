import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Pastille pays **vectorielle** — remplace les emoji drapeaux (🇨🇮…) qui se
/// rendent différemment selon l'OS (tell amateur sur les stores).
///
/// Affiche le code ISO-2 du pays (ex. « CI ») en or sur un disque sombre
/// bordé hairline. Cohérent quel que soit l'appareil.
///
/// Usage : `FlagRoundel(countryCode: 'CI')` dans le header de jeu, les cards
/// de sommet, le label flottant de l'altimètre, etc.
class FlagRoundel extends StatelessWidget {
  const FlagRoundel({
    required this.countryCode,
    this.size = 34,
    super.key,
  });

  /// Code ISO-2 du pays (insensible à la casse). Ex. `ci`, `TZ`, `Ma`.
  final String countryCode;

  /// Diamètre du disque en logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = countryCode.trim().toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceContainer,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        code,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: AppTypography.labelSm.copyWith(
          color: AppColors.orJour,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
