import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Barre de minuterie tam-tam (cf. plan.md §2 Phase 1.2).
///
/// Refonte 2026 :
/// - Or (accent principal) en temps normal
/// - Ambré (warning) si timeLeft < 12 s
/// - Kola avec shimmer si timeLeft < 5 s
class TimerBar extends StatefulWidget {
  const TimerBar({required this.timeLeft, required this.totalTime, super.key});

  final int timeLeft;
  final int totalTime;

  @override
  State<TimerBar> createState() => _TimerBarState();
}

class _TimerBarState extends State<TimerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // Plage de pulsation élargie (0.4-1.0) pour rendre le danger lisible
    // de loin — l'alpha shimmer module fortement la barre rouge en sub-8s.
    _shimmerAnim = Tween<double>(
      begin: 0.4,
      end: 1,
    ).animate(CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Color _barColor() {
    if (widget.timeLeft < 5) return AppColors.kola;
    if (widget.timeLeft < 12) return AppColors.warning;
    return AppColors.orJour;
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.totalTime == 0
        ? 0.0
        : widget.timeLeft / widget.totalTime;
    final barColor = _barColor();
    final isDanger = widget.timeLeft < 5;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Icône timer — Material rounded, cohérent avec le système d'icônes.
            Icon(Icons.timer_outlined, size: 18, color: barColor),
            const SizedBox(width: 8),
            // Progress bar — scale subtilement (0.97-1.03) en danger pour
            // accentuer la tension visuelle au-delà du shimmer alpha.
            Expanded(
              child: AnimatedBuilder(
                animation: _shimmerAnim,
                builder: (_, __) {
                  final bar = ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: AppColors.boisFonce.withValues(
                        alpha: 0.5,
                      ),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDanger
                            ? barColor.withValues(alpha: _shimmerAnim.value)
                            : barColor,
                      ),
                    ),
                  );
                  if (!isDanger) return bar;
                  // 0.0 → scale 1.03, 1.0 → scale 0.97, sync avec shimmer.
                  final scale = 1.03 - (1 - _shimmerAnim.value) * 0.06;
                  return Transform.scale(scaleY: scale, child: bar);
                },
              ),
            ),
            const SizedBox(width: 8),
            // Countdown number
            SizedBox(
              width: 28,
              child: AnimatedDefaultTextStyle(
                style: AppTypography.bebas(size: 18, color: barColor),
                duration: const Duration(milliseconds: 300),
                child: Text('${widget.timeLeft}', textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
