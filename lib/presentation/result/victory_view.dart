import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/ads/ads_service.dart';
import 'package:defi_kilimandjaro/data/ads/rewarded_daily_cap_service.dart';
import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/presentation/result/devinette_explanation.dart';
import 'package:defi_kilimandjaro/presentation/result/reward_lines.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:defi_kilimandjaro/presentation/widgets/dashed_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/kili_mascot.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Écran 04 — Overlay Victoire (refonte world-class 2026).
///
/// Affiché via [showDialog] avec fond noir à 92 % d'opacité.
///
/// **Architecture visuelle** : card centrée éditoriale.
/// - Kili (le margouillat) en haut (idle + hochement de tête déclenché à
///   l'ouverture de la card — seule animation de la mascotte, pas de pulsation)
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
    this.freehandBonus = 0,
    this.perfectBonus = 0,
    this.comboStreak = 0,
    this.comboMultiplier = 1.0,
    this.starsEarned = 0,
    this.isBoss = false,
    this.devinettes,
    super.key,
  });

  final Devinette devinette;

  /// Toutes les devinettes du niveau (rafale : 3 mots, duo : 2 mots).
  /// `null` = niveau à un seul mot. Au-delà d'une, l'explication de chaque
  /// mot est listée (mot en gras + explication) sous le mot-réponse.
  final List<Devinette>? devinettes;

  /// Devinettes à expliquer, principale seule par défaut.
  List<Devinette> get allDevinettes => devinettes ?? <Devinette>[devinette];

  /// Secondes restantes au moment de la victoire (pour affichage info).
  final int timeLeft;

  /// Récompense effective créditée par le controller. Pilote l'animation
  /// du chip "+N CAURIS" et sert de base au bouton "Doubler la récompense"
  /// (rewarded vidéo crédite un second [caurisAwarded] sur succès).
  final int caurisAwarded;

  /// Bonus « À main levée » crédité en plus de [caurisAwarded] (0 si le tracé
  /// se croisait ou mot trop court). Affiché en ligne dédiée sous le chip
  /// cauris quand > 0. **Déjà inclus** dans le solde — purement informatif.
  final int freehandBonus;

  /// Bonus « Sans faute » (aucun mot erroné sur le niveau), déjà inclus dans
  /// le solde. 0 = pas de ligne.
  final int perfectBonus;

  /// Longueur de la série intra-session (victoire courante incluse).
  final int comboStreak;

  /// Multiplicateur de série appliqué à [caurisAwarded] (1.0 = pas de ligne).
  final double comboMultiplier;

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
  late final AnimationController _cardCtrl;
  late final AnimationController _caurisCtrl;

  late final Animation<double> _cardScale;
  late final Animation<int> _caurisAnim;

  /// Poignée pilotant la mascotte Kili : on déclenche son hochement de tête
  /// une fois la card apparue (geste signature « bonne réponse »).
  final KiliController _kili = KiliController();

  /// Total animé dans le chip « ka-ching » = récompense de base (série
  /// incluse) + bonus à main levée + bonus sans faute. Les lignes sous le
  /// chip en donnent la décomposition (le joueur n'additionne rien).
  int get _caurisEarned =>
      widget.caurisAwarded + widget.freehandBonus + widget.perfectBonus;

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

    // Hochement de Kili une fois la card posée (le spring pop-in dure ~600 ms).
    // Synchronisé grosso modo avec le « ka-ching » cauris pour un pic de
    // célébration unique.
    Future<void>.delayed(const Duration(milliseconds: 550), () {
      if (mounted) _kili.nod();
    });
  }

  @override
  void dispose() {
    _particleCtrl.dispose();
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
            'result.victory.double_done'.tr(
              namedArgs: <String, String>{'cauris': '$bonus'},
            ),
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
                devinettes: widget.allDevinettes,
                caurisAnim: _caurisAnim,
                kili: _kili,
                onNext: widget.onNext,
                starsEarned: widget.starsEarned,
                isBoss: widget.isBoss,
                bonusLines: RewardBonusLines(
                  comboStreak: widget.comboStreak,
                  comboMultiplier: widget.comboMultiplier,
                  perfectBonus: widget.perfectBonus,
                  freehandBonus: widget.freehandBonus,
                ),
                hasBonusLines: widget.comboMultiplier > 1 ||
                    widget.perfectBonus > 0 ||
                    widget.freehandBonus > 0,
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
    required this.devinettes,
    required this.caurisAnim,
    required this.kili,
    required this.onNext,
    required this.starsEarned,
    required this.isBoss,
    required this.bonusLines,
    required this.hasBonusLines,
    required this.doubleButton,
  });

  final Devinette devinette;

  /// Devinettes à expliquer (≥ 1, [devinette] en tête).
  final List<Devinette> devinettes;

  final Animation<int> caurisAnim;

  /// Poignée de la mascotte Kili affichée en tête de card (hochement piloté
  /// par [_VictoryViewState]).
  final KiliController kili;

  final VoidCallback onNext;
  final int starsEarned;
  final bool isBoss;

  /// Lignes série / sans faute / à main levée (cf. [RewardBonusLines]).
  final Widget bonusLines;

  /// Vrai si au moins une ligne bonus est à afficher (pilote l'espacement).
  final bool hasBonusLines;

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
        borderRadius: BorderRadius.circular(24),
        // Vert Nuit : bordure sémantique « victoire » (succès) en hairline
        // teinté, pas d'or plein. La profondeur naît d'une seule ombre noire
        // diffuse — aucun halo doré (retenue : « moins de glows »).
        border: Border.all(
          color: isBoss
              ? AppColors.orJour.withValues(alpha: 0.5)
              : AppColors.success.withValues(alpha: 0.4),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 60,
            offset: const Offset(0, 24),
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
                Image.asset(AppAssets.iconStarGold, width: 22, height: 22),
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
                Image.asset(AppAssets.iconStarGold, width: 22, height: 22),
              ],
            ),
            // Marge élargie : la couronne déborde de 20 px au-dessus de Kili.
            const SizedBox(height: 26),
          ],
          // Mascotte Kili — idle + hochement de tête à l'ouverture (pas de
          // pulsation). En mode boss, surmontée d'une couronne flottante.
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: <Widget>[
              KiliMascot(controller: kili, size: 130),
              if (isBoss)
                // Décalée vers la gauche : la tête de Kili est à gauche du
                // centre de sa boîte (la queue occupe la droite).
                Positioned(
                  top: -20,
                  child: Transform.translate(
                    offset: const Offset(-24, 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.65),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        AppAssets.iconCrownBoss,
                        width: 44,
                        height: 44,
                      ),
                    ),
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
            devinette.answer.toUpperCase(),
            style: AppTypography.displayMd.copyWith(
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  offset: const Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Explication culturelle (2-3 lignes max).
          // bodyMd non-italique sur textePrimaire : c'est le moment
          // pédagogique principal, il mérite la couleur primaire et la
          // lisibilité maximale (la chute Fraunces 40pt → 14pt italic était
          // trop violente hiérarchiquement).
          if (devinettes.length <= 1)
            Text(
              devinette.explanation,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.textePrimaire,
                height: 1.5,
              ),
            )
          else
            // Rafale / duo : une ligne par mot (mot en gras + explication).
            for (var i = 0; i < devinettes.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                child: DevinetteExplanation(devinette: devinettes[i]),
              ),
          const SizedBox(height: 24),
          // Reward cauris — chip pill animé (ka-ching).
          _CaurisRewardChip(caurisAnim: caurisAnim),
          // Lignes bonus discrètes (série, sans faute, à main levée) —
          // uniquement quand au moins une s'applique.
          if (hasBonusLines) ...<Widget>[
            const SizedBox(height: 10),
            bonusLines,
          ],
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

/// Bouton "Doubler la récompense" — filet pointillé doré pleine largeur
/// (maquette `.double`). Style discret pour ne pas éclipser le CTA primaire
/// "SUIVANT". Affiche un spinner en tête pendant le chargement de la pub.
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
    return DashedButton(
      // Le rewarded ne crédite QUE la base (pas le bonus à main levée), donc
      // le libellé annonce le gain concret en cauris plutôt qu'un « ×2 » qui
      // serait trompeur quand un bonus à main levée existe.
      label:
          '${'result.victory.double_cta'.tr(namedArgs: <String, String>{'cauris': '$bonus'})} ▶',
      onTap: onTap,
      leading: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.orJour),
              ),
            )
          : null,
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
          // Étoile or peinte ; l'étoile manquée reste la même image,
          // désaturée et atténuée (même convention que les titres
          // verrouillés du profil).
          Opacity(
            opacity: i <= earned ? 1 : 0.22,
            child: ColorFiltered(
              colorFilter: i <= earned
                  ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                  : const ColorFilter.matrix(<double>[
                      0.2126, 0.7152, 0.0722, 0, 0, //
                      0.2126, 0.7152, 0.0722, 0, 0, //
                      0.2126, 0.7152, 0.0722, 0, 0, //
                      0, 0, 0, 1, 0, //
                    ]),
              child: Image.asset(AppAssets.iconStarGold, width: 32, height: 32),
            ),
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
              ..color = AppColors.textePrimaire.withValues(
                alpha: opacity * 0.85,
              ),
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
