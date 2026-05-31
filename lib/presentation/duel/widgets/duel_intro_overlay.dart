import 'dart:async';

import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/presentation/duel/widgets/duel_versus_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Superposition animée affichée pendant la phase [DuelPhase.intro].
///
/// Le décor VERSUS (split diagonal, montagne, lame dorée) est partagé avec
/// `DuelCountdownOverlay` via [DuelVersusBackdrop] : les deux combattants
/// glissent en diagonale vers leur place (~1 s, [Curves.easeOutBack]), puis un
/// flash blanc et le VS doré apparaissent en [ScaleTransition].
///
/// Durée totale : ~2,5 s. La transition vers [DuelPhase.countdown] est
/// déclenchée côté serveur (`advanceRound`) — ce widget ne la pilote pas.
class DuelIntroOverlay extends ConsumerStatefulWidget {
  const DuelIntroOverlay({required this.session, super.key});

  final DuelSession session;

  @override
  ConsumerState<DuelIntroOverlay> createState() => _DuelIntroOverlayState();
}

class _DuelIntroOverlayState extends ConsumerState<DuelIntroOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final AnimationController _vsCtrl;
  late final AnimationController _flashCtrl;

  late final Animation<double> _selfSlide;
  late final Animation<double> _opponentSlide;
  late final Animation<double> _vsScale;
  late final Animation<double> _vsOpacity;
  late final Animation<double> _flashOpacity;

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _vsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    // Portraits glissent de ±1 (hors écran) vers 0 (leur place diagonale).
    _selfSlide = Tween<double>(begin: -1, end: 0).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutBack),
    );
    _opponentSlide = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutBack),
    );

    _vsScale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _vsCtrl, curve: Curves.easeOutBack),
    );
    _vsOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _vsCtrl,
        curve: const Interval(0, 0.5, curve: Curves.easeIn),
      ),
    );

    _flashOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 0.85),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.85, end: 0),
        weight: 60,
      ),
    ]).animate(_flashCtrl);

    _playSequence();
  }

  Future<void> _playSequence() async {
    // 1. Slides portraits.
    await _slideCtrl.forward();

    // 2. Flash + VS simultanément.
    unawaited(_flashCtrl.forward());
    unawaited(_vsCtrl.forward());

    // 3. Son duel start.
    unawaited(ref.read(audioControllerProvider.notifier).playDuelStart());
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _vsCtrl.dispose();
    _flashCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selfUid = ref.watch(firebaseAuthProvider).currentUser?.uid ?? '';
    final self = widget.session.players[selfUid];
    final opponent = widget.session.opponentOf(selfUid);

    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Décor VERSUS partagé.
          const Positioned.fill(child: DuelVersusBackdrop()),

          // Combattant local — glisse depuis la gauche vers sa place haut-gauche.
          Positioned(
            left: kDuelFighterInset,
            top: h * kDuelLeftFighterTopFraction,
            child: AnimatedBuilder(
              animation: _slideCtrl,
              builder: (_, child) => Transform.translate(
                offset: Offset(_selfSlide.value * w, 0),
                child: child,
              ),
              child: DuelFighterPortrait(
                label: 'Toi',
                uid: selfUid,
                roundsWon: self?.roundsWon ?? 0,
                showElo: widget.session.isRanked,
                accent: AppColors.orJour,
              ),
            ),
          ),

          // Adversaire — glisse depuis la droite vers sa place bas-droite.
          Positioned(
            right: kDuelFighterInset,
            top: h * kDuelRightFighterTopFraction,
            child: AnimatedBuilder(
              animation: _slideCtrl,
              builder: (_, child) => Transform.translate(
                offset: Offset(_opponentSlide.value * w, 0),
                child: child,
              ),
              child: DuelFighterPortrait(
                label: 'Adversaire',
                uid: opponent?.uid ?? '',
                roundsWon: opponent?.roundsWon ?? 0,
                showElo: widget.session.isRanked,
                accent: AppColors.cielHauteur,
              ),
            ),
          ),

          // Flash blanc au croisement.
          AnimatedBuilder(
            animation: _flashOpacity,
            builder: (_, __) => Opacity(
              opacity: _flashOpacity.value,
              child: const ColoredBox(color: Colors.white),
            ),
          ),

          // VS doré au centre du choc.
          Positioned(
            top: h * kDuelVsCenterFraction - 105,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedBuilder(
                animation: _vsCtrl,
                builder: (_, child) => FadeTransition(
                  opacity: _vsOpacity,
                  child: ScaleTransition(scale: _vsScale, child: child),
                ),
                child: const DuelVsBadge(),
              ),
            ),
          ),

          // Pastille de manche en haut.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: DuelRoundPill(
                  currentRound: widget.session.currentRound,
                  totalRounds: widget.session.totalRounds,
                  difficulty: widget.session.currentRoundData?.difficulty ?? 'easy',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
