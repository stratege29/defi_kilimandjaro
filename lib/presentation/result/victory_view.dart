import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/ads/ads_service.dart';
import 'package:defi_kilimandjaro/data/ads/rewarded_daily_cap_service.dart';
import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class VictoryView extends ConsumerStatefulWidget {
  const VictoryView({
    required this.devinette,
    required this.timeLeft,
    required this.caurisAwarded,
    required this.onNext,
    this.starsEarned = 0,
    this.isBoss = false,
    super.key,
  });

  final Devinette devinette;

  /// Secondes restantes au moment de la victoire (pour affichage info).
  final int timeLeft;

  /// Récompense effective créditée par le controller. Pilote l'animation
  /// du chip "+N CAURIS" et sert de base au bouton "Doubler la récompense"
  /// (rewarded vidéo crédite un second [caurisAwarded] sur succès).
  final int caurisAwarded;

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
  ConsumerState<VictoryView> createState() => _VictoryViewState();
}

class _VictoryViewState extends ConsumerState<VictoryView>
    with TickerProviderStateMixin {
  late final AnimationController _particleCtrl;
  late final AnimationController _celebCtrl;
  late final AnimationController _cardCtrl;
  late final AnimationController _caurisCtrl;

  late final Animation<double> _celebScale;
  late final Animation<double> _cardScale;
  late final Animation<int> _caurisAnim;

  int get _caurisEarned => widget.caurisAwarded;

  /// Vrai après que le joueur a cliqué "Doubler" et que la pub s'est
  /// terminée avec succès — masque le bouton et déclenche le second tween
  /// d'animation.
  bool _doubled = false;

  /// Vrai pendant la transition (pub en cours / crédit cauris) pour éviter
  /// les double-taps qui crédentteraient 2× la récompense bonus.
  bool _doubling = false;

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

  /// Construit le bouton "Doubler la récompense" si toutes les conditions
  /// sont réunies : flag Remote Config activé, joueur sans No-Ads, killswitch
  /// off, cap quotidien non atteint, pub pas encore visionnée pour cette
  /// victoire. Retourne `SizedBox.shrink` sinon — le card omet alors la
  /// row supplémentaire.
  Widget _buildDoubleButton(BuildContext context) {
    if (_doubled) return const SizedBox.shrink();

    final econ = ref.watch(gameEconomyConfigProvider);
    if (!econ.rewardedDoubleEnabled) return const SizedBox.shrink();

    final progress = ref.watch(playerProgressProvider);
    if (progress.noAdsPurchased) return const SizedBox.shrink();

    if (!ref.watch(canOfferRewardedProvider)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _DoubleRewardButton(
        bonus: widget.caurisAwarded,
        loading: _doubling,
        onTap: _doubling ? null : _handleDouble,
      ),
    );
  }

  /// Lance la rewarded vidéo et crédite un second `caurisAwarded` si le
  /// joueur regarde jusqu'au bout. Affiche un snackbar de confirmation
  /// puis cache le bouton + déclenche la 2e animation cauris.
  Future<void> _handleDouble() async {
    if (_doubling || _doubled) return;
    setState(() => _doubling = true);

    final bonus = widget.caurisAwarded;
    final got = await ref
        .read(adsServiceProvider)
        .showRewardedForCauris(caurisReward: bonus);

    if (!mounted) return;
    if (got) {
      setState(() {
        _doubled = true;
        _doubling = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '+$bonus Cauris bonus — récompense doublée !',
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.orJour,
          duration: const Duration(milliseconds: 1500),
        ),
      );
    } else {
      setState(() => _doubling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Material(transparency) : fournit le DefaultTextStyle ancestor pour
    // que les Text n'aient pas le souligné debug "missing material".
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: <Widget>[
          // 1. Particules en éventail (derrière la card). RepaintBoundary :
          // isole le repaint de l'animation des particules de la card.
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _particleCtrl,
                builder: (context, _) => CustomPaint(
                  painter: _ParticlePainter(progress: _particleCtrl.value),
                ),
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
                doubleButton: _buildDoubleButton(context),
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
    required this.doubleButton,
  });

  final Devinette devinette;
  final Animation<int> caurisAnim;
  final Animation<double> celebScale;
  final VoidCallback onNext;
  final int starsEarned;
  final bool isBoss;

  /// Bouton optionnel "Doubler la récompense" (rewarded video). Vide
  /// (SizedBox.shrink) quand les conditions ne sont pas réunies, ce qui
  /// laisse le card visuellement inchangé pour les joueurs No-Ads / cap
  /// atteint / killswitch.
  final Widget doubleButton;

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
          // Bouton optionnel "Doubler" — n'apparaît que si conditions
          // remplies (cf. `_VictoryViewState._buildDoubleButton`).
          doubleButton,
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

/// Bouton "Doubler la récompense" — convertit ~25-40 % des victoires
/// observées sur le segment Word puzzle. Style discret pour ne pas
/// éclipser le CTA primaire "SUIVANT" : bordure or, fond translucide,
/// icône play_circle + montant en gros.
class _DoubleRewardButton extends StatelessWidget {
  const _DoubleRewardButton({
    required this.bonus,
    required this.loading,
    required this.onTap,
  });

  final int bonus;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.orJour.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: AppColors.orJour.withValues(alpha: 0.55),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.orJour),
                  ),
                )
              else
                const Icon(
                  Icons.play_circle_filled_rounded,
                  size: 20,
                  color: AppColors.orJour,
                ),
              const SizedBox(width: 8),
              Text(
                'DOUBLER (+$bonus)',
                style: AppTypography.bebas(
                  size: 14,
                  color: AppColors.orJour,
                ).copyWith(letterSpacing: 1.2),
              ),
              const SizedBox(width: 6),
              const CaurisIcon(size: 16),
            ],
          ),
        ),
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
// Particules dorées PEINTES (étincelles 4 branches + cauris + poussière crème)
// projetées en éventail. Remplace les emoji ✨🌟🪙 (rendu OS-dépendant) par
// du vectoriel crisp, sans dépendance asset.
// ---------------------------------------------------------------------------

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.progress});

  final double progress;

  static const int _count = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final maxRadius = size.shortestSide * 0.55;
    // easeOutCubic + fade-out sur les 30 derniers %.
    final t = 1 - math.pow(1 - progress, 3).toDouble();
    final opacity = progress < 0.7 ? 1.0 : (1.0 - (progress - 0.7) / 0.3);
    if (opacity <= 0) return;

    for (var i = 0; i < _count; i++) {
      final angle = (2 * math.pi / _count) * i + (i.isEven ? 0 : 0.22);
      final radius = maxRadius * t * (0.85 + (i % 3) * 0.08);
      final p = centre + Offset(math.cos(angle), math.sin(angle)) * radius;

      switch (i % 3) {
        case 0:
          canvas.drawCircle(
            p,
            4,
            Paint()..color = AppColors.orJour.withValues(alpha: opacity),
          );
        case 1:
          _sparkle(
            canvas,
            p,
            7 * t + 2,
            AppColors.orJour.withValues(alpha: opacity),
            angle,
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

  /// Dessine une étincelle 4 branches concave centrée en [c].
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
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}
