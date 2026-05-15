import 'dart:math';

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/devinette_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
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
      final repo = ref.read(devinetteRepositoryProvider);
      // Phase 2.2 stub : devinette aléatoire de "village_des_or" (seul peuplé).
      // Phase 4 : tag par pays / région.
      // Anti-répétition : exclut les 5 dernières devinettes jouées.
      final progress = ref.read(playerProgressProvider);
      final devinette = await repo.randomFromWorldExcluding(
        'village_des_or',
        progress.recentDevinetteIds,
      );
      await ref
          .read(playerProgressProvider.notifier)
          .recordRecentDevinette(devinette.id);
      if (!mounted) return;
      await context.push<void>(
        AppRoutes.game,
        extra: GameArgs(devinette: devinette, mountainId: widget.mountain.id),
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
          // Fond peint (ciel + montagne + neige + nuages pulsants).
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => CustomPaint(
              painter: _MountainBackgroundPainter(
                pulse: _pulseCtrl.value,
                seedNumber: mountain.altitude,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _Header(mountain: mountain, cauris: progress.cauris),
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, constraints) {
                      return _LevelsLayer(
                        mountain: mountain,
                        size: constraints.biggest,
                        pulse: _pulseCtrl,
                        onLevelTap: _onLevelTap,
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
          Text(mountain.flagEmoji, style: const TextStyle(fontSize: 22)),
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
  });

  final Mountain mountain;
  final Size size;
  final AnimationController pulse;
  final ValueChanged<int> onLevelTap;

  /// Calcule la position (Offset) du centre de la boule du niveau (1-N).
  Offset _positionOf(int levelNumber, int totalLevels) {
    final padTop = size.height * 0.08;
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
  });

  final int levelNumber;
  final _BulletStatus status;
  final AnimationController pulse;
  final VoidCallback onTap;

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

    if (status != _BulletStatus.current) return bullet;

    // Halo pulsant pour le niveau courant.
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
            bullet,
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
// Background painter — sky gradient + stars + mountain + snow + clouds
// ---------------------------------------------------------------------------

class _MountainBackgroundPainter extends CustomPainter {
  _MountainBackgroundPainter({required this.pulse, required this.seedNumber});

  final double pulse;
  final int seedNumber;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seedNumber);

    // Sky gradient.
    final skyRect = Offset.zero & size;
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0A1623), // dark night blue
            AppColors.vertForet,
          ],
        ).createShader(skyRect),
    );

    // Stars (~30 small white dots, deterministic).
    final starPaint = Paint()..color = AppColors.texteSecondaire;
    for (var i = 0; i < 35; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height * 0.55;
      final r = 0.8 + rng.nextDouble() * 1.4;
      canvas.drawCircle(Offset(x, y), r, starPaint);
    }

    // Mountain silhouette (large triangle filling lower 80% width).
    final centerX = size.width / 2;
    final mtnTopY = size.height * 0.18;
    final mtnBaseY = size.height;
    final mtnPath = Path()
      ..moveTo(centerX, mtnTopY)
      ..lineTo(size.width * 1.25, mtnBaseY)
      ..lineTo(-size.width * 0.25, mtnBaseY)
      ..close();
    final mtnRect = Rect.fromLTWH(0, mtnTopY, size.width, mtnBaseY - mtnTopY);
    canvas.drawPath(
      mtnPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.boisFonce, Color(0xFF3B2A14)],
        ).createShader(mtnRect),
    );

    // Snow cap (smaller white triangle at top).
    final snowH = size.height * 0.08;
    final snowPath = Path()
      ..moveTo(centerX, mtnTopY)
      ..lineTo(centerX + size.width * 0.16, mtnTopY + snowH)
      ..lineTo(centerX - size.width * 0.16, mtnTopY + snowH)
      ..close();
    canvas.drawPath(snowPath, Paint()..color = AppColors.ivoire);

    // Soft snow stripes flowing down.
    final stripePaint = Paint()
      ..color = AppColors.texteDisabled
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < 6; i++) {
      final dx = (rng.nextDouble() - 0.5) * size.width * 0.28;
      final p = Path()
        ..moveTo(centerX + dx, mtnTopY + snowH)
        ..relativeQuadraticBezierTo(
          dx * 0.1,
          size.height * 0.04,
          dx * 0.4,
          size.height * 0.07,
        );
      canvas.drawPath(p, stripePaint);
    }

    // Pulsing clouds at the peak.
    final cloudY = mtnTopY - size.height * 0.02;
    for (var i = 0; i < 4; i++) {
      final dx = (i - 1.5) * 38;
      final radius = (16 + i * 4) * (1 + pulse * 0.12);
      canvas.drawCircle(
        Offset(centerX + dx, cloudY),
        radius,
        Paint()
          ..color = AppColors.ivoire.withValues(
            alpha: 0.10 + 0.06 * (1 - pulse),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_MountainBackgroundPainter oldDelegate) =>
      oldDelegate.pulse != pulse;
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
