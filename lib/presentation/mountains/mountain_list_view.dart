import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_theme.dart';
import 'package:defi_kilimandjaro/presentation/hub/widgets/bottom_nav_bar.dart';
import 'package:defi_kilimandjaro/presentation/mountains/mountain_reveal_intent.dart';
import 'package:defi_kilimandjaro/presentation/mountains/widgets/altimeter_rail.dart';
import 'package:defi_kilimandjaro/presentation/mountains/widgets/atmosphere_layer.dart';
import 'package:defi_kilimandjaro/presentation/mountains/widgets/mountain_silhouette_vector.dart';
import 'package:defi_kilimandjaro/presentation/packs/widgets/active_pack_chip.dart';
import 'package:defi_kilimandjaro/presentation/theme/pack_motif_painter.dart';
import 'package:defi_kilimandjaro/presentation/theme/pack_theme_provider.dart';
import 'package:defi_kilimandjaro/presentation/widgets/flag_roundel.dart';
import 'package:defi_kilimandjaro/presentation/widgets/mountain_hero_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Marge horizontale de la carte sommet dans chaque page (cf. maquette
/// « peakcard »). Sert aussi à aligner l'overlay altimètre sur le bord
/// droit intérieur de la carte.
const double _kCardMarginH = 16;

/// Padding de chaque page autour de la carte (haut/bas réduits pour laisser
/// respirer header & nav). L'altimètre overlay se cale sur ces valeurs.
const EdgeInsets _kCardPad = EdgeInsets.fromLTRB(
  _kCardMarginH,
  6,
  _kCardMarginH,
  12,
);

/// Écran "Sommets" — ascension visuelle en carte des 52 sommets africains.
///
/// Header « Sommets · rang/total » + carte « peakcard » bordée par sommet
/// (scène biome, infos, étoiles, CTA) + altimètre intégré au bord droit.
/// PageView vertical snap : page 0 = Red Rocks (le plus bas), page 51 =
/// Kilimandjaro. Le scroll vers le haut fait "monter" le joueur ; l'altimètre
/// reste un scrubber alternatif.
class MountainListView extends ConsumerStatefulWidget {
  const MountainListView({this.revealIntent, super.key});

  /// Si non-null, déclenche l'animation d'ascension à l'entrée : se poser sur
  /// la montagne conquise puis scroller jusqu'à la suivante (cf.
  /// [MountainRevealIntent]). Null pour les entrées normales → jump-to-current.
  final MountainRevealIntent? revealIntent;

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

  // Séquence d'animation d'ascension (cf. widget.revealIntent) — one-shot.
  bool _revealSequenceDone = false;

  // Vrai pendant la séquence de reveal (pause + scroll) : affiche l'overlay
  // de skip et l'indice « Toucher pour passer ».
  bool _revealing = false;

  // Mis à vrai par un tap pendant le reveal → on saute directement à la cible.
  bool _revealSkipped = false;

  // Index cible du reveal (la nouvelle montagne), pour le skip immédiat.
  int? _revealToIdx;

  // Cache local des montagnes : `mountainsProvider` dépend de
  // `playerProgressProvider`, donc chaque fin de niveau invalide l'async et
  // repasse par `AsyncLoading`. Sans cache, le `.when(loading: ...)` démonte
  // le PageView et un nouveau s'attache au `PageController` neuf → retour
  // brutal à la page 0. Garder la dernière `data` connue évite le démontage.
  List<Mountain>? _cachedMountains;

  // Dernière page snappée — utilisé pour ne déclencher l'haptic qu'au
  // franchissement d'une frontière de page (pas pendant le glissement).
  int _lastSnappedPage = 0;

  // Vrai pendant qu'un drag sur l'altimètre pilote le scroll : on coupe
  // l'haptic snap pour éviter une rafale de clics pendant le scrub.
  bool _altimeterScrubbing = false;

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

  @override
  void didUpdateWidget(MountainListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // go_router RÉUTILISE cette instance d'écran à chaque conquête (la page
    // /mountains reste la racine de la pile). Sans ce réarmement, le one-shot
    // `_revealSequenceDone` resterait à true après le 1er reveal → les reveals
    // suivants seraient ignorés et le joueur resterait sur la montagne qu'il
    // vient de finir. Dès qu'un NOUVEAU revealIntent arrive, on réarme : le
    // post-frame du build suivant relancera _runRevealSequence.
    final intent = widget.revealIntent;
    if (intent != null && !identical(intent, oldWidget.revealIntent)) {
      _revealSequenceDone = false;
      _revealSkipped = false;
    }
  }

  void _onPageScroll() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page ?? 0;
    final snapped = page.round();
    if (snapped != _lastSnappedPage && !_altimeterScrubbing) {
      _lastSnappedPage = snapped;
      HapticFeedback.selectionClick();
    }
    setState(() {
      _pagePosition = page;
    });
  }

  /// Saute (sans animation) à un index — pilote du drag altimètre.
  void _jumpToIndex(int idx) {
    if (!_pageController.hasClients) return;
    _altimeterScrubbing = true;
    _pageController.jumpToPage(idx);
    // Reset asynchrone : le scroll callback va encore tirer une fois après
    // ce jump, on évite de bruiter l'haptic.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _altimeterScrubbing = false;
      _lastSnappedPage = idx;
    });
  }

  /// Anime vers un index — utilisé pour le retap onglet "Sommets" (450 ms par
  /// défaut) et pour le reveal d'ascension (durée proportionnelle à la
  /// distance, cf. [_runRevealSequence]).
  Future<void> _animateToIndex(int idx, {Duration? duration}) async {
    if (!_pageController.hasClients) return;
    await _pageController.animateToPage(
      idx,
      duration: duration ?? const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  /// Séquence d'animation d'ascension après une conquête : se pose sur la
  /// montagne conquise (`fromId`), marque une pause, puis scrolle jusqu'à la
  /// nouvelle montagne (`toId`). Skippable par un tap (cf. [_skipReveal]).
  /// One-shot via [_revealSequenceDone].
  Future<void> _runRevealSequence(List<Mountain> mountains) async {
    if (_revealSequenceDone) return;
    if (!_pageController.hasClients) return;
    final intent = widget.revealIntent;
    if (intent == null) return;
    final fromIdx = mountains.indexWhere((m) => m.id == intent.fromId);
    final toIdx = mountains.indexWhere((m) => m.id == intent.toId);
    if (fromIdx < 0 || toIdx < 0) {
      // Ids introuvables → fallback positionnement courant.
      _jumpToCurrentMountain(mountains);
      return;
    }
    _revealSequenceDone = true;
    // Supprime le jump-to-current concurrent (sinon il viserait directement la
    // nouvelle montagne et on ne verrait jamais le sommet conquis d'abord).
    _initialJumpDone = true;
    _revealToIdx = toIdx;

    _pageController.jumpToPage(fromIdx);
    setState(() => _revealing = true);

    // Pause : laisse le joueur reconnaître le sommet qu'il vient de gravir.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted || _revealSkipped || !_pageController.hasClients) {
      if (mounted && _revealing) setState(() => _revealing = false);
      return;
    }

    // Scroll animé vers la nouvelle montagne — durée ∝ distance (clampée).
    final distance = (toIdx - fromIdx).abs();
    final ms = (450 + 220 * distance).clamp(450, 1100);
    await _animateToIndex(toIdx, duration: Duration(milliseconds: ms));
    if (mounted && _revealing) setState(() => _revealing = false);
  }

  /// Saute immédiatement sur la nouvelle montagne (annule la séquence de
  /// reveal). Appelé par un tap sur l'overlay pendant l'animation.
  void _skipReveal() {
    final idx = _revealToIdx;
    if (idx == null) return;
    _revealSkipped = true;
    if (_pageController.hasClients) {
      // `jumpToPage` interrompt nativement un `animateToPage` en cours.
      _pageController.jumpToPage(idx);
    }
    setState(() => _revealing = false);
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
      // Distingue les deux causes possibles de verrou : star-gate (étoiles
      // manquantes) vs progression normale (sommet précédent). Le message
      // doit aider le joueur à comprendre ce qu'il doit faire ensuite —
      // rejouer ses niveaux à 1 ★ ou terminer le sommet courant.
      final String label;
      if (m.isStarGated) {
        label = 'mountains.locked_stargate_snackbar'.tr(
          namedArgs: <String, String>{
            'stars': (m.starsRequiredToUnlock ?? 0).toString(),
          },
        );
      } else {
        label = 'Termine le sommet précédent pour débloquer celui-ci';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(label, style: AppTypography.bebas()),
          backgroundColor: AppColors.boisFonce,
          duration: const Duration(milliseconds: 2400),
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
    final packTheme = ref.watch(activePackThemeProvider);
    // Cache local : on garde la dernière liste connue pour éviter de
    // démonter le PageView pendant un re-fetch (voir doc de _cachedMountains).
    if (asyncMountains.hasValue) {
      _cachedMountains = asyncMountains.value;
    }
    final mountains = _cachedMountains;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Builder(
          builder: (context) {
            if (asyncMountains.hasError && mountains == null) {
              return const _ErrorView();
            }
            if (mountains == null) {
              return const _LoadingView();
            }

            // Positionnement initial : reveal d'ascension si demandé (atterrir
            // sur le sommet conquis puis scroller vers le suivant), sinon jump
            // direct sur le sommet courant.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (widget.revealIntent != null && !_revealSequenceDone) {
                _runRevealSequence(mountains);
              } else {
                _jumpToCurrentMountain(mountains);
              }
            });

            final currentPage = _pagePosition.round().clamp(
              0,
              mountains.length - 1,
            );
            final interpolatedAlt = _interpolatedAltitude(mountains);
            final bestAlt = _bestAltitude(mountains);
            final currentIdx = _currentMountainIndex(mountains) ?? 0;
            final scrollFraction =
                _pagePosition / math.max(mountains.length - 1, 1);

            return Column(
              children: [
                // Header « Sommets · rang/total » + accès Mes packs.
                _SommetsHeader(
                  rank: currentPage + 1,
                  total: mountains.length,
                  mountains: mountains,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      // PageView principal — 1 montagne = 1 carte.
                      PageView.builder(
                        controller: _pageController,
                        scrollDirection: Axis.vertical,
                        itemCount: mountains.length,
                        itemBuilder: (context, index) {
                          final m = mountains[index];
                          return RepaintBoundary(
                            child: _MountainPage(
                              mountain: m,
                              rank: index + 1,
                              isCurrentTarget: index == currentIdx,
                              pulseAnim: _pulseAnim,
                              scrollFraction: scrollFraction,
                              packTheme: packTheme,
                              onTap: () => _onMountainTap(m),
                            ),
                          );
                        },
                      ),

                      // Altimètre — aligné sur le bord droit intérieur de la
                      // carte (scrubber alternatif au swipe vertical).
                      Positioned(
                        right: _kCardMarginH + 6,
                        top: _kCardPad.top + 54,
                        bottom: _kCardPad.bottom + 104,
                        child: AltimeterRail(
                          currentAltitude: interpolatedAlt,
                          bestAltitude: bestAlt,
                          mountains: mountains,
                          onSeekToIndex: _jumpToIndex,
                        ),
                      ),

                      // Skip discret du reveal d'ascension : tap n'importe où
                      // → saut direct sur la nouvelle montagne. N'existe que
                      // pendant la séquence (n'interfère pas avec le tap normal
                      // pour ouvrir le détail d'une montagne).
                      if (_revealing)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _skipReveal,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 24),
                                child: Text(
                                  'mountains.tap_to_skip'.tr(),
                                  style: AppTypography.labelXs.copyWith(
                                    color: AppColors.texteTertiaire,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: NavTab.sommets,
        onTabSelected: (t) {
          switch (t) {
            case NavTab.accueil:
              context.go(AppRoutes.home);
            case NavTab.defi:
              context.go(AppRoutes.hub);
            case NavTab.sommets:
              // Retap sur l'onglet courant → recentrer sur le sommet
              // à conquérir (pattern iOS). Silencieux si la liste n'est
              // pas encore chargée.
              final ms = _cachedMountains;
              if (ms != null) {
                final idx = _currentMountainIndex(ms) ?? 0;
                _animateToIndex(idx);
              }
            case NavTab.packs:
              context.go(AppRoutes.myPacks);
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
    required this.scrollFraction,
    required this.onTap,
    this.packTheme = PackThemes.defaultTheme,
  });

  final Mountain mountain;
  final int rank;
  final bool isCurrentTarget;
  final Animation<double> pulseAnim;

  /// Skin du pack actif — teinte l'ambiance (gradients de biome) et pose un
  /// motif culturel léger sur la carte. Défaut = ambiance historique pure.
  final PackTheme packTheme;
  final double scrollFraction;
  final VoidCallback onTap;

  bool get _isCompleted =>
      mountain.completedLevels >= mountain.totalLevels &&
      mountain.totalLevels > 0;

  @override
  Widget build(BuildContext context) {
    final biome = biomeForAltitude(mountain.altitude);

    return Padding(
      padding: _kCardPad,
      child: DecoratedBox(
        // Élévation maquette : surface opaque + bordure hairline + une seule
        // ombre noire diffuse (pas de glow coloré).
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Scène : ciel biome + nuages parallax (clippés dans la carte).
              Positioned.fill(
                child: AtmosphereLayer(
                  biome: biome,
                  tint: packTheme.sommetsTint,
                ),
              ),
              Positioned.fill(
                child: ParallaxBgLayer(
                  scrollFraction: scrollFraction,
                  biome: biome,
                ),
              ),
              // Motif culturel du pack en sur-couche très légère (identité
              // visuelle dédiée par pack). Aucun pour le thème par défaut.
              if (packTheme.motif != PackMotif.none)
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: PackMotifPainter(
                          motif: packTheme.motif,
                          color:
                              (packTheme.motifColor ??
                                      packTheme.sommetsTint ??
                                      packTheme.accent)
                                  .withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                  ),
                ),

              // 2. Sommet peint (hero PNG) + halo pulsé sur le sommet courant.
              // Repli : silhouette vectorielle si l'asset hero manque.
              Positioned(
                left: 0,
                right: 0,
                top: 48,
                bottom: 108,
                child: AnimatedBuilder(
                  animation: pulseAnim,
                  builder: (context, child) {
                    final showPulse = isCurrentTarget && !_isCompleted;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (showPulse)
                          Center(
                            child: Transform.scale(
                              scale: 0.92 + 0.14 * pulseAnim.value,
                              child: SizedBox(
                                width: 200,
                                height: 200,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        AppColors.orJour.withValues(
                                          alpha: 0.18 * pulseAnim.value,
                                        ),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        child!,
                      ],
                    );
                  },
                  child: MountainHeroImage(
                    mountainId: mountain.id,
                    alignment: Alignment.bottomCenter,
                    fallback: MountainSilhouetteVector(mountain: mountain),
                  ),
                ),
              ),

              // 3. Dégradé bas (scenefade) : fond vers la surface pour la
              // lisibilité des étoiles / altitude / CTA.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 150,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.surface.withValues(alpha: 0),
                        AppColors.surface,
                      ],
                      stops: const [0, 0.86],
                    ),
                  ),
                ),
              ),

              // 4. Infos : topinfo (nom + progression) en haut, botinfo
              // (étoiles + altitude + CTA) en bas.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    _NameHeader(mountain: mountain),
                    const Spacer(),
                    _ProgressFooter(
                      mountain: mountain,
                      isCompleted: _isCompleted,
                      onTap: onTap,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Header de l'écran Sommets
// ============================================================

/// Barre supérieure : titre « Sommets », accès « Mes packs » (sinon route
/// orpheline) et puce « rang / total » alignée à droite (cf. maquette).
class _SommetsHeader extends StatelessWidget {
  const _SommetsHeader({
    required this.rank,
    required this.total,
    required this.mountains,
  });

  final int rank;
  final int total;
  final List<Mountain> mountains;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 6),
      child: Row(
        children: [
          Text('Sommets', style: AppTypography.headingMd),
          const Spacer(),
          // Chip « pack actif » : indique la grimpe courante (la carte affiche
          // la progression du pack actif) et ouvre « Mes packs » au tap.
          const Flexible(child: ActivePackChip()),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Text(
              '$rank / $total',
              style: AppTypography.labelSm.copyWith(
                color: AppColors.texteSecondaire,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
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
          FlagRoundel(countryCode: mountain.countryCode, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mountain.name.toUpperCase(),
                  style: AppTypography.bebas(size: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  mountain.countryName,
                  style: AppTypography.crimson(
                    size: 12,
                    style: FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Text(
              'Niv. ${mountain.completedLevels}/${mountain.totalLevels}',
              style: AppTypography.labelXs.copyWith(
                color: AppColors.textePrimaire,
                fontWeight: FontWeight.w700,
              ),
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
            style: AppTypography.displayLg.copyWith(
              fontSize: 46,
              color: AppColors.textePrimaire,
            ),
          ),
          TextSpan(
            text: ' m',
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.texteSecondaire,
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
          const SizedBox(height: 8),
          // Altitude (Fraunces) + libellé de progression alignés en bas.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _AltitudeDisplay(altitude: mountain.altitude),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '${mountain.completedLevels}/${mountain.totalLevels} niveaux conquis',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.texteSecondaire,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Bouton CTA pleine largeur.
          _CtaButton(
            unlocked: unlocked,
            isCompleted: isCompleted,
            starsRequiredToUnlock: mountain.starsRequiredToUnlock,
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
    this.starsRequiredToUnlock,
  });

  final bool unlocked;
  final bool isCompleted;
  final VoidCallback onTap;

  /// Étoiles manquantes pour franchir la star-gate. Non-null **uniquement**
  /// quand la cause du verrou est la barrière étoiles (et non la
  /// progression normale). Quand renseigné, le label change pour orienter
  /// le joueur vers le replay des niveaux à 1 ★.
  final int? starsRequiredToUnlock;

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color textColor;
    final String label;

    final Color borderColor;
    if (!unlocked) {
      bgColor = AppColors.surface.withValues(alpha: 0.6);
      textColor = AppColors.texteTertiaire;
      borderColor = AppColors.hairline;
      final stars = starsRequiredToUnlock ?? 0;
      label = stars > 0
          ? 'mountains.locked_stargate_cta'.tr(
              namedArgs: <String, String>{'stars': stars.toString()},
            )
          : 'mountains.locked_progression_cta'.tr();
    } else if (isCompleted) {
      bgColor = AppColors.surface;
      textColor = AppColors.orJour;
      borderColor = AppColors.orJour.withValues(alpha: 0.5);
      label = 'GRAVIR À NOUVEAU';
    } else {
      bgColor = AppColors.orJour;
      textColor = AppColors.surface;
      borderColor = AppColors.orJour;
      label = 'GRAVIR';
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          label,
          style: AppTypography.headingMd.copyWith(color: textColor),
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
