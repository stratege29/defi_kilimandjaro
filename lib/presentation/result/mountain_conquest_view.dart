import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Overlay « TU AS CONQUIS ce sommet » — affiché juste après la victoire du
/// dernier niveau d'une montagne, avant la transition vers la suivante.
///
/// Mis en scène façon victoire : particules en éventail, halo pulsant
/// derrière l'emoji drapeau, gros chiffre d'altitude.
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
          // Halo pulsant derrière le drapeau — signature anim de l'écran.
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
                    alignment: Alignment.center,
                    child: child,
                  ),
                ],
              ),
              child: Text(
                mountain.flagEmoji,
                style: const TextStyle(fontSize: 76),
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

/// 16 emojis en éventail + traînée — plus grand que VictoryView.
class _StarBurstPainter extends CustomPainter {
  _StarBurstPainter({required this.progress});

  final double progress;

  static const _emojis = <String>['✨', '🌟', '⭐', '🏔️'];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    const count = 16;
    final maxRadius = size.shortestSide * 0.65;

    for (var i = 0; i < count; i++) {
      final angle = (2 * math.pi / count) * i;
      final t = 1 - math.pow(1 - progress, 3).toDouble();
      final radius = maxRadius * t;
      final dx = centre.dx + radius * math.cos(angle);
      final dy = centre.dy + radius * math.sin(angle);
      final opacity = (progress < 0.75)
          ? 1.0
          : (1.0 - (progress - 0.75) / 0.25);

      final tp = TextPainter(
        text: TextSpan(
          text: _emojis[i % _emojis.length],
          style: TextStyle(
            fontSize: 22,
            color: Colors.white.withValues(alpha: opacity),
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(dx - tp.width / 2, dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_StarBurstPainter old) => old.progress != progress;
}
