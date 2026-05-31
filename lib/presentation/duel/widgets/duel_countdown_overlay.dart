import 'dart:async';

import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/presentation/duel/widgets/duel_versus_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Superposition décompte affichée pendant la phase [DuelPhase.countdown].
///
/// Continuité directe de `DuelIntroOverlay` : même décor VERSUS (combattants
/// en place, VS doré), auquel s'ajoute le bandeau bas « Le duel commence
/// dans N » (3 → 2 → 1 → GO), conforme à la maquette `duelstart`.
///
/// Le timing se calcule depuis [DuelSession.phaseStartedAtMs].
class DuelCountdownOverlay extends ConsumerStatefulWidget {
  const DuelCountdownOverlay({required this.session, super.key});

  final DuelSession session;

  @override
  ConsumerState<DuelCountdownOverlay> createState() =>
      _DuelCountdownOverlayState();
}

class _DuelCountdownOverlayState extends ConsumerState<DuelCountdownOverlay>
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
    final elapsedSeconds =
        ((now - startMs) / 1000).floor().clamp(0, _countdownSeconds);
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
      unawaited(ref.read(audioControllerProvider.notifier).playWordComplete());
    }
  }

  @override
  void dispose() {
    _digitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selfUid = ref.watch(firebaseAuthProvider).currentUser?.uid ?? '';
    final self = widget.session.players[selfUid];
    final opponent = widget.session.opponentOf(selfUid);

    final h = MediaQuery.sizeOf(context).height;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Décor VERSUS partagé.
          const Positioned.fill(child: DuelVersusBackdrop()),

          // Combattant local (haut-gauche) — déjà en place.
          Positioned(
            left: kDuelFighterInset,
            top: h * kDuelLeftFighterTopFraction,
            child: DuelFighterPortrait(
              label: 'Toi',
              uid: selfUid,
              roundsWon: self?.roundsWon ?? 0,
              showElo: widget.session.isRanked,
              accent: AppColors.orJour,
            ),
          ),

          // Adversaire (bas-droite) — déjà en place.
          Positioned(
            right: kDuelFighterInset,
            top: h * kDuelRightFighterTopFraction,
            child: DuelFighterPortrait(
              label: 'Adversaire',
              uid: opponent?.uid ?? '',
              roundsWon: opponent?.roundsWon ?? 0,
              showElo: widget.session.isRanked,
              accent: AppColors.cielHauteur,
            ),
          ),

          // VS doré au centre.
          Positioned(
            top: h * kDuelVsCenterFraction - 105,
            left: 0,
            right: 0,
            child: const Center(child: DuelVsBadge()),
          ),

          // Pastille de manche en haut.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: DuelRoundPill(
                  currentRound: widget.session.currentRound,
                  totalRounds: widget.session.totalRounds,
                  difficulty:
                      widget.session.currentRoundData?.difficulty ?? 'easy',
                ),
              ),
            ),
          ),

          // Bandeau bas « Le duel commence dans N » (maquette `.ds-count2`).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _CountdownFooter(
              digit: _currentDigit,
              showGo: _showGo,
              pulse: _digitCtrl,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bandeau de décompte (label + grand chiffre Fraunces pulsé).
// ---------------------------------------------------------------------------

class _CountdownFooter extends StatelessWidget {
  const _CountdownFooter({
    required this.digit,
    required this.showGo,
    required this.pulse,
  });

  final int digit;
  final bool showGo;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 12, bottom: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.surface.withValues(alpha: 0),
            AppColors.surface.withValues(alpha: 0.88),
            AppColors.surface,
          ],
          stops: const [0, 0.42, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Le duel commence dans'.toUpperCase(),
              style: AppTypography.labelXs.copyWith(
                color: AppColors.texteTertiaire,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            if (showGo)
              const _Digit(text: 'GO', size: 46)
            else
              AnimatedBuilder(
                animation: pulse,
                builder: (_, __) {
                  final scale = Tween<double>(begin: 1.3, end: 1)
                      .animate(
                        CurvedAnimation(parent: pulse, curve: Curves.easeOut),
                      )
                      .value;
                  final opacity = Tween<double>(begin: 0.5, end: 1)
                      .animate(
                        CurvedAnimation(
                          parent: pulse,
                          curve: const Interval(0, 0.5, curve: Curves.easeIn),
                        ),
                      )
                      .value;
                  return Semantics(
                    label: 'Compte à rebours : $digit',
                    child: Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity,
                        child: _Digit(text: '$digit', size: 56),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Digit extends StatelessWidget {
  const _Digit({required this.text, required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.playfair(
        size: size,
        weight: FontWeight.w900,
      ).copyWith(
        height: 1.05,
        letterSpacing: text == 'GO' ? 1 : 0,
        shadows: [
          Shadow(
            color: AppColors.orJour.withValues(alpha: 0.6),
            blurRadius: 22,
          ),
        ],
      ),
    );
  }
}
