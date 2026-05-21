import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:flutter/material.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// Silhouette d'un sommet rendue depuis un `.vec` précompilé.
///
/// Chaque montagne du jeu a sa propre silhouette réelle dessinée à la main
/// dans `assets/svg/mountains/{id}.svg`, compilée en `.vec` binaire par
/// `tools/scripts/compile_mountains.sh` (~5-10× plus rapide à l'affichage
/// que `flutter_svg`).
///
/// Drop-in remplacement de l'ancien `MountainSilhouettePainter` :
/// même position dans la stack, mêmes états (locked / completed / pulse).
class MountainSilhouetteVector extends StatelessWidget {
  const MountainSilhouetteVector({
    required this.mountain,
    this.hasPulse = false,
    this.pulseValue = 0,
    this.fit = BoxFit.fitWidth,
    super.key,
  });

  final Mountain mountain;

  /// Active le halo pulsant doré (sommet en cours).
  final bool hasPulse;

  /// Valeur 0..1 fournie par l'`AnimationController` parent.
  final double pulseValue;

  /// Mode de remplissage du `.vec` dans son container.
  ///
  /// `BoxFit.fitWidth` (défaut) : utilisé dans l'écran "Sommets" — SVG carré
  /// occupant la largeur, ciel transparent au-dessus rempli par
  /// l'AtmosphereLayer.
  ///
  /// `BoxFit.cover` : utilisé dans l'écran de détail — SVG remplit toute la
  /// viewport allouée (crop horizontal léger pour les mountains à pic
  /// excentré comme Mawenzi du Kilimandjaro). Compense visuellement les
  /// mountains à faible amplitude verticale (Red Rocks, mesas).
  final BoxFit fit;

  bool get _isCompleted =>
      mountain.totalLevels > 0 &&
      mountain.completedLevels >= mountain.totalLevels;

  bool get _isLocked => !mountain.unlocked;

  String get _assetPath => 'assets/svg/mountains/${mountain.id}.svg.vec';

  @override
  Widget build(BuildContext context) {
    Widget silhouette = VectorGraphic(
      loader: AssetBytesLoader(_assetPath),
      fit: fit,
      alignment: Alignment.bottomCenter,
    );

    if (_isLocked) {
      silhouette = ColorFiltered(
        colorFilter: _lockedColorFilter,
        child: silhouette,
      );
    }

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.bottomCenter,
      children: [
        if (hasPulse && !_isLocked)
          Positioned.fill(
            child: CustomPaint(
              painter: _PulseHaloPainter(pulseValue: pulseValue),
            ),
          ),
        silhouette,
        if (_isCompleted && !_isLocked)
          const Positioned(
            top: 8,
            right: 12,
            child: _CompletionFlag(),
          ),
      ],
    );
  }
}

// ============================================================
// Color filter : silhouette verrouillée
// ============================================================

/// Matrice qui convertit en niveaux de gris (luminance ITU-R BT.709) puis
/// applique une opacité de 45 %. Préserve la structure tonale du dessin —
/// la montagne reste reconnaissable mais clairement "non débloquée".
const ColorFilter _lockedColorFilter = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0,      0,      0,      0.45, 0,
]);

// ============================================================
// Halo pulsant du sommet en cours
// ============================================================

class _PulseHaloPainter extends CustomPainter {
  const _PulseHaloPainter({required this.pulseValue});

  final double pulseValue;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.42;
    final radius = (size.width * 0.48) * (0.9 + pulseValue * 0.3);
    final opacity = (1 - pulseValue) * 0.32;

    final paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          AppColors.orSoleil.withValues(alpha: opacity),
          AppColors.orSoleil.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));

    canvas.drawCircle(Offset(cx, cy), radius, paint);
  }

  @override
  bool shouldRepaint(_PulseHaloPainter oldDelegate) =>
      oldDelegate.pulseValue != pulseValue;
}

// ============================================================
// Drapeau planté au sommet (état completed)
// ============================================================

class _CompletionFlag extends StatelessWidget {
  const _CompletionFlag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.flag_rounded,
        size: 16,
        color: AppColors.textePrimaire,
      ),
    );
  }
}
