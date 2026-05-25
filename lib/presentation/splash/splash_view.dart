import 'dart:async';

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/presentation/onboarding/onboarding_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran 01 — Splash Screen.
///
/// Cf. maquette p.3 :
/// - Logo "K" centré (Playfair Display, or)
/// - Nom KILIMANDJARO sous le logo
/// - Tagline "Sagesse Ivoirienne" en italique bois clair
/// - Cercles concentriques animés (motifs Adinkra)
/// - Indicateur de chargement pulsant (vert clair)
/// - Auto-transition vers /hub après 2.5s
class SplashView extends ConsumerStatefulWidget {
  const SplashView({super.key});

  @override
  ConsumerState<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends ConsumerState<SplashView>
    with TickerProviderStateMixin {
  late final AnimationController _ringsCtrl;
  late final AnimationController _pulseCtrl;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _ringsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Auto-transition après 2.5s vers Onboarding (1er lancement) ou Hub.
    _navTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      final prefs = ref.read(sharedPreferencesProvider);
      final destination = isOnboardingSeen(prefs)
          ? AppRoutes.home
          : AppRoutes.onboarding;
      context.go(destination);
    });
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _ringsCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            // Cercles concentriques animés (taille fixe centrée)
            Center(
              child: AnimatedBuilder(
                animation: _ringsCtrl,
                builder: (_, __) => CustomPaint(
                  size: const Size.square(320),
                  painter: _ConcentricRingsPainter(progress: _ringsCtrl.value),
                ),
              ),
            ),
            // Logo central — PNG stylé (cohérent avec le native splash).
            // Pas de Text('K') ici : on conserve l'identité visuelle du
            // logo design tout au long du démarrage (zéro flash de
            // transition entre native splash et SplashView Flutter).
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  AppAssets.logoK,
                  width: 140,
                  height: 140,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 12),
                Text('KILIMANDJARO', style: AppTypography.logoTitle),
                const SizedBox(height: 6),
                Text(
                  'Sagesse Ivoirienne',
                  style: AppTypography.taglineItalic(),
                ),
              ],
            ),
            // Pulsant en bas
            Positioned(
              bottom: 80,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.8, end: 1.2).animate(
                  CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
                ),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: AppColors.vertClair,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cercles concentriques évoquant les motifs Adinkra.
class _ConcentricRingsPainter extends CustomPainter {
  _ConcentricRingsPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide / 2;

    for (var i = 0; i < 4; i++) {
      final phase = (progress + i * 0.25) % 1;
      final radius = maxRadius * phase;
      final opacity = (1 - phase).clamp(0.0, 1.0) * 0.6;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.orSoleil.withValues(alpha: opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ConcentricRingsPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
