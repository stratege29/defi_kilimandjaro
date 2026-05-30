import 'dart:math';

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/core/utils/level_difficulty_resolver.dart';
import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/services/devinette_selection_service_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/mountains/widgets/mountain_silhouette_vector.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:defi_kilimandjaro/presentation/widgets/flag_roundel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran 07 — Détail d'une montagne (cf. maquette p.9).
///
/// Vue d'ascension : niveaux en zigzag sur le flanc, fond peint
/// (ciel étoilé + montagne + neige), zones nommées, scroll bottom→top.
class MountainDetailView extends ConsumerStatefulWidget {
  const MountainDetailView({required this.mountain, super.key});

  final Mountain mountain;

  @override
  ConsumerState<MountainDetailView> createState() => _MountainDetailViewState();
}

class _MountainDetailViewState extends ConsumerState<MountainDetailView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _onLevelTap(int levelNumber) async {
    final liveMountain = ref
        .read(mountainsProvider)
        .maybeWhen(
          data: (list) => list.firstWhere(
            (m) => m.id == widget.mountain.id,
            orElse: () => widget.mountain,
          ),
          orElse: () => widget.mountain,
        );

    final isUnlockedLevel = levelNumber <= liveMountain.completedLevels + 1;
    if (!isUnlockedLevel) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Termine le niveau ${levelNumber - 1} pour débloquer',
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.boisFonce,
          duration: const Duration(milliseconds: 1500),
        ),
      );
      return;
    }

    try {
      final selectionService = ref.read(devinetteSelectionServiceProvider);
      final progress = ref.read(playerProgressProvider);
      final config = LevelDifficultyResolver.resolve(
        mountain: liveMountain,
        levelIndex: levelNumber,
      );
      final devinette = await selectionService.nextDevinette(
        mix: progress.activePackMix,
        targetDifficulty: config.difficultyTier,
        wordLengthBucket: config.wordLengthBucket,
        excludeIds: progress.recentDevinetteIds.toSet(),
      );
      await ref
          .read(playerProgressProvider.notifier)
          .recordRecentDevinette(devinette.id);
      if (!mounted) return;
      await context.push<void>(
        AppRoutes.game,
        extra: GameArgs(
          devinette: devinette,
          mountainId: widget.mountain.id,
          levelIndex: levelNumber,
          config: config,
        ),
      );
    } on Exception catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur de chargement', style: AppTypography.bebas()),
          backgroundColor: AppColors.rouge,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncMountains = ref.watch(mountainsProvider);
    final progress = ref.watch(playerProgressProvider);

    // Live mountain (avec completedLevels à jour) si dispo, sinon fallback.
    final mountain = asyncMountains.maybeWhen(
      data: (list) => list.firstWhere(
        (m) => m.id == widget.mountain.id,
        orElse: () => widget.mountain,
      ),
      orElse: () => widget.mountain,
    );

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Ciel nocturne + étoiles (gradient bleu nuit → vert forêt).
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => CustomPaint(
              painter: _NightSkyPainter(
                pulse: _pulseCtrl.value,
                seedNumber: mountain.altitude,
              ),
            ),
          ),
          // 2. Silhouette réelle de la montagne (le même SVG que l'écran
          // Sommets). BoxFit.cover pour remplir verticalement l'écran et
          // donner sa juste place visuelle au sommet, même quand il est bas
          // (Red Rocks 53 m, Kediet, mesas...).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            top: 64,
            child: MountainSilhouetteVector(
              mountain: mountain,
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _Header(mountain: mountain, cauris: progress.cauris),
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, constraints) {
                      // Map levelIndex (1-based) → étoiles gagnées pour
                      // cette montagne. Le provider est déjà watché plus
                      // haut via `progress`, pas de double-subscribe.
                      final stars = <int, int>{
                        for (var i = 1; i <= mountain.totalLevels; i++)
                          if (progress.starsOnLevel(
                                mountainId: mountain.id,
                                levelIndex: i,
                              ) >
                              0)
                            i: progress.starsOnLevel(
                              mountainId: mountain.id,
                              levelIndex: i,
                            ),
                      };
                      return _LevelsLayer(
                        mountain: mountain,
                        size: constraints.biggest,
                        pulse: _pulseCtrl,
                        onLevelTap: _onLevelTap,
                        starsByLevel: stars,
                      );
                    },
                  ),
                ),
                _Footer(mountain: mountain),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — back arrow + flag + name + altitude + cauris
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.mountain, required this.cauris});
  final Mountain mountain;
  final int cauris;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(color: AppColors.orSoleil.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: AppColors.orSoleil,
            onPressed: () => context.pop(),
            tooltip: 'Retour',
          ),
          FlagRoundel(countryCode: mountain.countryCode, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mountain.name,
                  style: AppTypography.bebas(),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${mountain.countryName} · ${mountain.altitude} m',
                  style: AppTypography.crimson(
                    size: 12,
                    color: AppColors.texteSecondaire,
                    style: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.bois.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.orSoleil.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CaurisIcon(size: 16),
                const SizedBox(width: 4),
                Text(
                  '$cauris',
                  style: AppTypography.bebas(
                    size: 14,
                    color: AppColors.orSoleil,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Levels layer — zigzag positioned bullets + connecting dotted path
// ---------------------------------------------------------------------------

class _LevelsLayer extends StatelessWidget {
  const _LevelsLayer({
    required this.mountain,
    required this.size,
    required this.pulse,
    required this.onLevelTap,
    this.starsByLevel = const <int, int>{},
  });

  final Mountain mountain;
  final Size size;
  final AnimationController pulse;
  final ValueChanged<int> onLevelTap;

  /// Étoiles gagnées par niveau (levelIndex 1-based → 0..3). Niveaux non
  /// joués absents de la map. Affichés en mini-row sous chaque bullet.
  final Map<int, int> starsByLevel;

  /// Calcule la position (Offset) du centre de la boule du niveau (1-N).
  ///
  /// `padTop` est ajusté à l'altitude du sommet pour que le zigzag suive
  /// approximativement la silhouette : un sommet bas (Red Rocks 53 m,
  /// mesa) confine les bullets au tiers inférieur ; un sommet haut
  /// (Kilimandjaro 5895 m) les étale sur toute la hauteur de l'écran.
  Offset _positionOf(int levelNumber, int totalLevels) {
    // Map altitude (50 → 5900 m) en fraction padTop (0.65 → 0.25).
    // Calibré pour que le bullet du sommet atterrisse juste au-dessus de
    // la silhouette : sommets bas (Red Rocks 53 m) ont leur top-bullet
    // à 65 % de la hauteur (juste sur la mesa), sommets hauts
    // (Kilimandjaro 5895 m) à 25 % (sur l'épaule du pic).
    final altClamped = mountain.altitude.toDouble().clamp(50.0, 5900.0);
    final altT = (altClamped - 50) / 5850;
    final padTopFraction = 0.65 - altT * 0.40;
    final padTop = size.height * padTopFraction;
    final padBottom = size.height * 0.12;
    final usable = size.height - padTop - padBottom;
    // Niveau 1 en bas, niveau N en haut → metaphor d'ascension.
    final t = (levelNumber - 1) / (totalLevels - 1).clamp(1, double.infinity);
    final y = (size.height - padBottom) - (usable * t);
    final isLeft = levelNumber.isOdd;
    final x = isLeft ? size.width * 0.32 : size.width * 0.68;
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final totalLevels = mountain.totalLevels;
    final completed = mountain.completedLevels;

    final positions = <Offset>[
      for (var i = 1; i <= totalLevels; i++) _positionOf(i, totalLevels),
    ];

    return Stack(
      children: [
        // Path dotted entre les niveaux.
        CustomPaint(
          size: size,
          painter: _PathPainter(positions: positions),
        ),
        // Boules niveaux.
        for (var i = 0; i < totalLevels; i++)
          Positioned(
            left: positions[i].dx - 32,
            top: positions[i].dy - 32,
            child: _LevelBullet(
              levelNumber: i + 1,
              status: i + 1 <= completed
                  ? _BulletStatus.completed
                  : i + 1 == completed + 1 && mountain.unlocked
                  ? _BulletStatus.current
                  : _BulletStatus.locked,
              pulse: pulse,
              starsEarned: starsByLevel[i + 1] ?? 0,
              isBoss: i + 1 == mountain.totalLevels,
              onTap: () => onLevelTap(i + 1),
            ),
          ),
        // Labels zones.
        for (final z in _zonesFor(totalLevels))
          Positioned(
            left: 12,
            top: positions[z.levelIndex].dy - 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                z.name,
                style: AppTypography.crimson(
                  size: 11,
                  color: AppColors.textePrimaire,
                  style: FontStyle.italic,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Zone {
  const _Zone(this.name, this.levelIndex);
  final String name;
  final int levelIndex;
}

List<_Zone> _zonesFor(int total) {
  if (total <= 4) {
    return [
      const _Zone('Base', 0),
      _Zone('Forêt sacrée', total ~/ 3),
      _Zone('Brumes', (total * 2) ~/ 3),
      _Zone('Sommet', total - 1),
    ];
  }
  return [
    const _Zone('Base', 0),
    _Zone('Forêt sacrée', total ~/ 5),
    _Zone('Brumes', (total * 2) ~/ 5),
    _Zone('Glaciers', (total * 3) ~/ 5),
    _Zone('Nuages mythiques', (total * 4) ~/ 5),
    _Zone('Sommet', total - 1),
  ];
}

// ---------------------------------------------------------------------------
// Level bullet
// ---------------------------------------------------------------------------

enum _BulletStatus { completed, current, locked }

class _LevelBullet extends StatelessWidget {
  const _LevelBullet({
    required this.levelNumber,
    required this.status,
    required this.pulse,
    required this.onTap,
    this.starsEarned = 0,
    this.isBoss = false,
  });

  final int levelNumber;
  final _BulletStatus status;
  final AnimationController pulse;
  final VoidCallback onTap;

  /// Étoiles obtenues sur ce niveau (0-3). Quand > 0, affiche une mini-row
  /// d'étoiles dorées sous le bullet pour signaler la performance.
  final int starsEarned;

  /// Niveau boss (dernier de la montagne). Décoré d'une couronne dorée
  /// au-dessus du bullet pour signaler la signature visuelle.
  final bool isBoss;

  Color get _bg {
    switch (status) {
      case _BulletStatus.completed:
        return AppColors.vertClair;
      case _BulletStatus.current:
        return AppColors.orSoleil;
      case _BulletStatus.locked:
        return Colors.white.withValues(alpha: 0.15);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bullet = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _bg,
          border: Border.all(
            color: status == _BulletStatus.locked
                ? Colors.white.withValues(alpha: 0.25)
                : AppColors.orSoleil.withValues(alpha: 0.85),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: switch (status) {
            _BulletStatus.completed => const Icon(
              Icons.check,
              color: AppColors.vertForet,
              size: 26,
            ),
            _BulletStatus.current => Text(
              '$levelNumber',
              style: AppTypography.bebas(size: 22, color: AppColors.vertForet),
            ),
            _BulletStatus.locked => Image.asset(
              AppAssets.iconLock,
              width: 26,
              height: 26,
            ),
          },
        ),
      ),
    );

    // Couronne dorée flottante au-dessus du bullet pour les boss
    // (dernier niveau de la montagne). Signature visuelle distincte
    // pour anticiper le combat clé.
    Widget bulletDecorated = bullet;
    if (isBoss) {
      bulletDecorated = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: <Widget>[
          bullet,
          Positioned(
            top: -16,
            child: Icon(
              Icons.workspace_premium_rounded,
              size: 22,
              color: AppColors.orJour,
              shadows: <Shadow>[
                Shadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Mini-row d'étoiles affichée sous le bullet pour les niveaux où le
    // joueur a déjà obtenu au moins 1 étoile (toujours vrai post-victoire).
    var bulletWithStars = bulletDecorated;
    if (starsEarned > 0) {
      bulletWithStars = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          bulletDecorated,
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 1; i <= 3; i++) ...<Widget>[
                if (i > 1) const SizedBox(width: 1),
                Icon(
                  i <= starsEarned
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 12,
                  color: i <= starsEarned
                      ? AppColors.orJour
                      : Colors.white.withValues(alpha: 0.3),
                ),
              ],
            ],
          ),
        ],
      );
    }

    if (status != _BulletStatus.current) return bulletWithStars;

    // Halo pulsant pour le niveau courant — entoure uniquement le bullet,
    // pas la row d'étoiles.
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) {
        final scale = 1 + pulse.value * 0.18;
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: scale,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.orSoleil.withValues(
                    alpha: 0.25 * (1 - pulse.value),
                  ),
                ),
              ),
            ),
            bulletWithStars,
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Footer — current zone name + global progress bar
// ---------------------------------------------------------------------------

class _Footer extends StatelessWidget {
  const _Footer({required this.mountain});
  final Mountain mountain;

  @override
  Widget build(BuildContext context) {
    final zones = _zonesFor(mountain.totalLevels);
    final currentLevelIndex = mountain.completedLevels.clamp(
      0,
      mountain.totalLevels - 1,
    );
    final currentZone = zones.lastWhere(
      (z) => z.levelIndex <= currentLevelIndex,
      orElse: () => zones.first,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        border: Border(
          top: BorderSide(color: AppColors.orSoleil.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Zone ${zones.indexOf(currentZone) + 1} · ${currentZone.name}',
            style: AppTypography.bebas(size: 14, color: AppColors.orSoleil),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: mountain.progress,
              minHeight: 6,
              backgroundColor: AppColors.boisFonce.withValues(alpha: 0.5),
              valueColor: const AlwaysStoppedAnimation(AppColors.vertClair),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${mountain.completedLevels} / ${mountain.totalLevels} niveaux',
            style: AppTypography.crimson(
              size: 12,
              color: AppColors.texteSecondaire,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Night sky painter — gradient nuit + étoiles déterministes
// ---------------------------------------------------------------------------

class _NightSkyPainter extends CustomPainter {
  _NightSkyPainter({required this.pulse, required this.seedNumber});

  /// Animation pulse 0..1 (preserved hook si on veut ré-introduire des
  /// nuages pulsants ou un twinkle au sommet plus tard).
  final double pulse;

  /// Seed déterministe pour le placement des étoiles (= altitude du sommet
  /// → même montagne = même ciel, à chaque visite).
  final int seedNumber;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seedNumber);

    // Sky gradient nuit → forêt.
    final skyRect = Offset.zero & size;
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A1623), AppColors.vertForet],
        ).createShader(skyRect),
    );

    // 35 étoiles dans le tiers supérieur (déterministes via seed).
    final starPaint = Paint()..color = AppColors.texteSecondaire;
    for (var i = 0; i < 35; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height * 0.55;
      final r = 0.8 + rng.nextDouble() * 1.4;
      canvas.drawCircle(Offset(x, y), r, starPaint);
    }
  }

  @override
  bool shouldRepaint(_NightSkyPainter old) =>
      old.pulse != pulse || old.seedNumber != seedNumber;
}

// ---------------------------------------------------------------------------
// Dotted path between consecutive level bullets
// ---------------------------------------------------------------------------

class _PathPainter extends CustomPainter {
  _PathPainter({required this.positions});

  final List<Offset> positions;

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.length < 2) return;

    final paint = Paint()
      ..color = AppColors.orSoleil.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < positions.length - 1; i++) {
      _drawDashedLine(canvas, positions[i], positions[i + 1], paint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashLen = 6.0;
    const gapLen = 6.0;
    final delta = b - a;
    final distance = delta.distance;
    final dir = delta / distance;
    var traveled = 0.0;
    while (traveled < distance) {
      final start = a + dir * traveled;
      final end = a + dir * (traveled + dashLen).clamp(0, distance);
      canvas.drawLine(start, end, paint);
      traveled += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(_PathPainter oldDelegate) =>
      oldDelegate.positions != positions;
}
