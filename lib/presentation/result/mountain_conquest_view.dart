import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// Overlay « TU AS CONQUIS ce sommet » — affiché juste après la victoire du
/// dernier niveau d'une montagne, avant la transition vers la suivante.
///
/// Mis en scène façon victoire : particules dorées peintes en éventail, halo
/// pulsant derrière la silhouette du sommet, gros chiffre d'altitude.
class MountainConquestView extends StatefulWidget {
  const MountainConquestView({
    required this.mountain,
    required this.onContinue,
    super.key,
  });

  final Mountain mountain;

  /// Callback déclenché par le bouton « PROCHAINE MONTAGNE ».
  final VoidCallback onContinue;

  @override
  State<MountainConquestView> createState() => _MountainConquestViewState();
}

class _MountainConquestViewState extends State<MountainConquestView>
    with TickerProviderStateMixin {
  late final AnimationController _particleCtrl;
  late final AnimationController _cardCtrl;
  late final AnimationController _haloCtrl;

  late final Animation<double> _cardScale;
  late final Animation<double> _haloPulse;

  @override
  void initState() {
    super.initState();

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();

    // Spring damped — Duolingo style : 1 overshoot puis stabilisation.
    // Plus rigide (stiffness 200) que VictoryView car l'écran de conquête
    // mérite un pop plus assertif que l'écran de victoire de niveau.
    _cardCtrl = AnimationController(vsync: this, upperBound: 2)
      ..animateWith(
        SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 200, damping: 15),
          0,
          1,
          0,
        ),
      );

    _haloCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _cardScale = Tween<double>(begin: 0.6, end: 1).animate(_cardCtrl);

    _haloPulse = CurvedAnimation(parent: _haloCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _particleCtrl.dispose();
    _cardCtrl.dispose();
    _haloCtrl.dispose();
    super.dispose();
  }

  String _formatAltitude(int alt) {
    final s = alt.toString();
    if (s.length <= 3) return s;
    return '${s.substring(0, s.length - 3)} ${s.substring(s.length - 3)}';
  }

  @override
  Widget build(BuildContext context) {
    // Material(transparency) : fournit le DefaultTextStyle ancestor pour
    // que les Text n'aient pas le souligné debug "missing material"
    // (même bugfix que VictoryView).
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _particleCtrl,
              builder: (_, __) => CustomPaint(
                painter: _StarBurstPainter(progress: _particleCtrl.value),
              ),
            ),
          ),
          Center(
            child: ScaleTransition(
              scale: _cardScale,
              child: _ConquestCard(
                mountain: widget.mountain,
                altitudeLabel: _formatAltitude(widget.mountain.altitude),
                haloPulse: _haloPulse,
                onContinue: widget.onContinue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConquestCard extends StatelessWidget {
  const _ConquestCard({
    required this.mountain,
    required this.altitudeLabel,
    required this.haloPulse,
    required this.onContinue,
  });

  final Mountain mountain;
  final String altitudeLabel;
  final Animation<double> haloPulse;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return Container(
      width: screenWidth * 0.88,
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        // Palette 2026 : surface opaque + border or fin + double shadow
        // (halo subtil + profondeur). Aligné avec VictoryView refondu.
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.orJour, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.orJour.withValues(alpha: 0.20),
            blurRadius: 32,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Halo pulsant derrière la silhouette — signature anim de l'écran.
          SizedBox(
            width: 160,
            height: 160,
            child: AnimatedBuilder(
              animation: haloPulse,
              builder: (_, child) => Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: 1 + haloPulse.value * 0.25,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.orJour.withValues(
                          alpha: 0.18 * (1 - haloPulse.value),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 128,
                    height: 128,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.bois.withValues(alpha: 0.4),
                      border: Border.all(color: AppColors.orJour, width: 1.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.bottomCenter,
                    child: child,
                  ),
                ],
              ),
              child: VectorGraphic(
                loader: AssetBytesLoader(
                  'assets/svg/mountains/${mountain.id}.svg.vec',
                ),
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Eyebrow — sobre, Barlow Cond 14pt all-caps espacé.
          Text(
            'TU AS CONQUIS',
            style: AppTypography.bebas(
              size: 14,
              color: AppColors.texteSecondaire,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 8),
          // Nom de la montagne — Fraunces displaySm (32pt w700).
          // Moment éditorial fort : naming d'un sommet ivoirien conquis.
          Text(
            mountain.name.toUpperCase(),
            textAlign: TextAlign.center,
            style: AppTypography.displaySm.copyWith(letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          Text(
            mountain.countryName,
            style: AppTypography.crimson(
              size: 14,
              color: AppColors.texteSecondaire,
              style: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          // Altitude — Fraunces displayLg (48pt w800), chiffre prestige
          // type scoreboard athlétique.
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: altitudeLabel, style: AppTypography.displayLg),
                TextSpan(
                  text: ' m',
                  style: AppTypography.displayLg.copyWith(
                    fontSize: 22,
                    color: AppColors.orJour.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${mountain.totalLevels} devinettes maîtrisées',
            style: AppTypography.crimson(
              size: 13,
              color: AppColors.texteTertiaire,
              style: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
          // CTA design system 2026 — scale-on-press 0.96 + haptique selectionClick.
          AppButton(
            label: 'PROCHAINE MONTAGNE',
            onPressed: onContinue,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

/// 16 particules dorées PEINTES en éventail (étincelles + cauris + poussière).
/// Plus large que VictoryView. Remplace les emoji ✨🌟⭐🏔️ par du vectoriel
/// crisp, sans dépendance asset (rendu identique sur tous les OS).
class _StarBurstPainter extends CustomPainter {
  _StarBurstPainter({required this.progress});

  final double progress;

  static const int _count = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final maxRadius = size.shortestSide * 0.65;
    final t = 1 - math.pow(1 - progress, 3).toDouble();
    final opacity = progress < 0.75 ? 1.0 : (1.0 - (progress - 0.75) / 0.25);
    if (opacity <= 0) return;

    for (var i = 0; i < _count; i++) {
      final angle = (2 * math.pi / _count) * i + (i.isEven ? 0 : 0.2);
      final radius = maxRadius * t * (0.82 + (i % 3) * 0.09);
      final p = centre + Offset(math.cos(angle), math.sin(angle)) * radius;

      switch (i % 3) {
        case 0:
          _sparkle(
            canvas,
            p,
            8 * t + 2,
            AppColors.orJour.withValues(alpha: opacity),
            angle,
          );
        case 1:
          canvas.drawCircle(
            p,
            4,
            Paint()..color = AppColors.orJour.withValues(alpha: opacity),
          );
        default:
          canvas.drawCircle(
            p,
            2.5,
            Paint()
              ..color =
                  AppColors.textePrimaire.withValues(alpha: opacity * 0.85),
          );
      }
    }
  }

  /// Étincelle 4 branches concave centrée en [c].
  void _sparkle(Canvas canvas, Offset c, double r, Color color, double rot) {
    final path = Path();
    const tips = 4;
    for (var k = 0; k < tips * 2; k++) {
      final rr = k.isEven ? r : r * 0.32;
      final a = rot + (math.pi / tips) * k;
      final pt = c + Offset(math.cos(a), math.sin(a)) * rr;
      if (k == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_StarBurstPainter old) => old.progress != progress;
}
