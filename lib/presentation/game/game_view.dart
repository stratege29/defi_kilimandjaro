import 'dart:async';

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/core/utils/level_difficulty_resolver.dart';
import 'package:defi_kilimandjaro/data/ads/ads_service.dart';
import 'package:defi_kilimandjaro/data/ads/att_service.dart';
import 'package:defi_kilimandjaro/data/ads/rewarded_daily_cap_service.dart';
import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/services/devinette_selection_service_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/game_controller.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/answer_cells.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/circular_grid.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/griot_briefing_overlay.dart';
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

  /// Vrai dès que le briefing « Le griot t'avertit » a été affiché. Empêche
  /// la réapparition au [GameController.restart] (retry après échec), qui
  /// reset `_overlayShown` mais ne doit pas re-déclencher le briefing.
  bool _briefingShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Briefing du griot — si le niveau a des modifiers ou est un boss, on
    // pause le timer et on affiche un overlay narratif AVANT que le joueur
    // soit confronté à la grille. Cf. discussion produit : "no surprises".
    // Le timer démarre dans le constructeur du `GameController` (Timer.periodic
    // à 1s) ; la pause via postFrame intervient bien avant le 1er tick.
    final cfg = widget.args.config;
    final needsBriefing = cfg.isBoss || cfg.modifiers.isNotEmpty;
    if (needsBriefing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showGriotBriefing();
      });
    }
  }

  /// Affiche l'overlay de briefing modifiers/boss. Pause forcée du timer
  /// pendant l'affichage ; reprise au dismiss (tap CTA ou tap fond).
  Future<void> _showGriotBriefing() async {
    if (_briefingShown) return;
    _briefingShown = true;
    _pauseForModal();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (dialogCtx) => GriotBriefingOverlay(
        modifiers: widget.args.config.modifiers,
        isBoss: widget.args.config.isBoss,
        onConfirm: () => Navigator.of(dialogCtx).pop(),
      ),
    );
    if (!mounted) return;
    _resumeFromModal();
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
        // En mode défi du jour, on persiste le résultat via le flow
        // dédié AVANT d'afficher la victoire (l'overlay affiche le solde
        // mis à jour). Le controller a déjà skippé recordWin standard.
        if (widget.args.isDailyChallenge) {
          unawaited(
            ref
                .read(playerProgressProvider.notifier)
                .recordDailyChallengeResult(
                  date: widget.args.dailyDate!,
                  success: true,
                ),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showVictoryOverlay(
            context,
            next.timeLeft,
            next.starsEarned,
            next.caurisAwarded,
          );
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
              if (widget.args.config.isBoss ||
                  widget.args.config.modifiers.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _ModifierBadges(
                  modifiers: widget.args.config.modifiers,
                  isBoss: widget.args.config.isBoss,
                ),
              ],
              const SizedBox(height: 8),
              // Timer bar — totalTime calibré sur la config du niveau.
              TimerBar(
                timeLeft: gameState.timeLeft,
                totalTime: widget.args.config.timerSeconds,
              ),
              const SizedBox(height: 10),
              // Answer cells — quand `reverse` est actif on affiche les
              // cases dans l'ordre de saisie (mot inversé) pour que le
              // remplissage gauche→droite reste intuitif.
              AnswerCells(
                answer: gameState.expectedAnswer,
                formedLetters: gameState.formedWord,
                isValidated: gameState.validationCorrect,
              ),
              const SizedBox(height: 10),
              // Circular tile grid — `Expanded` absorbe l'espace gagné par
              // la suppression du `_RewardedAdChip` pleine-largeur (~36pt).
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
              const SizedBox(height: 10),
              // Bottom action row — [Pub?] · Indice · Effacer.
              // Le bouton Valider a été retiré (auto-validation déclenchée
              // dans `selectTile` quand `state.isComplete`). Le chip pub
              // pleine-largeur a été absorbé ici pour rendre son espace à
              // la grille. Pub gating + montant rewarded sont pilotés par
              // Remote Config via `_buildActionButtons` (cf. helper).
              _buildActionButtons(context, ref, controller, gameState),
              const SizedBox(height: 12),
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

  /// Construit la rangée d'actions (Indice / Effacer / Valider) avec la
  /// logique de coût dynamique + fallback rewarded.
  ///
  /// Cas du bouton **Indice** :
  /// - Solde >= coût indice → `useHint()` normal.
  /// - Solde < coût ET joueur peut voir une rewarded → snackbar CTA
  ///   "Regarde une pub pour gagner +N cauris". Plus doux qu'un modal forcé
  ///   et préserve la conversion IAP (le joueur garde le choix).
  /// - Solde < coût ET pas de rewarded dispo (cap atteint, killswitch,
  ///   No-Ads sans solde) → bouton réellement disabled.
  Widget _buildActionButtons(
    BuildContext context,
    WidgetRef ref,
    GameController controller,
    GameState gameState,
  ) {
    final cost = controller.nextHintCost;
    final hasLettersLeft =
        gameState.hintRevealedCount < widget.args.devinette.answer.length;
    final isPlaying = gameState.phase == GamePhase.playing;
    final canAfford = gameState.cauris >= cost;
    final progress = ref.watch(playerProgressProvider);
    final adsAllowed =
        ref.watch(canOfferRewardedProvider) && !progress.noAdsPurchased;

    // Indice gratuit du jour disponible ? Le drapeau a été crédité par
    // `claimFreeHintIfDue` au boot du home. Override le subtitle du
    // bouton pour signaler clairement la valeur "GRATUIT".
    final hasFreeHint = ref.watch(
      playerProgressProvider.select((p) => p.freeHintAvailable),
    );

    return _ActionButtons(
      hintCostLabel:
          hasFreeHint ? 'game.hint_free_badge'.tr() : '-$cost',
      onHint: () {
        // Le freebie quotidien est prioritaire sur le solde cauris.
        // `controller.useHint` appelle `spendOnHint` côté repo qui
        // consomme d'abord `freeHintAvailable` si présent.
        if (hasFreeHint || canAfford) {
          controller.useHint();
          return;
        }
        // Solde insuffisant et pas de freebie — propose la rewarded
        // sans forcer.
        final amount = ref.read(gameEconomyConfigProvider).rewardedVideoBonus;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pas assez de cauris — regarde une pub pour gagner +$amount',
              style: AppTypography.bebas(),
            ),
            backgroundColor: AppColors.boisFonce,
            duration: const Duration(milliseconds: 2000),
          ),
        );
      },
      onClear: controller.clearSelection,
      // Bouton Pub absorbé dans la row d'action — `null` quand No-Ads ou
      // killswitch / cap quotidien atteint : la row se rééquilibre sur
      // 2 colonnes (Indice + Effacer).
      onWatchAd: adsAllowed
          ? () async {
              final amount = ref
                  .read(gameEconomyConfigProvider)
                  .rewardedVideoBonus;
              final got = await ref
                  .read(adsServiceProvider)
                  .showRewardedForCauris();
              if (!context.mounted) return;
              if (got) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '+$amount Cauris de Sagesse',
                      style: AppTypography.bebas(),
                    ),
                    backgroundColor: AppColors.vertClair,
                    duration: const Duration(milliseconds: 1200),
                  ),
                );
              }
            }
          : null,
      canHint: hasLettersLeft &&
          isPlaying &&
          (hasFreeHint || canAfford || adsAllowed),
      canWatchAd: isPlaying,
    );
  }

  void _showVictoryOverlay(
    BuildContext ctx,
    int timeLeft,
    int starsEarned,
    int caurisAwarded,
  ) {
    // Compte la victoire pour la cadence interstitielle (Étape D).
    // L'incrément est fait au moment de l'overlay : si le joueur quitte
    // avant de tap SUIVANT, sa victoire compte quand même.
    ref.read(adsServiceProvider).noteVictory();

    // ATT prompt (iOS) — déclenché à partir de la 2e victoire cumulée
    // (joueur engagé). Idempotent, no-op si déjà prompted ou Android.
    final totalVictories =
        ref.read(playerProgressProvider).totalLevelsCompleted;
    if (totalVictories >= 2) {
      unawaited(
        ref.read(attServiceProvider).maybePromptAfterEngagement(),
      );
    }

    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => VictoryView(
        devinette: widget.args.devinette,
        timeLeft: timeLeft,
        caurisAwarded: caurisAwarded,
        starsEarned: starsEarned,
        isBoss: widget.args.config.isBoss,
        onNext: () async {
          // Ferme l'overlay, tente une interstitielle (transition naturelle
          // entre 2 niveaux), puis enchaîne sur la suite. Le helper skip
          // si pas atteint / min interval / killswitch / No-Ads / duel.
          ctx.pop();
          await ref.read(adsServiceProvider).maybeShowInterstitial();
          if (!mounted) return;
          await _advanceAfterVictory();
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

  /// Coût en cauris pour révéler la réponse à l'écran d'échec en zone
  /// T3+. Choisi pour rester accessible (~1 victoire T3 = 1 reveal) mais
  /// créer un vrai sink économique. Constante locale ici parce que ce
  /// levier d'équilibrage économique ne vit que dans le flow d'échec —
  /// à promouvoir vers Remote Config si on veut le tweaker à chaud.
  static const int _revealCostCauris = 50;

  /// Seuil d'échecs consécutifs sur **un même niveau** au-delà duquel la
  /// réponse est révélée gratuitement (filet anti-blocage). Combiné au
  /// reveal payant : le joueur peut soit payer plus tôt, soit insister
  /// 3 fois pour obtenir le reveal gratuit.
  static const int _autoRevealFailThreshold = 3;

  Future<void> _showFailureOverlay(
    BuildContext ctx,
    GameController controller,
  ) async {
    // Mode défi du jour : on persiste le résultat via le flow dédié,
    // **sans** toucher au compteur global `consecutiveFailures` (qui
    // sert au throttling pub côté niveau standard).
    if (widget.args.isDailyChallenge) {
      await ref
          .read(playerProgressProvider.notifier)
          .recordDailyChallengeResult(
            date: widget.args.dailyDate!,
            success: false,
          );
    } else {
      // Échec niveau standard : on incrémente seulement le compteur
      // (utilisé pour stats / titres). L'interstitielle n'est plus
      // déclenchée par les échecs (Étape D Phase 4) — punir l'échec
      // dégrade l'expérience. La pub arrive maintenant entre deux
      // niveaux après une victoire normale.
      if (!ref.read(playerProgressProvider).noAdsPurchased) {
        await ref.read(playerProgressProvider.notifier).recordFailure();
      }
    }

    // Logique de reveal (T3+ uniquement, et seulement en mode montagne
    // — le Hub n'a pas de structure progression par niveau).
    //
    // Pour les niveaux T1-T2 OU le mode Hub : on garde le comportement
    // historique (réponse révélée gratuitement à chaque échec).
    //
    // Pour T3+ avec mountainId/levelIndex : on incrémente le compteur
    // par niveau et on calcule si la réponse doit être révélée d'office
    // (filet anti-blocage à 3 échecs cumulés sur ce niveau précis).
    final mountainId = widget.args.mountainId;
    final levelIndex = widget.args.levelIndex;
    final config = widget.args.config;
    final canTrackLevel = mountainId != null && levelIndex != null;
    final isPayWallActive = !config.revealsAnswerOnFailure && canTrackLevel;

    var answerRevealed = true;
    if (isPayWallActive) {
      final newFailCount = await ref
          .read(playerProgressProvider.notifier)
          .recordLevelFailure(
            mountainId: mountainId,
            levelIndex: levelIndex,
          );
      answerRevealed = newFailCount >= _autoRevealFailThreshold;
    }

    if (!ctx.mounted) return;
    // Le `select` garantit que le `canAfford` lu reste cohérent avec
    // l'état au moment d'ouvrir le dialog. Le `FailureView` re-évalue
    // l'achat via `purchaseReveal` qui re-check le solde côté repo —
    // donc même si le joueur dépense ailleurs entre-temps, l'achat
    // est sécurisé serveur-style.
    final canAffordReveal = ref.read(
      playerProgressProvider.select((p) => p.cauris >= _revealCostCauris),
    );

    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => FailureView(
        devinette: widget.args.devinette,
        answerRevealed: answerRevealed,
        revealCost: isPayWallActive && !answerRevealed
            ? _revealCostCauris
            : null,
        canAffordReveal: canAffordReveal,
        onPurchaseReveal: isPayWallActive && !answerRevealed
            ? () => ref
                .read(playerProgressProvider.notifier)
                .purchaseReveal(_revealCostCauris)
            : null,
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
    // Header compact 1-ligne — le titre "KILIMANDJARO" a été retiré (le
    // joueur sait sur quelle montagne il est, le drapeau + numéro de niveau
    // suffisent). L'espace gagné est rendu à la devinette et à la grille.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: AppColors.orSoleil,
            onPressed: onBack,
            tooltip: 'game.back'.tr(),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          if (flagEmoji != null) ...[
            const SizedBox(width: 4),
            Text(flagEmoji!, style: const TextStyle(fontSize: 20)),
          ],
          if (levelLabel != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                levelLabel!,
                style: AppTypography.crimson(
                  size: 13,
                  color: AppColors.texteSecondaire,
                  style: FontStyle.italic,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            const Spacer(),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
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
          // Griot avatar — 44pt, gauche, sans rien ajouter en décoration.
          Image.asset(AppAssets.griotIdle, width: 44, height: 44),
          const SizedBox(width: 12),
          // Énoncé — taille remontée à 22pt pour faire de la devinette le
          // héros culturel de l'écran (cf. discussion produit). bodyMd
          // non-italique, l'italique restant réservé aux proverbes.
          Expanded(
            child: Text(
              riddle,
              style: AppTypography.bodyMd.copyWith(
                fontSize: 22,
                height: 1.35,
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
  const _ModifierBadges({required this.modifiers, this.isBoss = false});

  final Set<LevelModifier> modifiers;
  final bool isBoss;

  @override
  Widget build(BuildContext context) {
    // Filtre aux modifiers qui ont un effet visible côté joueur — on
    // n'affiche pas un badge pour `thinAir` (déjà perceptible via le timer
    // plus court).
    final visible = modifiers
        .where((m) => _badgeForModifier(m) != null)
        .toList(growable: false);
    if (visible.isEmpty && !isBoss) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          if (isBoss)
            const _ModifierPill(
              icon: Icons.workspace_premium_rounded,
              label: 'BOSS',
              color: AppColors.orJour,
            ),
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
    required this.onWatchAd,
    required this.canHint,
    required this.canWatchAd,
    required this.hintCostLabel,
  });

  final VoidCallback onHint;
  final VoidCallback onClear;

  /// Callback rewarded video — `null` quand le joueur a acheté "No Ads".
  /// Dans ce cas le bouton disparaît et la row passe sur 2 colonnes.
  final VoidCallback? onWatchAd;
  final bool canHint;
  final bool canWatchAd;

  /// Sous-titre affiché sur le bouton Indice (ex: "-20"). Dynamique pour
  /// supporter le coût progressif intra-niveau (cf. `hintCostMultiplier`).
  final String hintCostLabel;

  @override
  Widget build(BuildContext context) {
    final hasAdButton = onWatchAd != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: <Widget>[
          // Bouton Pub à gauche (loin du pouce dominant droit) en violet
          // ciel-hauteur, signalisation visuelle distincte des actions de
          // jeu pour éviter un tap parasite pendant une session.
          if (hasAdButton) ...[
            Expanded(
              child: _GameButton(
                label: 'game.watch_ad_short'.tr(),
                subtitle: '+50',
                iconData: Icons.play_circle_outline,
                color: AppColors.cielHauteur,
                enabled: canWatchAd,
                onTap: onWatchAd!,
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Bouton Indice.
          Expanded(
            child: _GameButton(
              label: 'game.hint'.tr(),
              subtitle: hintCostLabel,
              iconAsset: AppAssets.iconHint,
              color: AppColors.bois,
              enabled: canHint,
              onTap: onHint,
            ),
          ),
          const SizedBox(width: 8),
          // Bouton Effacer.
          Expanded(
            child: _GameButton(
              label: 'game.clear'.tr(),
              iconAsset: AppAssets.iconErase,
              color: AppColors.boisFonce,
              onTap: onClear,
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
    this.iconData,
    this.enabled = true,
  });

  final String label;
  final String? subtitle;

  /// Image asset (PNG sprite) — utilisé par les boutons jeu (Indice, Effacer).
  final String? iconAsset;

  /// IconData Material — fallback pour le bouton Pub qui n'a pas de sprite.
  /// Exclusif avec [iconAsset] : si les deux sont fournis [iconAsset] gagne.
  final IconData? iconData;
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
                ] else if (iconData != null) ...[
                  Icon(iconData, size: 26, color: AppColors.textePrimaire),
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
