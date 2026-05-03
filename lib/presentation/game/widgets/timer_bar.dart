import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Barre de minuterie tam-tam (cf. plan.md §2 Phase 1.2).
///
/// - Vert normal
/// - Orange si timeLeft < 15 s
/// - Rouge avec shimmer si timeLeft < 8 s
class TimerBar extends StatefulWidget {
  const TimerBar({
    required this.timeLeft,
    required this.totalTime,
    super.key,
  });

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

    _shimmerAnim = Tween<double>(begin: 0.6, end: 1).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Color _barColor() {
    if (widget.timeLeft < 8) return AppColors.rouge;
    if (widget.timeLeft < 15) return AppColors.orChaud;
    return AppColors.vertClair;
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        widget.totalTime == 0 ? 0.0 : widget.timeLeft / widget.totalTime;
    final barColor = _barColor();
    final isDanger = widget.timeLeft < 8;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            // Tam-tam icon
            const Text('🥁', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            // Progress bar
            Expanded(
              child: AnimatedBuilder(
                animation: _shimmerAnim,
                builder: (_, __) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor:
                          AppColors.boisFonce.withValues(alpha: 0.5),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDanger
                            ? barColor.withValues(alpha: _shimmerAnim.value)
                            : barColor,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            // Countdown number
            SizedBox(
              width: 28,
              child: AnimatedDefaultTextStyle(
                style: AppTypography.bebas(
                  size: 18,
                  color: barColor,
                ),
                duration: const Duration(milliseconds: 300),
                child: Text(
                  '${widget.timeLeft}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
