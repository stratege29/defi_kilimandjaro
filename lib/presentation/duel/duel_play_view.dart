import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/presentation/duel/duel_controller.dart';
import 'package:defi_kilimandjaro/presentation/game/game_controller.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/answer_cells.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/circular_grid.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/timer_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran de duel temps réel.
///
/// Reçoit la [DuelSession] initiale via `state.extra`, puis suit les
/// updates via `duelSessionStreamProvider`.
///
/// Si la session est ranked, joue le son de démarrage de duel une seule
/// fois au montage (cf. spec PR #2 § Audio wiring).
class DuelPlayView extends ConsumerStatefulWidget {
  const DuelPlayView({required this.initialSession, super.key});

  final DuelSession initialSession;

  @override
  ConsumerState<DuelPlayView> createState() => _DuelPlayViewState();
}

class _DuelPlayViewState extends ConsumerState<DuelPlayView> {
  @override
  void initState() {
    super.initState();
    // Wire audio : gong de démarrage uniquement pour les duels ranked.
    if (widget.initialSession.isRanked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(audioControllerProvider.notifier).playDuelStart().ignore();
      });
    }
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

    // IMPORTANT: keyed on initialSession (stable widget field) — using the
    // live session as key would recreate the controller on every RTDB
    // update and wipe the local selection.
    final localState = ref.watch(duelControllerProvider(widget.initialSession));
    final controller = ref.read(
      duelControllerProvider(widget.initialSession).notifier,
    );

    // Naviguer vers le résultat dès que la phase est finished.
    ref.listen<AsyncValue<DuelSession?>>(
      duelSessionStreamProvider(widget.initialSession.matchId),
      (prev, next) {
        final s = next.value;
        if (s == null) return;
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

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        child: Column(
          children: [
            _DuelHeader(
              selfProgress: selfPlayer?.progress ?? 0,
              opponentProgress: opponent?.progress ?? 0,
              opponentLabel: opponent != null ? 'Adversaire' : 'En attente...',
            ),
            const SizedBox(height: 12),
            _RiddleCard(riddle: liveSession.riddle),
            const SizedBox(height: 10),
            TimerBar(timeLeft: localState.timeLeft, totalTime: 30),
            const SizedBox(height: 14),
            AnswerCells(
              answer: liveSession.answer,
              formedLetters: formedLetters,
              isValidated: localState.submitted,
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Center(
                child: CircularGrid(
                  letters: liveSession.lettersPool,
                  selectedIndices: localState.selectedIndices,
                  hintTileIndices: const <int>[],
                  phase: localState.submitted
                      ? GamePhase.won
                      : (localState.timeLeft == 0
                            ? GamePhase.lost
                            : GamePhase.playing),
                  seed: liveSession.answer,
                  onTileEntered: controller.selectTile,
                  onDragEnd: () {},
                ),
              ),
            ),
            const SizedBox(height: 12),
            _BottomControls(
              onClear: controller.clearSelection,
              onForfeit: () async {
                await ref
                    .read(duelRepositoryProvider)
                    .forfeit(liveSession.matchId);
                if (!context.mounted) return;
                context.pop();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
} // _DuelPlayViewState

class _DuelHeader extends StatelessWidget {
  const _DuelHeader({
    required this.selfProgress,
    required this.opponentProgress,
    required this.opponentLabel,
  });

  final double selfProgress;
  final double opponentProgress;
  final String opponentLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(color: AppColors.orSoleil.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('⚔️', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Text('DUEL EN COURS', style: AppTypography.bebas(size: 14)),
              const Spacer(),
              Text(
                opponentLabel,
                style: AppTypography.crimson(
                  size: 12,
                  color: AppColors.texteSecondaire,
                  style: FontStyle.italic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ProgressRow(label: 'Moi', value: selfProgress, isSelf: true),
          const SizedBox(height: 4),
          _ProgressRow(
            label: 'Adversaire',
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
              valueColor: AlwaysStoppedAnimation(color),
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

class _RiddleCard extends StatelessWidget {
  const _RiddleCard({required this.riddle});
  final String riddle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orSoleil.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Text('🧙🏿', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              riddle,
              style: AppTypography.crimson(size: 14, style: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.onClear, required this.onForfeit});

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
