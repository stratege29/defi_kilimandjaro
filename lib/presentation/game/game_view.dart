import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/game_controller.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/answer_cells.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/circular_grid.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/timer_bar.dart';
import 'package:defi_kilimandjaro/presentation/result/failure_view.dart';
import 'package:defi_kilimandjaro/presentation/result/victory_view.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran 03 — Écran de Jeu (cf. plan.md §2 Phase 1.2 et maquette p.5).
///
/// Reçoit les [GameArgs] via [GoRouterState.extra].
class GameView extends ConsumerStatefulWidget {
  const GameView({required this.args, super.key});

  final GameArgs args;

  @override
  ConsumerState<GameView> createState() => _GameViewState();
}

class _GameViewState extends ConsumerState<GameView> {
  bool _overlayShown = false;

  @override
  Widget build(BuildContext context) {
    final provider = gameControllerProvider(widget.args);
    final gameState = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    // Listen for phase transitions and show overlay exactly once per end state.
    ref.listen<GameState>(provider, (previous, next) {
      if (_overlayShown) return;
      if (next.phase == GamePhase.won &&
          (previous == null || previous.phase != GamePhase.won)) {
        _overlayShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showVictoryOverlay(context, next.timeLeft);
        });
      } else if (next.phase == GamePhase.lost &&
          (previous == null || previous.phase != GamePhase.lost)) {
        _overlayShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showFailureOverlay(context, controller);
        });
      }
    });

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Header.
            _GameHeader(
              coins: gameState.coins,
              onBack: () => context.pop(),
            ),
            const SizedBox(height: 8),
            // World banner.
            _WorldBanner(world: widget.args.devinette.world),
            const SizedBox(height: 12),
            // Riddle card.
            _RiddleCard(riddle: widget.args.devinette.riddle),
            const SizedBox(height: 12),
            // Timer bar.
            TimerBar(
              timeLeft: gameState.timeLeft,
              totalTime: 30,
            ),
            const SizedBox(height: 16),
            // Answer cells.
            AnswerCells(
              answer: widget.args.devinette.answer,
              formedLetters: gameState.formedWord,
              isValidated: gameState.validationCorrect,
            ),
            const SizedBox(height: 20),
            // Circular tile grid (expands to fill space).
            Expanded(
              child: Center(
                child: CircularGrid(
                  letters: gameState.displayLetters,
                  selectedIndices: gameState.selectedIndices,
                  hintRevealedCount: gameState.hintRevealedCount,
                  answer: widget.args.devinette.answer,
                  phase: gameState.phase,
                  onTileEntered: controller.selectTile,
                  onDragEnd: () {
                    // validate() is called automatically on complete word;
                    // on partial lift we just let selection persist.
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Bottom action buttons.
            _ActionButtons(
              onHint: controller.useHint,
              onClear: controller.clearSelection,
              onValidate: controller.validate,
              canHint: gameState.coins >= 20 &&
                  gameState.hintRevealedCount <
                      widget.args.devinette.answer.length &&
                  gameState.phase == GamePhase.playing,
              canValidate: gameState.selectedIndices.isNotEmpty &&
                  gameState.phase == GamePhase.playing,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showVictoryOverlay(BuildContext ctx, int timeLeft) {
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => VictoryView(
        devinette: widget.args.devinette,
        timeLeft: timeLeft,
        onNext: () {
          // Close overlay then return to hub.
          ctx
            ..pop() // closes dialog
            ..pop(); // back to hub
        },
      ),
    );
  }

  void _showFailureOverlay(BuildContext ctx, GameController controller) {
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => FailureView(
        devinette: widget.args.devinette,
        onRetry: () {
          ctx.pop(); // closes dialog
          _overlayShown = false;
          controller.restart();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _GameHeader extends StatelessWidget {
  const _GameHeader({
    required this.coins,
    required this.onBack,
  });

  final int coins;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: AppColors.orSoleil,
            onPressed: onBack,
            tooltip: 'game.back'.tr(),
          ),
          Text('KILIMANDJARO', style: AppTypography.bebas()),
          const Spacer(),
          // Mute button (stub — audio agent scope).
          Icon(
            Icons.volume_up,
            color: AppColors.orSoleil.withValues(alpha: 0.7),
            size: 22,
          ),
          const SizedBox(width: 12),
          // Coins chip.
          _CoinsChip(coins: coins),
        ],
      ),
    );
  }
}

class _CoinsChip extends StatelessWidget {
  const _CoinsChip({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.orSoleil.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('🪙', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            '$coins',
            style: AppTypography.bebas(size: 14, color: AppColors.orSoleil),
          ),
        ],
      ),
    );
  }
}

class _WorldBanner extends StatelessWidget {
  const _WorldBanner({required this.world});

  final String world;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.orSoleil.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('🏘️', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            world.replaceAll('_', ' ').toUpperCase(),
            style: AppTypography.bebas(
              size: 13,
              color: AppColors.tagline,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RiddleCard extends StatelessWidget {
  const _RiddleCard({required this.riddle});

  final String riddle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.boisFonce.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.orChaud.withValues(alpha: 0.5),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Griot avatar.
          const Text(
            '🧙🏿',
            style: TextStyle(fontSize: 28),
          ),
          const SizedBox(width: 10),
          // Riddle text.
          Expanded(
            child: Text(
              riddle,
              style: AppTypography.crimson(
                size: 15,
                style: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.onHint,
    required this.onClear,
    required this.onValidate,
    required this.canHint,
    required this.canValidate,
  });

  final VoidCallback onHint;
  final VoidCallback onClear;
  final VoidCallback onValidate;
  final bool canHint;
  final bool canValidate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: <Widget>[
          // Hint button.
          Expanded(
            child: _GameButton(
              label: 'game.hint'.tr(),
              subtitle: '-20 🪙',
              color: AppColors.bois,
              enabled: canHint,
              onTap: onHint,
            ),
          ),
          const SizedBox(width: 8),
          // Clear button.
          Expanded(
            child: _GameButton(
              label: 'game.clear'.tr(),
              color: AppColors.boisFonce,
              onTap: onClear,
            ),
          ),
          const SizedBox(width: 8),
          // Validate button.
          Expanded(
            child: _GameButton(
              label: 'game.validate'.tr(),
              color: AppColors.vertClair,
              enabled: canValidate,
              onTap: onValidate,
            ),
          ),
        ],
      ),
    );
  }
}

class _GameButton extends StatelessWidget {
  const _GameButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                offset: const Offset(0, 2),
                blurRadius: 6,
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: AppTypography.bebas(
                    size: 15,
                    letterSpacing: 1,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTypography.crimson(
                      size: 11,
                      color: AppColors.ivoire.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
