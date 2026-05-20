import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/hub/widgets/bottom_nav_bar.dart';
import 'package:defi_kilimandjaro/presentation/mountains/widgets/altimeter_rail.dart';
import 'package:defi_kilimandjaro/presentation/mountains/widgets/atmosphere_layer.dart';
import 'package:defi_kilimandjaro/presentation/mountains/widgets/mountain_silhouette_vector.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran "Sommets" — ascension visuelle plein écran des 52 sommets africains.
///
/// PageView vertical snap : page 0 = Red Rocks (le plus bas), page 51 =
/// Kilimandjaro. Le scroll vers le haut fait "monter" le joueur.
/// Chaque page occupe exactement un viewport — expérience d'élévation totale.
class MountainListView extends ConsumerStatefulWidget {
  const MountainListView({super.key});

  @override
  ConsumerState<MountainListView> createState() => _MountainListViewState();
}

class _MountainListViewState extends ConsumerState<MountainListView>
    with TickerProviderStateMixin {
  late final PageController _pageController;

  // Position courante du PageView — interpolée entre pages pendant le scroll.
  double _pagePosition = 0;

  // Contrôleur du halo pulsant sur le sommet actif.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  // Le jump initial vers la montagne en cours ne doit s'exécuter qu'une fois
  // par instance — sinon il interromprait le scroll de l'utilisateur à chaque
  // rebuild. Vérifier `_pageController.page == null` ne suffit pas : dès que
  // le PageView attache le controller, `page` vaut 0.0, jamais null.
  bool _initialJumpDone = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(_onPageScroll);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnim = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageController
      ..removeListener(_onPageScroll)
      ..dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onPageScroll() {
    if (_pageController.hasClients) {
      setState(() {
        _pagePosition = _pageController.page ?? 0;
      });
    }
  }

  /// Initialise le PageController sur le sommet courant (premier non-completed).
  /// One-shot par instance via [_initialJumpDone].
  void _jumpToCurrentMountain(List<Mountain> mountains) {
    if (_initialJumpDone) return;
    if (!_pageController.hasClients) return;
    final idx = _currentMountainIndex(mountains);
    if (idx == null) return;
    _pageController.jumpToPage(idx);
    _initialJumpDone = true;
  }

  /// Index du sommet courant (premier non-completed, ou 0).
  int? _currentMountainIndex(List<Mountain> mountains) {
    for (var i = 0; i < mountains.length; i++) {
      final m = mountains[i];
      if (m.unlocked && m.completedLevels < m.totalLevels) return i;
    }
    return 0;
  }

  Future<void> _onMountainTap(Mountain m) async {
    if (!m.unlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Termine le sommet précédent pour débloquer celui-ci',
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.boisFonce,
          duration: const Duration(milliseconds: 1800),
        ),
      );
      return;
    }
    await context.push<void>(AppRoutes.mountain, extra: m);
  }

  /// Altitude interpolée entre les deux pages adjacentes (pour altimètre fluide).
  double _interpolatedAltitude(List<Mountain> mountains) {
    if (mountains.isEmpty) return 0;
    final page = _pagePosition.clamp(0.0, mountains.length - 1.0);
    final lower = page.floor().clamp(0, mountains.length - 1);
    final upper = page.ceil().clamp(0, mountains.length - 1);
    if (lower == upper) return mountains[lower].altitude.toDouble();
    final t = page - lower;
    return mountains[lower].altitude * (1 - t) + mountains[upper].altitude * t;
  }

  /// Altitude du meilleur sommet conquis par le joueur.
  int _bestAltitude(List<Mountain> mountains) {
    var best = 0;
    for (final m in mountains) {
      if (m.completedLevels > 0 && m.altitude > best) best = m.altitude;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final asyncMountains = ref.watch(mountainsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: asyncMountains.when(
        loading: () => const _LoadingView(),
        error: (_, __) => const _ErrorView(),
        data: (mountains) {
          // Positionnement initial sur le sommet courant.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _jumpToCurrentMountain(mountains),
          );

          final currentPage = _pagePosition.round().clamp(
            0,
            mountains.length - 1,
          );
          final currentMountain = mountains[currentPage];
          final biome = biomeForAltitude(currentMountain.altitude);
          final interpolatedAlt = _interpolatedAltitude(mountains);
          final bestAlt = _bestAltitude(mountains);
          final currentIdx = _currentMountainIndex(mountains) ?? 0;

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Atmosphère animée (dégradé biome plein écran).
              Positioned.fill(child: AtmosphereLayer(biome: biome)),

              // 2. Nuages parallax animés — 3 couches stratifiées qui
              // dérivent horizontalement + déplacement vertical sur scroll.
              Positioned.fill(
                child: ParallaxBgLayer(
                  scrollFraction:
                      _pagePosition / math.max(mountains.length - 1, 1),
                  biome: biome,
                ),
              ),

              // 3. Scrim contextuel : dégradé sombre haut + bas pour
              // garantir la lisibilité du HUD sur les ciels clairs.
              const Positioned.fill(child: _HudScrim()),

              // 4. PageView principal — 1 montagne = 1 viewport.
              PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: mountains.length,
                itemBuilder: (context, index) {
                  final m = mountains[index];
                  final isCurrentTarget = index == currentIdx;
                  return RepaintBoundary(
                    child: _MountainPage(
                      mountain: m,
                      rank: index + 1,
                      isCurrentTarget: isCurrentTarget,
                      pulseAnim: _pulseAnim,
                      onTap: () => _onMountainTap(m),
                    ),
                  );
                },
              ),

              // 4. Altimètre rail droit.
              Positioned(
                right: 0,
                top: 60,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4, bottom: 80),
                    child: AltimeterRail(
                      currentAltitude: interpolatedAlt,
                      bestAltitude: bestAlt,
                    ),
                  ),
                ),
              ),

              // 5. Bouton "Mes packs" — coin supérieur droit (icon-only).
              // Libère l'espace pour le nom de la montagne en haut-gauche.
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: Semantics(
                    button: true,
                    label: 'my_packs.title'.tr(),
                    child: Material(
                      color: AppColors.surfaceContainer.withValues(alpha: 0.85),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => context.push(AppRoutes.myPacks),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.layers_outlined,
                            color: AppColors.orJour,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: NavTab.sommets,
        onTabSelected: (t) {
          switch (t) {
            case NavTab.defi:
              context.go(AppRoutes.hub);
            case NavTab.sommets:
              break;
            case NavTab.profil:
              context.go(AppRoutes.profile);
          }
        },
      ),
    );
  }
}

// ============================================================
// Page individuelle d'une montagne
// ============================================================

class _MountainPage extends StatelessWidget {
  const _MountainPage({
    required this.mountain,
    required this.rank,
    required this.isCurrentTarget,
    required this.pulseAnim,
    required this.onTap,
  });

  final Mountain mountain;
  final int rank;
  final bool isCurrentTarget;
  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  bool get _isCompleted =>
      mountain.completedLevels >= mountain.totalLevels &&
      mountain.totalLevels > 0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Silhouette FG — stripped SVG (transparent au-dessus de la
        // montagne) qui laisse passer AtmosphereLayer + nuages parallax.
        // Ancrée au bas de l'écran avec un haut réservé au HUD.
        Positioned(
          left: 0,
          right: 0,
          bottom: 96,
          top: size.height * 0.18,
          child: AnimatedBuilder(
            animation: pulseAnim,
            builder: (context, _) {
              return MountainSilhouetteVector(
                mountain: mountain,
                hasPulse: isCurrentTarget && !_isCompleted,
                pulseValue: pulseAnim.value,
              );
            },
          ),
        ),

        // HUD — informations de la montagne.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                _NameHeader(mountain: mountain),
                const SizedBox(height: 8),
                _AltitudeDisplay(altitude: mountain.altitude),
                const Spacer(),
                _ProgressFooter(
                  mountain: mountain,
                  isCompleted: _isCompleted,
                  onTap: onTap,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---- Sous-widgets HUD ----

class _NameHeader extends StatelessWidget {
  const _NameHeader({required this.mountain});
  final Mountain mountain;

  @override
  Widget build(BuildContext context) {
    final opacity = mountain.unlocked ? 1.0 : 0.45;
    return Opacity(
      opacity: opacity,
      child: Row(
        children: [
          Text(mountain.flagEmoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mountain.name.toUpperCase(),
              style: AppTypography.bebas(size: 18, letterSpacing: 3),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            mountain.countryName,
            style: AppTypography.crimson(
              size: 12,
              color: AppColors.texteSecondaire,
              style: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _AltitudeDisplay extends StatelessWidget {
  const _AltitudeDisplay({required this.altitude});
  final int altitude;

  @override
  Widget build(BuildContext context) {
    final formatted = _formatAltitude(altitude);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: formatted,
            style: AppTypography.bebas(size: 56, color: AppColors.orSoleil),
          ),
          TextSpan(
            text: ' m',
            style: AppTypography.bebas(
              size: 24,
              color: AppColors.orSoleil.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAltitude(int alt) {
    // Espace comme séparateur des milliers : "5 895"
    final s = alt.toString();
    if (s.length <= 3) return s;
    final rest = s.substring(0, s.length - 3);
    final last = s.substring(s.length - 3);
    return '$rest $last';
  }
}

class _ProgressFooter extends StatelessWidget {
  const _ProgressFooter({
    required this.mountain,
    required this.isCompleted,
    required this.onTap,
  });

  final Mountain mountain;
  final bool isCompleted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unlocked = mountain.unlocked;
    final footerOpacity = unlocked ? 1.0 : 0.50;

    return Opacity(
      opacity: footerOpacity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Étoiles de progression.
          _StarRow(
            completed: mountain.completedLevels,
            total: mountain.totalLevels,
          ),
          const SizedBox(height: 4),
          Text(
            '${mountain.completedLevels}/${mountain.totalLevels} niveaux conquis',
            style: AppTypography.crimson(
              size: 13,
              color: AppColors.texteSecondaire,
            ),
          ),
          const SizedBox(height: 14),
          // Bouton CTA.
          _CtaButton(
            unlocked: unlocked,
            isCompleted: isCompleted,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow({required this.completed, required this.total});
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final filled = i < completed;
        return Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 18,
            color: filled ? AppColors.orSoleil : AppColors.texteDisabled,
          ),
        );
      }),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.unlocked,
    required this.isCompleted,
    required this.onTap,
  });

  final bool unlocked;
  final bool isCompleted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color textColor;
    final String label;

    if (!unlocked) {
      bgColor = AppColors.boisFonce.withValues(alpha: 0.6);
      textColor = AppColors.texteTertiaire;
      label = 'TERMINE LE SOMMET PRÉCÉDENT';
    } else if (isCompleted) {
      bgColor = AppColors.vertClair.withValues(alpha: 0.25);
      textColor = AppColors.vertClair;
      label = 'GRAVIR À NOUVEAU';
    } else {
      bgColor = AppColors.orSoleil;
      textColor = AppColors.boisFonce;
      label = 'GRAVIR';
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: unlocked
                ? (isCompleted ? AppColors.vertClair : AppColors.orChaud)
                : AppColors.boisFonce,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.bebas(size: 15, color: textColor),
        ),
      ),
    );
  }
}

// ============================================================
// Scrim HUD — dégradé vertical sombre sur les bords haut/bas
// ============================================================

/// Voile sombre sur les 22 % du haut et 30 % du bas de l'écran, transparent
/// au milieu. Garantit le contraste du HUD (nom, altitude, étoiles, CTA)
/// sur les biomes clairs (savanne, altitude), sans dénaturer l'atmosphère
/// au centre de la composition.
///
/// `IgnorePointer` : laisse passer les taps vers les widgets sous-jacents.
class _HudScrim extends StatelessWidget {
  const _HudScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x99000000), // 60 % black — derrière nom + altitude
              Color(0x00000000), // transparent
              Color(0x00000000), // transparent
              Color(0xB3000000), // 70 % black — derrière étoiles + CTA
            ],
            stops: [0.0, 0.22, 0.62, 1.0],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// États de chargement / erreur
// ============================================================

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.vertForet, Color(0xFF0D2510)],
        ),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.orSoleil),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.vertForet,
      child: Center(
        child: Text(
          'Impossible de charger les sommets',
          style: AppTypography.crimson(color: AppColors.rouge),
        ),
      ),
    );
  }
}
