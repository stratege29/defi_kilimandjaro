import 'dart:async';

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Compte à rebours qui se met à jour chaque seconde jusqu'à [target], puis
/// notifie [onElapsed] une fois la cible atteinte.
///
/// Réutilisé pour « démarre dans … » (vers `start_at`) et « se termine dans … »
/// (vers `end_at`). Affiche `HH:MM:SS` au-delà d'une heure, sinon `MM:SS`.
class TournamentCountdown extends StatefulWidget {
  const TournamentCountdown({
    required this.target,
    this.style,
    this.color,
    this.onElapsed,
    super.key,
  });

  final DateTime target;
  final TextStyle? style;
  final Color? color;
  final VoidCallback? onElapsed;

  /// Formate une durée : `HH:MM:SS` au-delà d'une heure, sinon `MM:SS`.
  static String format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  State<TournamentCountdown> createState() => _TournamentCountdownState();
}

class _TournamentCountdownState extends State<TournamentCountdown> {
  Timer? _timer;
  late Duration _remaining;
  bool _firedElapsed = false;

  @override
  void initState() {
    super.initState();
    _remaining = _computeRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(TournamentCountdown old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) {
      _firedElapsed = false;
      _remaining = _computeRemaining();
    }
  }

  Duration _computeRemaining() {
    final d = widget.target.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  void _tick() {
    if (!mounted) return;
    final next = _computeRemaining();
    setState(() => _remaining = next);
    if (next == Duration.zero && !_firedElapsed) {
      _firedElapsed = true;
      widget.onElapsed?.call();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      TournamentCountdown.format(_remaining),
      style: (widget.style ?? AppTypography.bebas(size: 22))
          .copyWith(color: widget.color ?? AppColors.orSoleil),
    );
  }
}
