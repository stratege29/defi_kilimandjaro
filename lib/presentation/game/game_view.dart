import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/core/utils/level_difficulty_resolver.dart';
import 'package:defi_kilimandjaro/data/ads/ads_service.dart';
import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/services/devinette_selection_service_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/game_controller.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/answer_cells.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/circular_grid.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/timer_bar.dart';
import 'package:defi_kilimandjaro/presentation/result/failure_view.dart';
import 'package:defi_kilimandjaro/presentation/result/mountain_conquest_view.dart';
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

class _GameViewState extends ConsumerState<GameView>
    with WidgetsBindingObserver {
  bool _overlayShown = false;

  /// Vrai quand un dialog (back confirm, victory, failure, conquest) tient
  /// le timer en pause via [_pauseForModal]. Évite un double-resume.
  bool _modalPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause le décompte quand l'app passe en arrière-plan (appel téléphonique,
    // notification plein écran, switch d'app). Reprend à la résumée.
    final notifier = ref.read(gameControllerProvider(widget.args).notifier);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        notifier.pause();
      case AppLifecycleState.resumed:
        if (!_modalPaused) notifier.resume();
      case AppLifecycleState.detached:
        break;
    }
  }

  void _pauseForModal() {
    if (_modalPaused) return;
    _modalPaused = true;
    ref.read(gameControllerProvider(widget.args).notifier).pause();
  }

  void _resumeFromModal() {
    if (!_modalPaused) return;
    _modalPaused = false;
    ref.read(gameControllerProvider(widget.args).notifier).resume();
  }

  /// Construit le header avec contexte montagne (nom + niveau N/M + drapeau).
  /// Lit `mountainsProvider` pour récupérer le détail vivant. En mode Hub
  /// (sans `mountainId`), tombe sur le défaut "KILIMANDJARO" sans niveau.
  Widget _buildHeader(int cauris) {
    final mountainId = widget.args.mountainId;
    if (mountainId == null) {
      return _GameHeader(cauris: cauris, onBack: _confirmBack);
    }

    final mountainsAsync = ref.watch(mountainsProvider);
    final mountain = mountainsAsync.maybeWhen(
      data: (list) => list.cast<Mountain?>().firstWhere(
        (m) => m?.id == mountainId,
        orElse: () => null,
      ),
      orElse: () => null,
    );

    if (mountain == null) {
      return _GameHeader(cauris: cauris, onBack: _confirmBack);
    }

    // Niveau affiché = celui que le joueur est en train d'essayer
    // (completedLevels + 1, clampé à totalLevels).
    final currentLevel = (mountain.completedLevels + 1).clamp(
      1,
      mountain.totalLevels,
    );

    return _GameHeader(
      cauris: cauris,
      onBack: _confirmBack,
      mountainName: mountain.name,
      levelLabel: 'Niveau $currentLevel / ${mountain.totalLevels}',
      flagEmoji: mountain.flagEmoji,
    );
  }

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
          _showVictoryOverlay(context, next.timeLeft, next.starsEarned);
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.vertForet,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              // Header — montagne en cours + niveau (au lieu du nom d'app).
              _buildHeader(gameState.cauris),
              const SizedBox(height: 8),
              // Riddle card.
              _RiddleCard(riddle: widget.args.devinette.riddle),
              if (widget.args.config.modifiers.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _ModifierBadges(modifiers: widget.args.config.modifiers),
              ],
              const SizedBox(height: 10),
              // Timer bar — totalTime calibré sur la config du niveau.
              TimerBar(
                timeLeft: gameState.timeLeft,
                totalTime: widget.args.config.timerSeconds,
              ),
              const SizedBox(height: 12),
              // Answer cells — quand `reverse` est actif on affiche les
              // cases dans l'ordre de saisie (mot inversé) pour que le
              // remplissage gauche→droite reste intuitif.
              AnswerCells(
                answer: gameState.expectedAnswer,
                formedLetters: gameState.formedWord,
                isValidated: gameState.validationCorrect,
              ),
              const SizedBox(height: 12),
              // Circular tile grid (expands to fill space).
              Expanded(
                child: Center(
                  child: CircularGrid(
                    letters: gameState.displayLetters,
                    selectedIndices: gameState.selectedIndices,
                    hintTileIndices: gameState.hintTileIndices,
                    hiddenIndices: gameState.fogHiddenIndices,
                    shuffledIndices: gameState.shuffledIndices,
                    phase: gameState.phase,
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
                canHint:
                    gameState.cauris >= 20 &&
                    gameState.hintRevealedCount <
                        widget.args.devinette.answer.length &&
                    gameState.phase == GamePhase.playing,
                canValidate:
                    gameState.selectedIndices.isNotEmpty &&
                    gameState.phase == GamePhase.playing,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// Demande confirmation avant de quitter une partie en cours. Pas de modal
  /// si la partie est déjà terminée (won/lost) — dans ce cas, pop direct.
  Future<void> _confirmBack() async {
    final gameState = ref.read(gameControllerProvider(widget.args));
    if (gameState.phase != GamePhase.playing) {
      if (mounted) context.pop();
      return;
    }

    _pauseForModal();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.boisFonce,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.orSoleil.withValues(alpha: 0.5)),
        ),
        title: Text(
          'Quitter la partie ?',
          style: AppTypography.bebas(size: 20, color: AppColors.orSoleil),
        ),
        content: Text(
          'Tu perdras ta progression sur cette devinette.',
          style: AppTypography.crimson(
            size: 15,
            color: AppColors.textePrimaire,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(
              'QUITTER',
              style: AppTypography.bebas(
                size: 14,
                color: AppColors.texteSecondaire,
                letterSpacing: 1.5,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.vertClair,
              foregroundColor: AppColors.ivoire,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'CONTINUER',
              style: AppTypography.bebas(size: 14, letterSpacing: 1.5),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed ?? false) {
      context.pop();
    } else {
      _resumeFromModal();
    }
  }

  void _showVictoryOverlay(BuildContext ctx, int timeLeft, int starsEarned) {
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => VictoryView(
        devinette: widget.args.devinette,
        timeLeft: timeLeft,
        starsEarned: starsEarned,
        onNext: () {
          // Ferme l'overlay puis enchaîne automatiquement sur la prochaine
          // étape : devinette suivante de la même montagne, ou montagne
          // suivante si celle-ci vient d'être conquise.
          ctx.pop();
          _advanceAfterVictory();
        },
      ),
    );
  }

  /// Détermine et exécute la prochaine navigation après une victoire.
  ///
  /// - Mode Hub (sans `mountainId`) : retour au hub (legacy).
  /// - Montagne en cours non terminée : charge une devinette random du même
  ///   monde et remplace la route `/game` (re-démarre une partie fraîche).
  /// - Montagne tout juste conquise : remplace `/mountain` par la prochaine
  ///   montagne débloquée (la liste `mountainsProvider` reflète déjà la win,
  ///   `recordWin` ayant muté `playerProgressProvider` de façon synchrone).
  Future<void> _advanceAfterVictory() async {
    final mountainId = widget.args.mountainId;
    if (mountainId == null) {
      if (mounted) context.pop();
      return;
    }

    final List<Mountain> mountains;
    try {
      mountains = await ref.read(mountainsProvider.future);
    } on Exception catch (_) {
      if (mounted) context.pop();
      return;
    }
    if (!mounted) return;

    final currentIdx = mountains.indexWhere((m) => m.id == mountainId);
    if (currentIdx < 0) {
      context.pop();
      return;
    }

    final current = mountains[currentIdx];
    final mountainDone = current.completedLevels >= current.totalLevels;

    if (!mountainDone) {
      await _pushNextDevinette(mountainId);
      return;
    }

    // Cherche la prochaine montagne débloquée.
    Mountain? next;
    for (var i = currentIdx + 1; i < mountains.length; i++) {
      if (mountains[i].unlocked) {
        next = mountains[i];
        break;
      }
    }

    if (next == null) {
      // Plus de montagne accessible — retour au détail courant. On affiche
      // tout de même l'overlay de conquête car c'est probablement le sommet
      // final (Kilimandjaro).
      await _showConquestOverlay(current);
      if (!mounted) return;
      context.pop();
      return;
    }

    // Célèbre la conquête, puis bascule vers la montagne suivante.
    await _showConquestOverlay(current);
    if (!mounted) return;
    context.pop(); // /game → /mountain(courant)
    if (!mounted) return;
    context.pushReplacement(AppRoutes.mountain, extra: next);
  }

  /// Affiche l'overlay « TU AS CONQUIS » et attend que l'utilisateur tape
  /// « PROCHAINE MONTAGNE ».
  Future<void> _showConquestOverlay(Mountain conquered) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      builder: (dialogCtx) => MountainConquestView(
        mountain: conquered,
        onContinue: () => Navigator.of(dialogCtx).pop(),
      ),
    );
  }

  Future<void> _pushNextDevinette(String mountainId) async {
    try {
      final selectionService = ref.read(devinetteSelectionServiceProvider);
      final progress = ref.read(playerProgressProvider);

      // Résoudre la montagne courante pour calculer la difficulté cible.
      final asyncMountains = ref.read(mountainsProvider);
      final mountain = asyncMountains.maybeWhen(
        data: (list) => list.cast<Mountain?>().firstWhere(
          (m) => m?.id == mountainId,
          orElse: () => null,
        ),
        orElse: () => null,
      );
      // Pour la devinette suivante en chaîne, on se base sur le niveau
      // que le joueur s'apprête à atteindre (completedLevels + 1).
      // Si pas de montagne (mode Hub) → config fallback.
      final nextLevelIndex =
          mountain != null ? mountain.completedLevels + 1 : null;
      final config = mountain != null
          ? LevelDifficultyResolver.resolve(
              mountain: mountain,
              levelIndex: nextLevelIndex!,
            )
          : LevelDifficultyResolver.fallback();

      final next = await selectionService.nextDevinette(
        mix: progress.activePackMix,
        targetDifficulty: config.difficultyTier,
        wordLengthBucket: config.wordLengthBucket,
        excludeIds: progress.recentDevinetteIds.toSet(),
      );
      await ref
          .read(playerProgressProvider.notifier)
          .recordRecentDevinette(next.id);
      if (!mounted) return;
      context.pushReplacement(
        AppRoutes.game,
        extra: GameArgs(
          devinette: next,
          mountainId: mountainId,
          levelIndex: nextLevelIndex,
          config: config,
        ),
      );
    } on Exception catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur de chargement', style: AppTypography.bebas()),
          backgroundColor: AppColors.rouge,
        ),
      );
      context.pop();
    }
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
                color: AppColors.orSoleil.withValues(
                  alpha: enabled ? 0.6 : 0.2,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.play_circle_outline,
                  size: 16,
                  color: AppColors.orSoleil.withValues(
                    alpha: enabled ? 0.95 : 0.4,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '+50',
                  style: AppTypography.bebas(
                    size: 13,
                    color: AppColors.orSoleil.withValues(
                      alpha: enabled ? 0.95 : 0.4,
                    ),
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
                    color: AppColors.orSoleil.withValues(
                      alpha: enabled ? 0.95 : 0.4,
                    ),
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
    this.mountainName,
    this.levelLabel,
    this.flagEmoji,
  });

  final int cauris;
  final VoidCallback onBack;

  /// Nom de la montagne en cours (ex. "MONT NIMBA"). `null` en mode Hub.
  final String? mountainName;

  /// Sous-titre niveau (ex. "Niveau 3/6"). `null` si pas pertinent.
  final String? levelLabel;

  /// Drapeau emoji de la montagne (ex. "🇨🇮"). `null` en mode Hub.
  final String? flagEmoji;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: AppColors.orSoleil,
            onPressed: onBack,
            tooltip: 'game.back'.tr(),
          ),
          if (flagEmoji != null) ...[
            Text(flagEmoji!, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (mountainName ?? 'KILIMANDJARO').toUpperCase(),
                  style: AppTypography.bebas(size: 18, letterSpacing: 1.5),
                  overflow: TextOverflow.ellipsis,
                ),
                if (levelLabel != null)
                  Text(
                    levelLabel!,
                    style: AppTypography.crimson(
                      size: 12,
                      color: AppColors.texteSecondaire,
                      style: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Cauris chip (la pile de cauris du joueur).
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
        border: Border.all(color: AppColors.orSoleil.withValues(alpha: 0.4)),
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

class _RiddleCard extends StatelessWidget {
  const _RiddleCard({required this.riddle});

  final String riddle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Griot avatar — réduit à 48pt pour libérer largeur texte.
          Image.asset(AppAssets.griotIdle, width: 48, height: 48),
          const SizedBox(width: 12),
          // Énoncé — bodyMd non-italique sur textePrimaire pour scan rapide.
          // L'italique est réservé aux proverbes/encouragements.
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

/// Row de badges pour les modifiers actifs (un pill par modifier).
/// Indication explicite des défis présents pour éviter les pièges
/// déloyaux : le joueur sait que le mot est à l'envers, que des lettres
/// vont bouger, que la grille va se brumer, etc.
class _ModifierBadges extends StatelessWidget {
  const _ModifierBadges({required this.modifiers});

  final Set<LevelModifier> modifiers;

  @override
  Widget build(BuildContext context) {
    // Filtre aux modifiers qui ont un effet visible côté joueur — on
    // n'affiche pas un badge pour `thinAir` (déjà perceptible via le timer
    // plus court).
    final visible = modifiers
        .where((m) => _badgeForModifier(m) != null)
        .toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final m in visible) _badgeForModifier(m)!,
        ],
      ),
    );
  }

  static Widget? _badgeForModifier(LevelModifier m) {
    switch (m) {
      case LevelModifier.reverse:
        return const _ModifierPill(
          icon: Icons.swap_horiz_rounded,
          label: "Mot à l'envers",
          color: AppColors.rouge,
        );
      case LevelModifier.wind:
        return const _ModifierPill(
          icon: Icons.air_rounded,
          label: 'Vent',
          color: AppColors.cielHauteur,
        );
      case LevelModifier.earthquake:
        return const _ModifierPill(
          icon: Icons.terrain_rounded,
          label: 'Tremblement',
          color: AppColors.laterite,
        );
      case LevelModifier.fog:
        return const _ModifierPill(
          icon: Icons.cloud_rounded,
          label: 'Brouillard',
          color: AppColors.cielHauteur,
        );
      case LevelModifier.shuffle:
        return const _ModifierPill(
          icon: Icons.shuffle_rounded,
          label: 'Remélange',
          color: AppColors.rouge,
        );
      // ignore: no_default_cases
      default:
        // thinAir + autres modifiers non-implémentés visuellement → pas
        // de badge pour l'instant. La couverture S3 se limite aux 4 cités.
        return null;
    }
  }
}

class _ModifierPill extends StatelessWidget {
  const _ModifierPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTypography.bebas().copyWith(
              fontSize: 12,
              letterSpacing: 1.1,
              color: color,
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
                    Text(label, style: AppTypography.bebas(size: 15)),
                    if (subtitle != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            subtitle!,
                            style: AppTypography.crimson(
                              size: 11,
                              color: AppColors.textePrimaire,
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
