import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Écran 04 — Overlay Victoire (refonte world-class 2026).
///
/// Affiché via [showDialog] avec fond noir à 92 % d'opacité.
///
/// **Architecture visuelle** : card centrée éditoriale.
/// - Griot 96pt en haut (mascotte célèbre, scale-bounce continu)
/// - Mot-réponse en Fraunces display (la plus belle fonte du DS)
/// - Explication culturelle 2-3 lignes Crimson italic
/// - **Proverbe** dans son cadre éditorial dédié — séparateurs gold
///   fins haut+bas, guillemets typographiques « », attribution
///   « — Sagesse Ivoirienne » en bas droit
/// - Reward cauris en chip pill animée (tween 0→N)
/// - CTA SUIVANT via AppButton.primary
///
/// **Bugfix** : wrap en `Material(transparency)` — sans Material ancestor
/// le `Text` Flutter rendait les soulignés debug "missing material".
class VictoryView extends StatefulWidget {
  const VictoryView({
    required this.devinette,
    required this.timeLeft,
    required this.onNext,
    this.starsEarned = 0,
    this.isBoss = false,
    super.key,
  });

  final Devinette devinette;

  /// Secondes restantes au moment de la victoire (pour bonus cauris).
  final int timeLeft;

  /// Nombre d'étoiles obtenues (0-3). 0 ne devrait jamais arriver ici
  /// puisque l'overlay n'est affiché que sur victoire (≥ 1).
  final int starsEarned;

  /// Niveau boss (dernier niveau de la montagne). Quand vrai, l'écran
  /// est enrichi : couronne dorée flottante au-dessus du griot, label
  /// "BOSS VAINCU", particules plus denses.
  final bool isBoss;

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

    // Spring damped — 1 overshoot puis stabilisation (Duolingo-style).
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
      begin: 0.92,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _celebCtrl, curve: Curves.easeInOut));

    _cardScale = Tween<double>(begin: 0.7, end: 1).animate(_cardCtrl);

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

  @override
  Widget build(BuildContext context) {
    // Material(transparency) : fournit le DefaultTextStyle ancestor pour
    // que les Text n'aient pas le souligné debug "missing material".
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: <Widget>[
          // 1. Particules en éventail (derrière la card).
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _particleCtrl,
              builder: (context, _) => CustomPaint(
                painter: _ParticlePainter(progress: _particleCtrl.value),
              ),
            ),
          ),
          // 2. Card éditoriale (spring pop-in).
          Center(
            child: ScaleTransition(
              scale: _cardScale,
              child: _VictoryCard(
                devinette: widget.devinette,
                caurisAnim: _caurisAnim,
                celebScale: _celebScale,
                onNext: widget.onNext,
                starsEarned: widget.starsEarned,
                isBoss: widget.isBoss,
              ),
            ),
          ),
        ],
      ),
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
    required this.onNext,
    required this.starsEarned,
    required this.isBoss,
  });

  final Devinette devinette;
  final Animation<int> caurisAnim;
  final Animation<double> celebScale;
  final VoidCallback onNext;
  final int starsEarned;
  final bool isBoss;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return Container(
      width: screenWidth * 0.88,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orJour, width: 1.5),
        boxShadow: <BoxShadow>[
          // Halo doré subtil (signature 2026).
          BoxShadow(
            color: AppColors.orJour.withValues(alpha: 0.18),
            blurRadius: 28,
          ),
          // Profondeur sous la card.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Label "BOSS VAINCU" en haut quand niveau boss — signature
          // visuelle forte avant même la mascotte.
          if (isBoss) ...<Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.workspace_premium_rounded,
                  size: 22,
                  color: AppColors.orJour,
                ),
                const SizedBox(width: 6),
                Text(
                  'BOSS VAINCU',
                  style: AppTypography.bebas().copyWith(
                    fontSize: 18,
                    letterSpacing: 2.5,
                    color: AppColors.orJour,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.workspace_premium_rounded,
                  size: 22,
                  color: AppColors.orJour,
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          // Mascotte griot 96pt — bouncing victory pose. En mode boss,
          // surmontée d'une couronne flottante.
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: <Widget>[
              ScaleTransition(
                scale: celebScale,
                child: Image.asset(
                  AppAssets.griotVictory,
                  width: 96,
                  height: 96,
                ),
              ),
              if (isBoss)
                Positioned(
                  top: -14,
                  child: Icon(
                    Icons.emoji_events_rounded,
                    size: 36,
                    color: AppColors.orJour,
                    shadows: <Shadow>[
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.65),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 3 étoiles — feedback de performance instantané. Affichées
          // dorées (acquises) ou grises (manquées). 1 étoile = victoire,
          // 2 = sans indice, 3 = victoire en ≤ 50 % du temps.
          _StarsRow(earned: starsEarned),
          const SizedBox(height: 16),
          // Mot-réponse — Fraunces displayMd 40pt w700, gold.
          // Moment éditorial fort : la 1re fois que le mot ivoirien
          // apparaît au joueur. Centré, sans décoration.
          Text(
            devinette.answer,
            style: AppTypography.displayMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Explication culturelle (2-3 lignes max).
          // bodyMd non-italique sur textePrimaire : c'est le moment
          // pédagogique principal, il mérite la couleur primaire et la
          // lisibilité maximale (la chute Fraunces 40pt → 14pt italic était
          // trop violente hiérarchiquement).
          Text(
            devinette.explanation,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.textePrimaire,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          // Reward cauris — chip pill animé (ka-ching).
          _CaurisRewardChip(caurisAnim: caurisAnim),
          const SizedBox(height: 24),
          // CTA primaire — design system 2026.
          AppButton(
            label: 'result.victory.next'.tr(),
            onPressed: onNext,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

/// Rangée des 3 étoiles — chaque étoile prend une couleur or si acquise,
/// gris sombre si manquée. Apparaît au-dessus du mot-réponse pour donner
/// le feedback de performance avant même le contenu pédagogique.
class _StarsRow extends StatelessWidget {
  const _StarsRow({required this.earned});

  final int earned;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 1; i <= 3; i++) ...<Widget>[
          if (i > 1) const SizedBox(width: 6),
          Icon(
            i <= earned ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 32,
            color: i <= earned
                ? AppColors.orJour
                : AppColors.textePrimaire.withValues(alpha: 0.25),
          ),
        ],
      ],
    );
  }
}

/// Chip pill animée affichant les cauris gagnés (icon + tween 0→N + label).
///
/// Remplace l'ancien `Text` plat — c'est le moment "ka-ching" qui doit être
/// visuellement reconnu comme une récompense, pas comme du texte courant.
class _CaurisRewardChip extends StatelessWidget {
  const _CaurisRewardChip({required this.caurisAnim});

  final Animation<int> caurisAnim;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: caurisAnim,
      builder: (_, __) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.orJour.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: AppColors.orJour.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CaurisIcon(),
              const SizedBox(width: 8),
              Text(
                '+${caurisAnim.value}',
                style: AppTypography.headingMd.copyWith(
                  color: AppColors.orJour,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'CAURIS',
                style: AppTypography.labelSm.copyWith(
                  color: AppColors.orJour.withValues(alpha: 0.75),
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Particle system — 12 emojis projetés en éventail depuis le centre
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
