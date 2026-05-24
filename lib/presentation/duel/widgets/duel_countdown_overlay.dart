import 'dart:async';
import 'dart:ui' as ui;

import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Superposition 3-2-1 affichée pendant la phase [DuelPhase.countdown].
///
/// Comportement :
/// - La devinette reste visible dans son cadre pour permettre la lecture.
/// - La grille circulaire (slot [gameContent]) est rendue floue + cadenas.
/// - Un grand chiffre (3 → 2 → 1 → GO!) animate au centre.
/// - Le timing se calcule depuis [DuelSession.phaseStartedAtMs].
///
/// Le parent DuelPlayView fournit le contenu gameplay via [gameContent]
/// et [riddleContent] pour que les overlays restent découplés.
class DuelCountdownOverlay extends ConsumerStatefulWidget {
  const DuelCountdownOverlay({
    required this.session,
    required this.gameContent,
    required this.riddleContent,
    super.key,
  });

  final DuelSession session;

  /// Le widget grille circulaire + cellules réponse (sera flouté + verrouillé).
  final Widget gameContent;

  /// Le widget devinette (visible, non flouté).
  final Widget riddleContent;

  @override
  ConsumerState<DuelCountdownOverlay> createState() =>
      _DuelCountdownOverlayState();
}

class _DuelCountdownOverlayState
    extends ConsumerState<DuelCountdownOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _digitCtrl;
  int _currentDigit = 3;
  bool _showGo = false;

  // Durée de la phase countdown (définie côté serveur, on s'aligne dessus).
  static const int _countdownSeconds = 3;

  @override
  void initState() {
    super.initState();

    _digitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _computeAndStartCountdown();
  }

  void _computeAndStartCountdown() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final startMs = widget.session.phaseStartedAtMs ?? now;
    final elapsedSeconds = ((now - startMs) / 1000).floor().clamp(0, _countdownSeconds);
    final remaining = _countdownSeconds - elapsedSeconds;

    if (remaining > 0) {
      _currentDigit = remaining;
      _animateDigit();
    } else {
      _currentDigit = 0;
      _showGo = true;
    }
  }

  Future<void> _animateDigit() async {
    if (!mounted) return;

    // Son "tac" sur chaque chiffre.
    unawaited(ref.read(audioControllerProvider.notifier).playTimerTick(60));

    await _digitCtrl.forward(from: 0);

    // Attend 700 ms au total (350 animation + 350 pause).
    await Future<void>.delayed(const Duration(milliseconds: 350));

    if (!mounted) return;

    setState(() {
      _currentDigit--;
    });

    if (_currentDigit > 0) {
      unawaited(_animateDigit());
    } else {
      // Affiche GO!
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      setState(() => _showGo = true);
      // Son "ding" sur GO!
      unawaited(
        ref.read(audioControllerProvider.notifier).playWordComplete(),
      );
    }
  }

  @override
  void dispose() {
    _digitCtrl.dispose();
    super.dispose();
  }

  String get _difficultyLabel {
    final d = widget.session.currentRoundData?.difficulty ?? 'easy';
    return switch (d) {
      'easy' => 'Facile',
      'medium' => 'Moyen',
      'hard' => 'Difficile',
      _ => d,
    };
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // --- Contenu gameplay flouté + verrouillé ---
          _BlurredGameContent(child: widget.gameContent),

          // --- Couche semi-transparente sombre ---
          ColoredBox(
            color: Colors.black.withValues(alpha: 0.55),
          ),

          // --- Devinette visible en haut (non floue) ---
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Indicateur de manche.
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: _RoundBadge(
                      currentRound: widget.session.currentRound,
                      totalRounds: widget.session.totalRounds,
                      difficultyLabel: _difficultyLabel,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: widget.riddleContent,
                  ),
                ],
              ),
            ),
          ),

          // --- Grand chiffre centré ---
          Center(
            child: _showGo
                ? _GoLabel()
                : AnimatedBuilder(
                    animation: _digitCtrl,
                    builder: (_, __) {
                      final scale = Tween<double>(begin: 1.4, end: 1).animate(
                        CurvedAnimation(
                          parent: _digitCtrl,
                          curve: Curves.easeOut,
                        ),
                      ).value;
                      final opacity = Tween<double>(begin: 1, end: 0.4).animate(
                        CurvedAnimation(
                          parent: _digitCtrl,
                          curve: const Interval(0.5, 1, curve: Curves.easeIn),
                        ),
                      ).value;
                      return Semantics(
                        label: 'Compte à rebours : $_currentDigit',
                        child: Transform.scale(
                          scale: scale,
                          child: Opacity(
                            opacity: opacity,
                            child: Text(
                              '$_currentDigit',
                              style: AppTypography.displayLg.copyWith(
                                fontSize: 96,
                                color: AppColors.orJour,
                                shadows: const [
                                  Shadow(
                                    color: AppColors.orCrepuscule,
                                    blurRadius: 24,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sous-widgets privés
// ---------------------------------------------------------------------------

class _BlurredGameContent extends StatelessWidget {
  const _BlurredGameContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        // Flou BackdropFilter par-dessus le contenu gameplay.
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: const ColoredBox(color: Colors.transparent),
        ),
        // Cadenas centré (zone grille inférieure).
        Align(
          alignment: const Alignment(0, 0.4),
          child: Semantics(
            label: 'Grille verrouillée — attend le GO',
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.orJour.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.lock_outline,
                size: 36,
                color: AppColors.orJour,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GoLabel extends StatefulWidget {
  @override
  State<_GoLabel> createState() => _GoLabelState();
}

class _GoLabelState extends State<_GoLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
    _scale = Tween<double>(begin: 0.3, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'GO ! Le duel commence',
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, __) => Transform.scale(
          scale: _scale.value,
          child: Text(
            'GO !',
            style: AppTypography.displayLg.copyWith(
              fontSize: 80,
              color: AppColors.orJour,
              shadows: [
                Shadow(
                  color: AppColors.orJour.withValues(alpha: 0.6),
                  blurRadius: 32,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundBadge extends StatelessWidget {
  const _RoundBadge({
    required this.currentRound,
    required this.totalRounds,
    required this.difficultyLabel,
  });

  final int currentRound;
  final int totalRounds;
  final String difficultyLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.orJour.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        'Manche ${currentRound + 1} / $totalRounds — $difficultyLabel',
        style: AppTypography.labelSm,
      ),
    );
  }
}
