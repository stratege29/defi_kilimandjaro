import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Écran 04 — Overlay Victoire (cf. maquette p.6).
///
/// Affiché via [showDialog] avec fond noir à 92 % d'opacité.
/// 12 particules emoji projetées en fan depuis le centre (CustomPainter).
class VictoryView extends StatefulWidget {
  const VictoryView({
    required this.devinette,
    required this.timeLeft,
    required this.onNext,
    super.key,
  });

  final Devinette devinette;

  /// Secondes restantes au moment de la victoire (pour bonus cauris).
  final int timeLeft;

  /// Callback appelé quand l'utilisateur tape SUIVANT.
  final VoidCallback onNext;

  @override
  State<VictoryView> createState() => _VictoryViewState();
}

class _VictoryViewState extends State<VictoryView>
    with TickerProviderStateMixin {
  late final AnimationController _particleCtrl;
  late final AnimationController _celebCtrl;
  late final AnimationController _cardCtrl;
  late final AnimationController _caurisCtrl;

  late final Animation<double> _celebScale;
  late final Animation<double> _cardScale;
  late final Animation<int> _caurisAnim;

  int get _caurisEarned => 30 + widget.timeLeft;

  @override
  void initState() {
    super.initState();

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();

    _celebCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // Spring damped : 1 overshoot puis stabilisation (Duolingo-style).
    // upperBound:2 autorise le bond visuel sans clipping.
    _cardCtrl = AnimationController(vsync: this, upperBound: 2)
      ..animateWith(
        SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 180, damping: 14),
          0,
          1,
          0,
        ),
      );

    _celebScale = Tween<double>(
      begin: 0.85,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _celebCtrl, curve: Curves.easeInOut));

    // Tween piloté par le ressort : la valeur du controller oscille en
    // amorti, le Tween la mappe sur l'échelle visuelle 0.7 → 1.0+.
    _cardScale = Tween<double>(begin: 0.7, end: 1).animate(_cardCtrl);

    // Compteur cauris : décale après le pop-in de la carte pour que le tween
    // 0 → N soit perçu comme une récompense distincte.
    _caurisCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _caurisAnim = IntTween(
      begin: 0,
      end: _caurisEarned,
    ).animate(CurvedAnimation(parent: _caurisCtrl, curve: Curves.easeOutCubic));
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (mounted) _caurisCtrl.forward();
    });
  }

  @override
  void dispose() {
    _particleCtrl.dispose();
    _celebCtrl.dispose();
    _cardCtrl.dispose();
    _caurisCtrl.dispose();
    super.dispose();
  }

  String _subjectEmoji() {
    final tags = widget.devinette.tags;
    if (tags.any((t) => t.contains('cuisine') || t.contains('food'))) {
      return '🍲';
    }
    if (tags.any((t) => t.contains('nature') || t.contains('plante'))) {
      return '🌿';
    }
    if (tags.any((t) => t.contains('animal'))) return '🦁';
    if (tags.any((t) => t.contains('musique') || t.contains('music'))) {
      return '🎵';
    }
    if (tags.any((t) => t.contains('art') || t.contains('tissu'))) {
      return '🎨';
    }
    return '✨';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // Particle layer behind the card.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _particleCtrl,
            builder: (context, _) => CustomPaint(
              painter: _ParticlePainter(progress: _particleCtrl.value),
            ),
          ),
        ),
        // Card.
        Center(
          child: ScaleTransition(
            scale: _cardScale,
            child: _VictoryCard(
              devinette: widget.devinette,
              caurisAnim: _caurisAnim,
              celebScale: _celebScale,
              subjectEmoji: _subjectEmoji(),
              onNext: widget.onNext,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Card widget
// ---------------------------------------------------------------------------

class _VictoryCard extends StatelessWidget {
  const _VictoryCard({
    required this.devinette,
    required this.caurisAnim,
    required this.celebScale,
    required this.subjectEmoji,
    required this.onNext,
  });

  final Devinette devinette;
  final Animation<int> caurisAnim;
  final Animation<double> celebScale;
  final String subjectEmoji;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return Container(
      width: screenWidth * 0.88,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.boisFonce.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orSoleil, width: 3),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Griot mascot — bouncing victory pose.
            ScaleTransition(
              scale: celebScale,
              child: Image.asset(
                AppAssets.griotVictory,
                width: 140,
                height: 140,
              ),
            ),
            const SizedBox(height: 12),
            // Subject illustration circle.
            _SubjectCircle(
              emoji: subjectEmoji,
              borderColor: AppColors.orSoleil,
            ),
            const SizedBox(height: 16),
            // Answer word.
            Text(
              devinette.answer,
              style: AppTypography.bebas(size: 42, color: AppColors.orSoleil),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            // Cultural explanation.
            Text(
              devinette.explanation,
              textAlign: TextAlign.center,
              style: AppTypography.crimson(style: FontStyle.italic),
            ),
            const SizedBox(height: 16),
            // Proverb box.
            _ProverbBox(proverb: devinette.proverb),
            const SizedBox(height: 14),
            // Cauris earned — compteur tween 0 → N (ka-ching).
            AnimatedBuilder(
              animation: caurisAnim,
              builder: (_, __) => Text(
                'result.victory.cauris_earned'.tr(
                  namedArgs: <String, String>{'cauris': '${caurisAnim.value}'},
                ),
                style: AppTypography.bebas(size: 18, color: AppColors.orSoleil),
              ),
            ),
            const SizedBox(height: 20),
            // Next button — design system 2026 (AppButton primary, scale-on-press).
            AppButton(
              label: 'result.victory.next'.tr(),
              onPressed: onNext,
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectCircle extends StatelessWidget {
  const _SubjectCircle({required this.emoji, required this.borderColor});

  final String emoji;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.boisFonce,
        border: Border.all(color: borderColor, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 56)),
    );
  }
}

class _ProverbBox extends StatelessWidget {
  const _ProverbBox({required this.proverb});

  final String proverb;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.orSoleil, width: 1.5),
      ),
      child: Text(
        '"$proverb"',
        textAlign: TextAlign.center,
        style: AppTypography.crimson(
          size: 18,
          color: AppColors.orSoleil,
          style: FontStyle.italic,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Particle system — 12 emoji shot in fan from centre outwards
// ---------------------------------------------------------------------------

const List<String> _kParticleEmojis = <String>['✨', '🌟', '🪙'];

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    const particleCount = 12;
    final maxRadius = size.shortestSide * 0.55;

    for (var i = 0; i < particleCount; i++) {
      // Even fan across 360°.
      final angle = (2 * math.pi / particleCount) * i;

      // easeOutCubic curve.
      final t = 1 - math.pow(1 - progress, 3).toDouble();
      final radius = maxRadius * t;

      final dx = centre.dx + radius * math.cos(angle);
      final dy = centre.dy + radius * math.sin(angle);

      // Fade out in last 30 % of animation.
      final opacity = (progress < 0.7) ? 1.0 : (1.0 - (progress - 0.7) / 0.3);

      final textPainter = TextPainter(
        text: TextSpan(
          text: _kParticleEmojis[i % _kParticleEmojis.length],
          style: TextStyle(
            fontSize: 20,
            color: Colors.white.withValues(alpha: opacity),
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(dx - textPainter.width / 2, dy - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}
