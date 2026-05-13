import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/ads/ads_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/game_controller.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/answer_cells.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/circular_grid.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/timer_bar.dart';
import 'package:defi_kilimandjaro/presentation/result/failure_view.dart';
import 'package:defi_kilimandjaro/presentation/result/victory_view.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
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
              cauris: gameState.cauris,
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
                  seed: widget.args.devinette.id,
                  onTileEntered: controller.selectTile,
                  onDragEnd: () {
                    // validate() is called automatically on complete word;
                    // on partial lift we just let selection persist.
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Rewarded video chip ("+50 🪙 regarder une pub").
            if (!ref.watch(playerProgressProvider).noAdsPurchased)
              _RewardedAdChip(
                enabled: gameState.phase == GamePhase.playing,
                onWatch: () async {
                  final got = await ref
                      .read(adsServiceProvider)
                      .showRewardedForCauris();
                  if (!context.mounted) return;
                  if (got) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '+50 Cauris de Sagesse',
                          style: AppTypography.bebas(),
                        ),
                        backgroundColor: AppColors.vertClair,
                        duration: const Duration(milliseconds: 1200),
                      ),
                    );
                  }
                },
              ),
            const SizedBox(height: 8),
            // Bottom action buttons.
            _ActionButtons(
              onHint: controller.useHint,
              onClear: controller.clearSelection,
              onValidate: controller.validate,
              canHint: gameState.cauris >= 20 &&
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

  Future<void> _showFailureOverlay(
    BuildContext ctx,
    GameController controller,
  ) async {
    // Records the failure and triggers an interstitial every 3 in a row,
    // unless the player has bought "No-Ads".
    final progress = ref.read(playerProgressProvider);
    if (!progress.noAdsPurchased) {
      final newCount = await ref
          .read(playerProgressProvider.notifier)
          .recordFailure();
      if (newCount % 3 == 0) {
        await ref.read(adsServiceProvider).maybeShowInterstitial();
      }
    }
    if (!ctx.mounted) return;
    await showDialog<void>(
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

class _RewardedAdChip extends StatelessWidget {
  const _RewardedAdChip({required this.enabled, required this.onWatch});
  final bool enabled;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onWatch : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.bois.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.orSoleil.withValues(alpha: enabled ? 0.6 : 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.play_circle_outline,
                  size: 16,
                  color: AppColors.orSoleil
                      .withValues(alpha: enabled ? 0.95 : 0.4),
                ),
                const SizedBox(width: 6),
                Text(
                  '+50',
                  style: AppTypography.bebas(
                    size: 13,
                    color: AppColors.orSoleil
                        .withValues(alpha: enabled ? 0.95 : 0.4),
                  ),
                ),
                const SizedBox(width: 4),
                Opacity(
                  opacity: enabled ? 1 : 0.4,
                  child: const CaurisIcon(size: 14),
                ),
                const SizedBox(width: 4),
                Text(
                  'regarder une pub',
                  style: AppTypography.bebas(
                    size: 13,
                    color: AppColors.orSoleil
                        .withValues(alpha: enabled ? 0.95 : 0.4),
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

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _GameHeader extends StatelessWidget {
  const _GameHeader({
    required this.cauris,
    required this.onBack,
  });

  final int cauris;
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
          // Audio indicator (static, toggle handled in profile).
          Opacity(
            opacity: 0.85,
            child: Image.asset(AppAssets.iconAudioOn, width: 24, height: 24),
          ),
          const SizedBox(width: 12),
          // Cauris chip.
          _CaurisChip(cauris: cauris),
        ],
      ),
    );
  }
}

class _CaurisChip extends StatelessWidget {
  const _CaurisChip({required this.cauris});

  final int cauris;

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
          const CaurisIcon(size: 16),
          const SizedBox(width: 4),
          Text(
            '$cauris',
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
          Image.asset(
            AppAssets.griotIdle,
            width: 64,
            height: 64,
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
              subtitle: '-20',
              iconAsset: AppAssets.iconHint,
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
              iconAsset: AppAssets.iconErase,
              color: AppColors.boisFonce,
              onTap: onClear,
            ),
          ),
          const SizedBox(width: 8),
          // Validate button.
          Expanded(
            child: _GameButton(
              label: 'game.validate'.tr(),
              iconAsset: AppAssets.iconValidate,
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
    this.iconAsset,
    this.enabled = true,
  });

  final String label;
  final String? subtitle;
  final String? iconAsset;
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
          height: 56,
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (iconAsset != null) ...[
                  Image.asset(iconAsset!, width: 28, height: 28),
                  const SizedBox(width: 6),
                ],
                Column(
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            subtitle!,
                            style: AppTypography.crimson(
                              size: 11,
                              color: AppColors.ivoire.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(width: 3),
                          const CaurisIcon(size: 11),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
