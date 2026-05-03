import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Écran 01 — Splash Screen.
///
/// Cf. maquette p.3 :
/// - Logo "K" centré (Playfair Display, or)
/// - Nom KILIMANDJARO sous le logo
/// - Tagline "Sagesse Ivoirienne" en italique bois clair
/// - Cercles concentriques animés (motifs Adinkra)
/// - Indicateur de chargement pulsant (vert clair)
/// - Auto-transition vers /hub après 2.5s
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with TickerProviderStateMixin {
  late final AnimationController _ringsCtrl;
  late final AnimationController _pulseCtrl;

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

    // TODO(phase-0): naviguer vers /hub après 2.5s + reprise localStorage.
    // Pour l'instant on reste sur le splash le temps de valider le rendu.
  }

  @override
  void dispose() {
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
            // Logo central
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('K', style: AppTypography.logoK),
                const SizedBox(height: 8),
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
                  CurvedAnimation(
                    parent: _pulseCtrl,
                    curve: Curves.easeInOut,
                  ),
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
