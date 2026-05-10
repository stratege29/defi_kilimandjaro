import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Biome visuel d'un sommet, dérivé de son altitude.
enum AtmosphereBiome { savanne, foret, roche, altitude }

/// Retourne le biome correspondant à une altitude en mètres.
AtmosphereBiome biomeForAltitude(int altitudeM) {
  if (altitudeM < 500) return AtmosphereBiome.savanne;
  if (altitudeM < 2000) return AtmosphereBiome.foret;
  if (altitudeM < 4000) return AtmosphereBiome.roche;
  return AtmosphereBiome.altitude;
}

/// Couleur principale de la silhouette selon le biome.
Color silhouetteColorForBiome(AtmosphereBiome biome) {
  switch (biome) {
    case AtmosphereBiome.savanne:
      return AppColors.savanneFonce;
    case AtmosphereBiome.foret:
      return AppColors.vertForet;
    case AtmosphereBiome.roche:
      return AppColors.rocheBrume;
    case AtmosphereBiome.altitude:
      return AppColors.cielHauteur;
  }
}

/// Gradient de fond animé représentant l'atmosphère selon le biome courant.
///
/// Interpolé via [AnimatedContainer] entre les dégradés de biome.
/// Place cette couche en premier dans le Stack de l'écran Sommets.
class AtmosphereLayer extends StatelessWidget {
  const AtmosphereLayer({
    required this.biome,
    super.key,
  });

  final AtmosphereBiome biome;

  List<Color> get _colors {
    switch (biome) {
      case AtmosphereBiome.savanne:
        return [AppColors.savanneOcre, AppColors.savanneFonce];
      case AtmosphereBiome.foret:
        return [AppColors.vertForet, const Color(0xFF0D2510)];
      case AtmosphereBiome.roche:
        return [AppColors.rocheBrume, AppColors.boisFonce];
      case AtmosphereBiome.altitude:
        return [AppColors.cielHauteur, AppColors.neigeBlanche];
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _colors,
        ),
      ),
    );
  }
}

/// Silhouettes de montagnes lointaines en arrière-plan pour l'effet parallax.
///
/// Ces formes simples défilent plus lentement que le PageView principal
/// grâce au [scrollFraction] (0.0 = bas, 1.0 = haut du PageView).
class ParallaxBgLayer extends StatelessWidget {
  const ParallaxBgLayer({
    required this.scrollFraction,
    required this.biome,
    super.key,
  });

  final double scrollFraction;
  final AtmosphereBiome biome;

  @override
  Widget build(BuildContext context) {
    // Déplacement vertical plus lent (30 % de l'amplitude normale).
    final parallaxOffset = scrollFraction * 60.0;

    return ClipRect(
      child: CustomPaint(
        painter: _BgMountainsPainter(
          offsetY: parallaxOffset,
          biome: biome,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BgMountainsPainter extends CustomPainter {
  const _BgMountainsPainter({
    required this.offsetY,
    required this.biome,
  });

  final double offsetY;
  final AtmosphereBiome biome;

  Color get _mountainColor {
    switch (biome) {
      case AtmosphereBiome.savanne:
        return AppColors.savanneFonce.withValues(alpha: 0.35);
      case AtmosphereBiome.foret:
        return AppColors.vertForet.withValues(alpha: 0.55);
      case AtmosphereBiome.roche:
        return AppColors.rocheBrume.withValues(alpha: 0.45);
      case AtmosphereBiome.altitude:
        return AppColors.cielHauteur.withValues(alpha: 0.30);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = _mountainColor
      ..style = PaintingStyle.fill;

    final baseY = h * 0.72 + offsetY;

    // Montagne lointaine gauche
    final p1 = Path()
      ..moveTo(0, baseY + 10)
      ..lineTo(w * 0.22, baseY - h * 0.22)
      ..lineTo(w * 0.44, baseY + 10)
      ..close();
    canvas.drawPath(p1, paint);

    // Montagne lointaine centrale (plus haute)
    final p2 = Path()
      ..moveTo(w * 0.28, baseY + 10)
      ..lineTo(w * 0.52, baseY - h * 0.30)
      ..lineTo(w * 0.76, baseY + 10)
      ..close();
    canvas.drawPath(p2, paint);

    // Montagne lointaine droite
    final p3 = Path()
      ..moveTo(w * 0.60, baseY + 10)
      ..lineTo(w * 0.82, baseY - h * 0.18)
      ..lineTo(w, baseY + 10)
      ..close();
    canvas.drawPath(p3, paint);
  }

  @override
  bool shouldRepaint(_BgMountainsPainter old) =>
      old.offsetY != offsetY || old.biome != biome;
}
