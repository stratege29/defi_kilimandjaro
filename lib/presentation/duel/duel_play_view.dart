import 'dart:async';

import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_controller.dart';
import 'package:defi_kilimandjaro/presentation/duel/widgets/duel_countdown_overlay.dart';
import 'package:defi_kilimandjaro/presentation/duel/widgets/duel_intro_overlay.dart';
import 'package:defi_kilimandjaro/presentation/duel/widgets/duel_round_end_overlay.dart';
import 'package:defi_kilimandjaro/presentation/game/game_controller.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/answer_cells.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/circular_grid.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/timer_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran de duel temps réel — Phase 3 (3 manches).
///
/// Orchestre les phases via un [Stack] :
///
/// - [DuelPhase.waiting]   → en attente (existant)
/// - [DuelPhase.intro]     → [DuelIntroOverlay] par-dessus
/// - [DuelPhase.countdown] → [DuelCountdownOverlay] (grille floue + cadenas)
/// - [DuelPhase.active]    → gameplay normal
/// - [DuelPhase.roundEnd]  → [DuelRoundEndOverlay] par-dessus
/// - [DuelPhase.finished]  → navigation vers DuelResultView
class DuelPlayView extends ConsumerStatefulWidget {
  const DuelPlayView({required this.initialSession, super.key});

  final DuelSession initialSession;

  @override
  ConsumerState<DuelPlayView> createState() => _DuelPlayViewState();
}

class _DuelPlayViewState extends ConsumerState<DuelPlayView> {
  /// Timer qui declenche advancePhase apres l'animation locale (3s) sur
  /// roundEnd et countdown. Re-armé à chaque changement de phase.
  Timer? _phaseAdvanceTimer;

  /// Phase observée au dernier tick pour détecter les transitions.
  DuelPhase? _lastObservedPhase;

  @override
  void initState() {
    super.initState();
    // Son de démarrage pour les duels ranked.
    if (widget.initialSession.isRanked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(audioControllerProvider.notifier).playDuelStart().ignore();
      });
    }
  }

  @override
  void dispose() {
    _phaseAdvanceTimer?.cancel();
    super.dispose();
  }

  /// Programme un appel a `advancePhase` 3.2s apres l'entree en `roundEnd`
  /// ou `countdown` (3s d'animation + 0.2s tolerance latence reseau).
  ///
  /// Les 2 clients vont appeler en parallele. Grace a l'idempotence cote
  /// serveur (MIN_ELAPSED_MS + check phase courante), un seul gagne et
  /// l'autre voit la phase deja avancee.
  void _scheduleAdvancePhase(String matchId, DuelPhase newPhase) {
    _phaseAdvanceTimer?.cancel();
    if (newPhase != DuelPhase.roundEnd && newPhase != DuelPhase.countdown) {
      return;
    }
    _phaseAdvanceTimer = Timer(const Duration(milliseconds: 3200), () {
      if (!mounted) return;
      // Best-effort : on ignore l'erreur, le serveur est idempotent.
      ref.read(duelRepositoryProvider).advancePhase(matchId).catchError((
        Object _,
      ) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(firebaseAuthProvider);
    final selfUid = auth.currentUser?.uid ?? '';

    final liveSession =
        ref
            .watch(duelSessionStreamProvider(widget.initialSession.matchId))
            .value ??
        widget.initialSession;

    // Controller local — stable sur toute la session (keyed sur initialSession).
    final localState =
        ref.watch(duelControllerProvider(widget.initialSession));
    final controller = ref.read(
      duelControllerProvider(widget.initialSession).notifier,
    );

    // Propager la session mise à jour au controller (gestion du round switch).
    ref.listen<AsyncValue<DuelSession?>>(
      duelSessionStreamProvider(widget.initialSession.matchId),
      (_, next) {
        final s = next.value;
        if (s == null) return;
        controller.onSessionUpdated(s);
        // Détection de transition de phase : si on entre dans roundEnd ou
        // countdown, on schedule l'appel à advancePhase après 3s d'animation.
        if (s.phase != _lastObservedPhase) {
          _lastObservedPhase = s.phase;
          _scheduleAdvancePhase(s.matchId, s.phase);
        }
        // Navigation automatique vers résultat.
        if (s.phase == DuelPhase.finished) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            context.go(AppRoutes.duelResult, extra: s);
          });
        }
      },
    );

    final formedLetters = localState.selectedIndices
        .map((i) => liveSession.lettersPool[i])
        .join();
    final selfPlayer = liveSession.players[selfUid];
    final opponent = liveSession.opponentOf(selfUid);

    // --- Contenu gameplay de base ---
    final gameplayContent = _GameplayContent(
      session: liveSession,
      localState: localState,
      controller: controller,
      selfPlayer: selfPlayer,
      opponent: opponent,
      formedLetters: formedLetters,
      onForfeit: () async {
        await ref
            .read(duelRepositoryProvider)
            .forfeit(liveSession.matchId);
        if (!context.mounted) return;
        context.pop();
      },
    );

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Couche de base : gameplay normal.
          gameplayContent,

          // Phase overlay : AnimatedSwitcher pour transition fluide.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeIn,
            switchOutCurve: Curves.easeOut,
            child: _buildOverlay(
              phase: liveSession.phase,
              session: liveSession,
              gameContent: gameplayContent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay({
    required DuelPhase phase,
    required DuelSession session,
    required Widget gameContent,
  }) {
    switch (phase) {
      case DuelPhase.intro:
        return DuelIntroOverlay(
          key: const ValueKey('intro'),
          session: session,
        );

      case DuelPhase.countdown:
        return DuelCountdownOverlay(
          key: const ValueKey('countdown'),
          session: session,
          gameContent: gameContent,
          riddleContent: _RiddleCard(riddle: session.riddle),
        );

      case DuelPhase.roundEnd:
        return DuelRoundEndOverlay(
          key: const ValueKey('roundEnd'),
          session: session,
          gameBackground: gameContent,
        );

      case DuelPhase.waiting:
      case DuelPhase.active:
      case DuelPhase.finished:
        // Aucun overlay — clé unique pour que AnimatedSwitcher retire
        // l'overlay précédent proprement.
        return const SizedBox.shrink(key: ValueKey('none'));
    }
  }
}

// ---------------------------------------------------------------------------
// Contenu gameplay de base (affiché en permanence sous les overlays)
// ---------------------------------------------------------------------------

class _GameplayContent extends StatelessWidget {
  const _GameplayContent({
    required this.session,
    required this.localState,
    required this.controller,
    required this.selfPlayer,
    required this.opponent,
    required this.formedLetters,
    required this.onForfeit,
  });

  final DuelSession session;
  final DuelLocalState localState;
  final DuelController controller;
  final DuelPlayer? selfPlayer;
  final DuelPlayer? opponent;
  final String formedLetters;
  final VoidCallback onForfeit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _DuelHeader(
            selfRoundsWon: selfPlayer?.roundsWon ?? 0,
            opponentRoundsWon: opponent?.roundsWon ?? 0,
            selfProgress: selfPlayer?.progress ?? 0,
            opponentProgress: opponent?.progress ?? 0,
            opponentLabel:
                opponent != null ? 'Adversaire' : 'En attente...',
            currentRound: session.currentRound,
            totalRounds: session.totalRounds,
          ),
          const SizedBox(height: 12),
          _RiddleCard(riddle: session.riddle),
          const SizedBox(height: 10),
          TimerBar(timeLeft: localState.timeLeft, totalTime: 30),
          const SizedBox(height: 14),
          AnswerCells(
            answer: session.answer,
            formedLetters: formedLetters,
            isValidated: localState.submitted,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Center(
              child: CircularGrid(
                letters: session.lettersPool,
                selectedIndices: localState.selectedIndices,
                hintTileIndices: const <int>[],
                phase: localState.submitted
                    ? GamePhase.won
                    : (localState.timeLeft == 0
                          ? GamePhase.lost
                          : GamePhase.playing),
                seed: session.answer,
                onTileEntered: controller.selectTile,
                onDragEnd: () {},
              ),
            ),
          ),
          const SizedBox(height: 12),
          _BottomControls(
            onClear: controller.clearSelection,
            onForfeit: onForfeit,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header 3-manches avec score de manches gagnées
// ---------------------------------------------------------------------------

class _DuelHeader extends StatelessWidget {
  const _DuelHeader({
    required this.selfRoundsWon,
    required this.opponentRoundsWon,
    required this.selfProgress,
    required this.opponentProgress,
    required this.opponentLabel,
    required this.currentRound,
    required this.totalRounds,
  });

  final int selfRoundsWon;
  final int opponentRoundsWon;
  final double selfProgress;
  final double opponentProgress;
  final String opponentLabel;
  final int currentRound;
  final int totalRounds;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: AppColors.orSoleil.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined, size: 18, color: AppColors.orSoleil),
              const SizedBox(width: 6),
              Text('DUEL EN COURS', style: AppTypography.bebas(size: 14)),
              const Spacer(),
              // Score de manches.
              Semantics(
                label:
                    'Score manches : Toi $selfRoundsWon - Adversaire $opponentRoundsWon',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.orJour.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.orJour.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '$selfRoundsWon - $opponentRoundsWon',
                    style: AppTypography.bebas(
                      color: AppColors.orSoleil,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Indicateur de manche.
              Text(
                '${currentRound + 1}/$totalRounds',
                style: AppTypography.bebas(
                  size: 12,
                  color: AppColors.texteSecondaire,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ProgressRow(label: 'Moi', value: selfProgress, isSelf: true),
          const SizedBox(height: 4),
          _ProgressRow(
            label: opponentLabel,
            value: opponentProgress,
            isSelf: false,
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.value,
    required this.isSelf,
  });

  final String label;
  final double value;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final color = isSelf ? AppColors.vertClair : AppColors.orSoleil;
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: AppTypography.bebas(size: 12, color: color),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: AppColors.boisFonce.withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.right,
            style: AppTypography.bebas(size: 12, color: color),
          ),
        ),
      ],
    );
  }
}

/// Carte devinette du duel — meme style que le mode solo (`game_view.dart`)
/// avec l'avatar du griot a gauche et le texte en bodyMd non-italique.
class _RiddleCard extends StatelessWidget {
  const _RiddleCard({required this.riddle});

  final String riddle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.orJour.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Image.asset(
            AppAssets.griotIdle,
            width: 56,
            height: 56,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              riddle,
              style: AppTypography.bodyMd.copyWith(
                fontSize: 16,
                height: 1.45,
                color: AppColors.textePrimaire,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.onClear,
    required this.onForfeit,
  });

  final VoidCallback onClear;
  final VoidCallback onForfeit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(
                Icons.backspace_outlined,
                color: AppColors.orSoleil,
              ),
              label: Text(
                'Effacer',
                style: AppTypography.bebas(color: AppColors.orSoleil),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.orSoleil),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onForfeit,
              icon: const Icon(Icons.flag, color: AppColors.rouge),
              label: Text(
                'Abandonner',
                style: AppTypography.bebas(color: AppColors.rouge),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.rouge),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
