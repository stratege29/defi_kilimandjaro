import 'dart:async';

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/constants/loss_economy.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/ads/ads_service.dart';
import 'package:defi_kilimandjaro/data/ads/rewarded_daily_cap_service.dart';
import 'package:defi_kilimandjaro/data/firebase/analytics_service.dart';
import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/local/link_prompt_gate.dart';
import 'package:defi_kilimandjaro/data/local/seen_devinette_store.dart';
import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/level_kind.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_theme.dart';
import 'package:defi_kilimandjaro/presentation/auth/link_account_prompt.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/game_controller.dart';
import 'package:defi_kilimandjaro/presentation/game/level_launcher.dart';
import 'package:defi_kilimandjaro/presentation/game/solo_combo_provider.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/answer_cells.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/circular_grid.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/first_encounter_banner.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/timer_bar.dart';
import 'package:defi_kilimandjaro/presentation/mountains/mountain_reveal_intent.dart';
import 'package:defi_kilimandjaro/presentation/result/failure_view.dart';
import 'package:defi_kilimandjaro/presentation/result/mountain_conquest_view.dart';
import 'package:defi_kilimandjaro/presentation/result/victory_banner.dart';
import 'package:defi_kilimandjaro/presentation/result/victory_view.dart';
import 'package:defi_kilimandjaro/presentation/theme/pack_background.dart';
import 'package:defi_kilimandjaro/presentation/theme/pack_theme_provider.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:defi_kilimandjaro/presentation/widgets/flag_roundel.dart';
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

  /// Modificateurs du niveau que le joueur rencontre pour la **première
  /// fois** (absents de `PlayerProgress.encounteredModifiers`) et qui ont une
  /// description joueur. Figé à l'entrée du niveau : le bandeau ne se
  /// réaffiche pas au [GameController.restart] (retry après échec) puisque le
  /// widget n'est créé qu'une fois avec la vue. Vide = aucun bandeau.
  late final Set<LevelModifier> _firstEncounter;

  /// Vrai tant que le bandeau de première rencontre tient le timer en pause.
  bool _bannerHoldsPause = false;

  /// Vrai pendant le dialog « Quitter la partie ? » — empêche le repli du
  /// bandeau de reprendre le timer sous un modal encore ouvert.
  bool _backDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Première rencontre d'un modificateur : bandeau compact non modal
    // (3 s, tap pour fermer) avec timer en pause. Plus de briefing plein
    // écran ni pour les modificateurs connus ni pour le boss : les badges
    // d'en-tête (`_ModifierBadges`) restent l'indication permanente.
    // Le timer démarre dans le constructeur du `GameController`
    // (Timer.periodic à 1 s) ; la pause via postFrame précède le 1er tick.
    final encountered = ref.read(
      playerProgressProvider.select((p) => p.encounteredModifiers),
    );
    _firstEncounter = FirstEncounterBanner.describable(
      widget.args.config.modifiers.difference(encountered),
    );
    if (_firstEncounter.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _bannerHoldsPause = true;
        _pauseForModal();
      });
    }
  }

  /// Repli du bandeau de première rencontre (auto ou tap) : mémorise les
  /// modificateurs comme rencontrés (comme l'ancien briefing, seulement au
  /// dismiss — un crash en plein affichage ne marque rien) et reprend le
  /// timer, sauf si un autre modal est ouvert.
  void _onFirstEncounterDismissed() {
    unawaited(
      ref
          .read(playerProgressProvider.notifier)
          .recordModifiersEncounter(_firstEncounter),
    );
    _bannerHoldsPause = false;
    if (!_backDialogOpen) _resumeFromModal();
  }

  /// Remet la série intra-session à zéro sur abandon (quitter confirmé, skip
  /// gratuit). Hors périmètre en défi du jour et en mode Hub.
  void _resetComboOnAbandon() {
    if (widget.args.isDailyChallenge || widget.args.mountainId == null) return;
    ref.read(soloComboProvider.notifier).reset();
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

    // Série intra-session (flamme + compteur dès 2 victoires d'affilée).
    final comboStreak = ref.watch(soloComboProvider);

    final mountainsAsync = ref.watch(mountainsProvider);
    final mountain = mountainsAsync.maybeWhen(
      data: (list) => list.cast<Mountain?>().firstWhere(
        (m) => m?.id == mountainId,
        orElse: () => null,
      ),
      orElse: () => null,
    );

    if (mountain == null) {
      return _GameHeader(
        cauris: cauris,
        onBack: _confirmBack,
        comboStreak: comboStreak,
      );
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
      countryCode: mountain.countryCode,
      comboStreak: comboStreak,
    );
  }

  /// Vrai si ce niveau est le dernier de sa montagne (la victoire déclenche
  /// la conquête). Lu sur `mountainsProvider` ; si la montagne n'est pas
  /// résolue (chargement), on considère « dernier » par prudence pour garder
  /// l'écran complet plutôt qu'une bannière avant un overlay de conquête.
  bool _isLastLevelOfMountain() {
    final mountainId = widget.args.mountainId;
    final levelIndex = widget.args.levelIndex;
    if (mountainId == null || levelIndex == null) return false;
    final mountain = ref
        .read(mountainsProvider)
        .maybeWhen(
          data: (list) => list.cast<Mountain?>().firstWhere(
            (m) => m?.id == mountainId,
            orElse: () => null,
          ),
          orElse: () => null,
        );
    if (mountain == null) return true;
    return levelIndex >= mountain.totalLevels;
  }

  @override
  Widget build(BuildContext context) {
    final provider = gameControllerProvider(widget.args);
    final gameState = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final packTheme = ref.watch(activePackThemeProvider);

    // Listen for phase transitions and show overlay exactly once per end state.
    ref.listen<GameState>(provider, (previous, next) {
      if (_overlayShown) return;
      if (next.phase == GamePhase.won &&
          (previous == null || previous.phase != GamePhase.won)) {
        _overlayShown = true;
        // Anti-répétition : marque cette devinette comme résolue dans son
        // pack. Seule une victoire effective déclenche le marquage (une
        // défaite garde la devinette ouverte pour un retry).
        // Sur une rafale ou un duo, chaque mot du niveau est marqué.
        final tracker = ref.read(seenDevinetteTrackerProvider);
        for (final d in _levelDevinettes) {
          unawaited(tracker.markSolved(packId: d.pack, devinetteId: d.id));
        }
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
          _showVictoryOverlay(context, next);
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
        backgroundColor: packTheme.background,
        body: PackBackground(
          theme: packTheme,
          child: SafeArea(
            child: Stack(
              children: <Widget>[
                Column(
                  children: <Widget>[
                    // Header — montagne en cours + niveau (au lieu du nom d'app).
                    _buildHeader(gameState.cauris),
                    const SizedBox(height: 8),
                    // Énigme(s) — selon la structure du niveau : énigme du
                    // mot en cours (rafale, avec compteur k/n), deux énigmes
                    // compactes (duo), ou énigme effaçable (boss aveugle).
                    ..._buildRiddles(gameState, controller, packTheme),
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
                    // Answer cells — quand `reverse` (« mot à l'envers ») est
                    // actif, les cases se remplissent de droite à gauche : la
                    // 1re lettre saisie va dans la dernière case, etc.
                    // En duo : une rangée par mot ; le mot trouvé reste
                    // affiché rempli (doré) jusqu'à la fin du niveau.
                    for (var w = 0; w < gameState.wordCount; w++) ...<Widget>[
                      if (w > 0) const SizedBox(height: 6),
                      AnswerCells(
                        key: ValueKey<String>(
                          'answer_${gameState.roundIndex}_$w',
                        ),
                        answer: gameState.answerFor(w),
                        formedLetters: gameState.formedFor(w),
                        isValidated:
                            gameState.validationCorrect ||
                            gameState.isSolved(w),
                        fillFromEnd: gameState.reverseAnswer,
                        revealedPositions: gameState.revealedFor(w),
                        theme: packTheme,
                      ),
                    ],
                    const SizedBox(height: 10),
                    // Circular tile grid — `Expanded` absorbe l'espace gagné par
                    // la suppression du `_RewardedAdChip` pleine-largeur (~36pt).
                    Expanded(
                      child: Center(
                        child: CircularGrid(
                          theme: packTheme,
                          letters: gameState.displayLetters,
                          selectedIndices: gameState.selectedIndices,
                          hiddenIndices: gameState.hiddenTileIndices,
                          spiritIndex: gameState.spiritHiddenIndex,
                          mirageIndices: gameState.mirageGridIndices,
                          rainBlurActive: gameState.rainBlurActive,
                          shuffledIndices: gameState.shuffledIndices,
                          phase: gameState.phase,
                          onTileEntered: controller.selectTile,
                          onTrailSelfIntersectingChanged:
                              controller.updateTrailSelfIntersecting,
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
                // Bandeau de première rencontre — superposé sous l'en-tête,
                // sans décaler la mise en page quand il se replie.
                if (_firstEncounter.isNotEmpty)
                  Positioned(
                    top: 48,
                    left: 16,
                    right: 16,
                    child: FirstEncounterBanner(
                      modifiers: _firstEncounter,
                      onDismissed: _onFirstEncounterDismissed,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Devinettes effectivement jouées sur ce niveau (même règle que le
  /// controller) : toutes celles d'une rafale ou d'un duo, la principale
  /// seule sinon.
  List<Devinette> get _levelDevinettes => widget.args.config.kind.isMultiWord
      ? widget.args.allDevinettes
      : <Devinette>[widget.args.devinette];

  /// Bloc énigme(s) du haut d'écran selon `config.kind`.
  List<Widget> _buildRiddles(
    GameState gameState,
    GameController controller,
    PackTheme packTheme,
  ) {
    final kind = widget.args.config.kind;
    if (gameState.isDuo) {
      final second = gameState.secondDevinette!;
      return <Widget>[
        _RiddleCard(
          riddle: gameState.devinette.riddle,
          theme: packTheme,
          compact: true,
          solved: gameState.isSolved(0),
        ),
        const SizedBox(height: 6),
        _RiddleCard(
          riddle: second.riddle,
          theme: packTheme,
          compact: true,
          showKili: false,
          solved: gameState.isSolved(1),
        ),
      ];
    }
    if (kind == LevelKind.blindBoss) {
      return <Widget>[
        _BlindRiddleCard(
          riddle: gameState.devinette.riddle,
          theme: packTheme,
          visible: gameState.riddleVisible,
          rereadCount: gameState.rereadCount,
          onReread: controller.rereadRiddle,
        ),
      ];
    }
    return <Widget>[
      _RiddleCard(riddle: gameState.devinette.riddle, theme: packTheme),
      if (gameState.roundCount > 1) ...<Widget>[
        const SizedBox(height: 6),
        _RafaleProgress(
          current: gameState.roundIndex + 1,
          total: gameState.roundCount,
        ),
      ],
    ];
  }

  /// Demande confirmation avant de quitter une partie en cours. Pas de modal
  /// si la partie est déjà terminée (won/lost) — dans ce cas, pop direct.
  Future<void> _confirmBack() async {
    final gameState = ref.read(gameControllerProvider(widget.args));
    if (gameState.phase != GamePhase.playing) {
      // Sortie après un échec (dialogue d'échec fermé au retour système,
      // puis second retour) : c'est un abandon. Après une victoire, non.
      if (gameState.phase == GamePhase.lost) {
        _logLevelAbandoned(AnalyticsKeys.abandonReasonQuitAfterFailure);
      }
      if (mounted) context.pop();
      return;
    }

    _backDialogOpen = true;
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
          style: AppTypography.crimson(size: 15),
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

    _backDialogOpen = false;
    if (!mounted) return;
    if (confirmed ?? false) {
      _logLevelAbandoned(AnalyticsKeys.abandonReasonQuit);
      _resetComboOnAbandon();
      context.pop();
    } else if (!_bannerHoldsPause) {
      _resumeFromModal();
    }
  }

  /// Émet `level_abandoned` (fail-soft, non bloquant). Mesure la lassitude
  /// par `level_index` et `tier` : rapporté à `level_won`, donne le taux
  /// d'abandon de chaque position dans l'ascension.
  void _logLevelAbandoned(String reason) {
    final gameState = ref.read(gameControllerProvider(widget.args));
    final mountainId = widget.args.mountainId;
    final levelIndex = widget.args.levelIndex;
    final failsOnLevel = mountainId != null && levelIndex != null
        ? ref
              .read(playerProgressProvider)
              .failsOnLevel(mountainId: mountainId, levelIndex: levelIndex)
        : 0;
    unawaited(
      ref
          .read(analyticsServiceProvider)
          .logLevelAbandoned(
            tier: widget.args.config.difficultyTier,
            reason: reason,
            timeLeft: gameState.timeLeft,
            hintsUsed: gameState.hintRevealedCount,
            failsOnLevel: failsOnLevel,
            isDaily: widget.args.isDailyChallenge,
            kind: widget.args.config.kind.name,
            exposed: widget.args.isExposed,
            levelIndex: levelIndex,
            mountainId: mountainId,
          ),
    );
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
    final hasLettersLeft = gameState.canRevealMore;
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
      hintCostLabel: hasFreeHint ? 'game.hint_free_badge'.tr() : '-$cost',
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
      // Mélanger gratuit, une fois par niveau (rendu par `restart`).
      onShuffle: controller.shuffleByPlayer,
      canShuffle: isPlaying && !gameState.shuffleUsed,
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
      canHint:
          hasLettersLeft &&
          isPlaying &&
          (hasFreeHint || canAfford || adsAllowed),
      canWatchAd: isPlaying,
    );
  }

  void _showVictoryOverlay(BuildContext ctx, GameState won) {
    // Compte la victoire pour la cadence interstitielle (Étape D).
    // L'incrément est fait au moment de l'overlay : si le joueur quitte
    // avant de tap SUIVANT, sa victoire compte quand même.
    ref.read(adsServiceProvider).noteVictory();

    // (ATT est désormais demandé au démarrage, avant l'init AdMob —
    // cf. main.dart / AttService.ensureRequested. Plus de gate victoire.)

    // Suite du flux — strictement identique bannière / écran complet :
    // ferme l'overlay, tente une interstitielle (transition naturelle entre
    // 2 niveaux), puis enchaîne. Le helper skip si pas atteint / min
    // interval / killswitch / No-Ads / duel.
    Future<void> onNext() async {
      ctx.pop();
      await ref.read(adsServiceProvider).maybeShowInterstitial();
      if (!mounted) return;
      await _advanceAfterVictory();
    }

    // Écran complet (Kili, explication, proverbe) réservé aux moments qui
    // le méritent : boss, défi du jour, dernier niveau d'une montagne.
    // Les 200+ niveaux ordinaires passent par la bannière compacte.
    final isBoss = widget.args.config.isBoss;
    final needsFullView =
        isBoss || widget.args.isDailyChallenge || _isLastLevelOfMountain();

    if (needsFullView) {
      showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        builder: (_) => VictoryView(
          devinette: won.devinette,
          devinettes: _levelDevinettes,
          timeLeft: won.timeLeft,
          caurisAwarded: won.caurisAwarded,
          freehandBonus: won.freehandBonusAwarded,
          perfectBonus: won.perfectBonusAwarded,
          comboStreak: won.comboStreak,
          comboMultiplier: won.comboMultiplierApplied,
          starsEarned: won.starsEarned,
          isBoss: isBoss,
          onNext: onNext,
        ),
      );
      return;
    }

    // Éligibilité « Doubler » — mêmes conditions que `VictoryView` : flag
    // Remote Config, pas de No-Ads, killswitch off, cap quotidien non
    // atteint. Le crédit passe par le même `showRewardedForCauris`.
    final canDouble =
        ref.read(gameEconomyConfigProvider).rewardedDoubleEnabled &&
        !ref.read(playerProgressProvider).noAdsPurchased &&
        ref.read(canOfferRewardedProvider);
    final bonus = won.caurisAwarded;

    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      // Voile léger : la grille reste visible derrière la bannière.
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => VictoryBanner(
        devinette: won.devinette,
        devinettes: _levelDevinettes,
        caurisAwarded: bonus,
        freehandBonus: won.freehandBonusAwarded,
        perfectBonus: won.perfectBonusAwarded,
        comboStreak: won.comboStreak,
        comboMultiplier: won.comboMultiplierApplied,
        starsEarned: won.starsEarned,
        doubleReward: canDouble && bonus > 0
            ? () => ref
                  .read(adsServiceProvider)
                  .showRewardedForCauris(caurisReward: bonus)
            : null,
        onNext: onNext,
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
      await _pushNextLevel(current);
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
      await maybeShowLinkAccountPrompt(
        context,
        ref,
        LinkPromptTrigger.mountainComplete,
      );
      if (!mounted) return;
      context.pop();
      return;
    }

    // Célèbre la conquête, propose (si pertinent) de sauvegarder la
    // progression, puis bascule vers la montagne suivante.
    await _showConquestOverlay(current);
    if (!mounted) return;
    await maybeShowLinkAccountPrompt(
      context,
      ref,
      LinkPromptTrigger.mountainComplete,
    );
    if (!mounted) return;
    // Bascule vers l'écran SOMMETS (pas le détail) en RÉINITIALISANT la pile à
    // [Sommets]. `go()` remplace toute la pile en UNE opération atomique : peu
    // importe d'où la partie a été lancée (accueil « continuer l'ascension »,
    // défi du jour, ou /mountain), pas besoin de `pop()` préalable.
    //
    // Le MountainRevealIntent déclenche l'animation d'ascension : l'écran
    // Sommets se pose sur la montagne conquise (`current`), marque une pause,
    // puis scrolle jusqu'à la nouvelle montagne (`next`) — le joueur voit la
    // belle UI Sommets au lieu d'atterrir directement dans le détail. Il tape
    // ensuite lui-même la montagne pour entrer. « Retour » ramène à l'accueil.
    context.go(
      AppRoutes.mountains,
      extra: MountainRevealIntent(fromId: current.id, toId: next.id),
    );
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

  /// Enchaîne sur le niveau suivant de [mountain] (`completedLevels + 1`,
  /// déjà mis à jour par `recordWin`) en remplaçant la route `/game`
  /// courante. Tirage, embranchement « voie exposée » et structure du
  /// niveau sont gérés par le lanceur commun ; si celui-ci n'a pas navigué
  /// (dialogue refermé, tirage épuisé), on ressort de la partie.
  Future<void> _pushNextLevel(Mountain mountain) async {
    final launched = await launchMountainLevel(
      context,
      ref,
      mountain: mountain,
      levelIndex: mountain.completedLevels + 1,
      replace: true,
    );
    if (!launched && mounted) context.pop();
  }

  /// Seuil d'échecs consécutifs sur **un même niveau** au-delà duquel la
  /// réponse est révélée gratuitement (filet anti-blocage). Combiné au
  /// reveal payant : le joueur peut soit payer plus tôt, soit insister
  /// 3 fois pour obtenir le reveal gratuit.
  static const int _autoRevealFailThreshold = 3;

  Future<void> _showFailureOverlay(
    BuildContext ctx,
    GameController controller,
  ) async {
    // Devinette montrée / révélée à l'échec : le mot en cours d'une rafale,
    // le premier mot non trouvé d'un duo, l'unique sinon.
    final devinette = ref
        .read(gameControllerProvider(widget.args))
        .focusDevinette;
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
      // Anti-tilt : incrémente les défaites consécutives sur cette
      // devinette (sans pénalité cauris). Au seuil, l'écran d'échec
      // proposera un skip gratuit. Hors défi du jour (flow dédié).
      await ref
          .read(playerProgressProvider.notifier)
          .recordSoloLoss(devinetteId: devinette.id);
    }

    // Logique de reveal (T2+ uniquement, et seulement en mode montagne
    // — le Hub n'a pas de structure progression par niveau).
    //
    // Pour les niveaux T1 OU le mode Hub : on garde le comportement
    // d'amorçage (réponse révélée gratuitement à chaque échec).
    //
    // Pour T2+ avec mountainId/levelIndex : on incrémente le compteur
    // par niveau et on calcule si la réponse doit être révélée d'office
    // (filet anti-blocage à 3 échecs cumulés sur ce niveau précis).
    final mountainId = widget.args.mountainId;
    final levelIndex = widget.args.levelIndex;
    final config = widget.args.config;
    final canTrackLevel = mountainId != null && levelIndex != null;
    final isPayWallActive = !config.revealsAnswerOnFailure && canTrackLevel;

    // Coût de la révélation, scalé par le tier du niveau si activé en
    // Remote Config (`eco_sink_tier_scaling`) : un reveal coûte ≈ une
    // victoire propre au tier, vs un prix plat qui devient trivial en
    // late-game. Lu une fois ici — le flow d'échec n'évolue pas en cours.
    final revealCostCauris = ref
        .read(gameEconomyConfigProvider)
        .revealCost(tierMultiplier: config.caurisMultiplier);

    var answerRevealed = true;
    if (isPayWallActive) {
      final newFailCount = await ref
          .read(playerProgressProvider.notifier)
          .recordLevelFailure(mountainId: mountainId, levelIndex: levelIndex);
      answerRevealed = newFailCount >= _autoRevealFailThreshold;
    }

    // Anti-farm : dès que la réponse est révélée (mode T1/Hub où elle l'est
    // d'office, ou auto-reveal au seuil d'échecs), on marque la devinette
    // comme « récompense consommée » — reformer ensuite le mot révélé, ou
    // rejouer cette devinette, ne rapportera plus de cauris. Hors défi du
    // jour (récompense gérée par date, pas par devinette).
    if (answerRevealed && !widget.args.isDailyChallenge) {
      await ref
          .read(playerProgressProvider.notifier)
          .markDevinetteRewarded(devinette.id);
    }

    if (!ctx.mounted) return;
    // Le `select` garantit que le `canAfford` lu reste cohérent avec
    // l'état au moment d'ouvrir le dialog. Le `FailureView` re-évalue
    // l'achat via `purchaseReveal` qui re-check le solde côté repo —
    // donc même si le joueur dépense ailleurs entre-temps, l'achat
    // est sécurisé serveur-style.
    final canAffordReveal = ref.read(
      playerProgressProvider.select((p) => p.cauris >= revealCostCauris),
    );

    // Anti-tilt : skip gratuit proposé dès que les défaites consécutives
    // sur cette devinette atteignent le seuil (hors défi du jour — déjà
    // exclu de `recordSoloLoss` ci-dessus, donc le compteur y reste à 0).
    final devinetteId = devinette.id;
    final showSkip = ref.read(
      playerProgressProvider.select(
        (p) => p.consecutiveLossesOn(devinetteId) >= kFreeSkipLossThreshold,
      ),
    );

    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => FailureView(
        devinette: devinette,
        answerRevealed: answerRevealed,
        revealCost: isPayWallActive && !answerRevealed
            ? revealCostCauris
            : null,
        canAffordReveal: canAffordReveal,
        onPurchaseReveal: isPayWallActive && !answerRevealed
            ? () async {
                // Analytics : taux d'achat de révélation par variante A/B.
                unawaited(
                  ref
                      .read(analyticsServiceProvider)
                      .logAnswerRevealed(
                        tier: config.difficultyTier,
                        cost: revealCostCauris,
                      ),
                );
                final notifier = ref.read(playerProgressProvider.notifier);
                final ok = await notifier.purchaseReveal(revealCostCauris);
                if (ok) {
                  // Anti-farm : reveal payé → récompense de cette devinette
                  // consommée (reformer le mot révélé ne rapportera rien).
                  await notifier.markDevinetteRewarded(devinette.id);
                }
                return ok;
              }
            : null,
        onRetry: () {
          ctx.pop(); // closes dialog
          _overlayShown = false;
          controller.restart();
        },
        onSkip: showSkip
            ? () {
                // Reset du compteur (sans pénalité), ferme l'échec puis
                // ressort de la partie : le prochain tirage — désormais
                // filtré par le seen-tracker — servira une devinette
                // fraîche.
                _logLevelAbandoned(AnalyticsKeys.abandonReasonSkipFree);
                _resetComboOnAbandon();
                unawaited(
                  ref
                      .read(playerProgressProvider.notifier)
                      .recordSoloSkipFree(devinetteId: devinetteId),
                );
                ctx
                  ..pop() // closes dialog
                  ..pop(); // exits game view
              }
            : null,
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
    this.countryCode,
    this.comboStreak = 0,
  });

  final int cauris;
  final VoidCallback onBack;

  /// Série intra-session de victoires (flamme + compteur affichés dès 2).
  final int comboStreak;

  /// Nom de la montagne en cours (ex. "MONT NIMBA"). `null` en mode Hub.
  final String? mountainName;

  /// Sous-titre niveau (ex. "Niveau 3/6"). `null` si pas pertinent.
  final String? levelLabel;

  /// Code pays ISO-2 de la montagne (ex. "CI"). `null` en mode Hub.
  /// Rendu via [FlagRoundel] (vectoriel) — fini l'emoji drapeau.
  final String? countryCode;

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
          if (countryCode != null) ...[
            const SizedBox(width: 4),
            FlagRoundel(countryCode: countryCode!, size: 26),
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
          if (comboStreak >= 2) ...<Widget>[
            const SizedBox(width: 8),
            _ComboChip(streak: comboStreak),
          ],
          const SizedBox(width: 8),
          // Cauris chip (la pile de cauris du joueur).
          _CaurisChip(cauris: cauris),
        ],
      ),
    );
  }
}

/// Flamme + compteur de série intra-session (visible dès 2 victoires
/// d'affilée). Couleur kola pour se distinguer du chip cauris doré.
class _ComboChip extends StatelessWidget {
  const _ComboChip({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.kola.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.kola.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.local_fire_department_rounded,
            size: 15,
            color: AppColors.kola,
          ),
          const SizedBox(width: 3),
          Text(
            '×$streak',
            style: AppTypography.bebas(size: 14, color: AppColors.kola),
          ),
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
  const _RiddleCard({
    required this.riddle,
    required this.theme,
    this.compact = false,
    this.showKili = true,
    this.solved = false,
  });

  final String riddle;
  final PackTheme theme;

  /// Duo : énoncé plus petit et padding réduit pour loger deux cartes.
  final bool compact;

  /// Kili « peek » sur le bord supérieur (une seule fois par écran).
  final bool showKili;

  /// Duo : mot déjà trouvé — la carte s'estompe et se coche.
  final bool solved;

  @override
  Widget build(BuildContext context) {
    final fontSize = compact ? 16.0 : 22.0;
    final padding = compact
        ? EdgeInsets.fromLTRB(16, showKili ? 18 : 10, 18, 10)
        : const EdgeInsets.fromLTRB(16, 28, 18, 16);
    // Carte devinette — accent gauche (3pt) sur fond de bulle, couleurs pilotées
    // par le skin du pack (défaut = surfaceContainer / or / crème historiques).
    // Plus de bordure dorée pleine : la hiérarchie vient de l'accent + ombre.
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: <Widget>[
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: ColoredBox(
              color: theme.bubbleBackground,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Filet d'accent pleine hauteur (couleur du skin).
                    Container(width: 3, color: theme.bubbleAccent),
                    Expanded(
                      child: Padding(
                        padding: padding,
                        // Énoncé — 22pt, héros culturel de l'écran. Padding
                        // haut majoré pour laisser respirer Kili posé sur
                        // le bord supérieur.
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                riddle,
                                style: AppTypography.bodyMd.copyWith(
                                  fontSize: fontSize,
                                  height: 1.35,
                                  color: solved
                                      ? theme.bubbleText.withValues(alpha: 0.55)
                                      : theme.bubbleText,
                                ),
                              ),
                            ),
                            if (solved) ...<Widget>[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 20,
                                color: AppColors.orSoleil,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Kili « peek » — à cheval sur le bord supérieur de la bulle, comme
        // s'il grimpait pour lire l'énoncé avec le joueur. `top: -37` cale
        // la bordure de la rampe (dans le PNG source) sur le bord réel de la
        // carte (même calcul que le CTA GRIMPER). `IgnorePointer` : purement
        // décoratif.
        if (showKili)
          Positioned(
            top: -37,
            child: IgnorePointer(
              child: Image.asset(
                AppAssets.kiliPeek,
                width: 84,
                height: 43,
                fit: BoxFit.contain,
              ),
            ),
          ),
      ],
    );
  }
}

/// Compteur « Mot k/n » d'une rafale, sous l'énigme.
class _RafaleProgress extends StatelessWidget {
  const _RafaleProgress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (var i = 1; i <= total; i++) ...<Widget>[
          if (i > 1) const SizedBox(width: 6),
          Container(
            width: i == current ? 18 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i <= current
                  ? AppColors.orSoleil
                  : AppColors.orSoleil.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
        const SizedBox(width: 10),
        Text(
          'game.rafale_progress'.tr(
            namedArgs: <String, String>{
              'current': '$current',
              'total': '$total',
            },
          ),
          style: AppTypography.bebas(
            size: 13,
            color: AppColors.orSoleil,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Énigme du boss aveugle : le texte s'estompe (fondu) quand
/// `GameController` la masque ; un bouton « Relire » la réaffiche via
/// [onReread]. Le coût des relectures suivantes est affiché sur le bouton.
class _BlindRiddleCard extends StatelessWidget {
  const _BlindRiddleCard({
    required this.riddle,
    required this.theme,
    required this.visible,
    required this.rereadCount,
    required this.onReread,
  });

  final String riddle;
  final PackTheme theme;
  final bool visible;
  final int rereadCount;
  final VoidCallback onReread;

  @override
  Widget build(BuildContext context) {
    final reread = 'game.blind_reread'.tr();
    final cost = 'game.blind_reread_cost'.tr(
      namedArgs: <String, String>{
        'seconds': '${GameController.blindRereadCostSeconds}',
      },
    );
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        // La carte garde sa place : seul le texte s'estompe, pour ne pas
        // faire sauter la grille.
        AnimatedOpacity(
          opacity: visible ? 1 : 0.06,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          child: _RiddleCard(riddle: riddle, theme: theme),
        ),
        if (!visible)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'game.blind_hidden'.tr(),
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.texteSecondaire,
                ),
              ),
              const SizedBox(height: 6),
              ElevatedButton.icon(
                onPressed: onReread,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orSoleil,
                  foregroundColor: AppColors.boisFonce,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: Text(
                  rereadCount == 0 ? reread : '$reread · $cost',
                  style: AppTypography.bebas(size: 14, letterSpacing: 1.5),
                ),
              ),
            ],
          ),
      ],
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

  /// Libellé i18n d'un modificateur (`game.briefing.modifier.<clé>.name`,
  /// mêmes clés que `FirstEncounterBanner`).
  static String _nameOf(String i18nKey) =>
      'game.briefing.modifier.$i18nKey.name'.tr();

  static Widget? _badgeForModifier(LevelModifier m) {
    switch (m) {
      case LevelModifier.reverse:
        return _ModifierPill(
          icon: Icons.swap_horiz_rounded,
          label: _nameOf('reverse'),
          color: AppColors.rouge,
        );
      case LevelModifier.wind:
        return _ModifierPill(
          icon: Icons.air_rounded,
          label: _nameOf('wind'),
          color: AppColors.cielHauteur,
        );
      case LevelModifier.earthquake:
        return _ModifierPill(
          icon: Icons.terrain_rounded,
          label: _nameOf('earthquake'),
          color: AppColors.laterite,
        );
      case LevelModifier.fog:
        return _ModifierPill(
          icon: Icons.cloud_rounded,
          label: _nameOf('fog'),
          color: AppColors.cielHauteur,
        );
      case LevelModifier.shuffle:
        return _ModifierPill(
          icon: Icons.shuffle_rounded,
          label: _nameOf('shuffle'),
          color: AppColors.rouge,
        );
      case LevelModifier.mirage:
        return _ModifierPill(
          icon: Icons.wb_sunny_rounded,
          label: _nameOf('mirage'),
          color: AppColors.savanneOcre,
        );
      case LevelModifier.rain:
        return _ModifierPill(
          icon: Icons.water_drop_rounded,
          label: _nameOf('rain'),
          color: AppColors.info,
        );
      case LevelModifier.spirit:
        return _ModifierPill(
          icon: Icons.auto_awesome_rounded,
          label: _nameOf('spirit'),
          color: AppColors.esprit,
        );
      // ignore: no_default_cases
      default:
        // thinAir + modifiers sans runtime (lava, ice, …) → pas de badge.
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
    required this.onShuffle,
    required this.onWatchAd,
    required this.canHint,
    required this.canWatchAd,
    required this.canShuffle,
    required this.hintCostLabel,
  });

  final VoidCallback onHint;
  final VoidCallback onClear;

  /// Mélanger gratuit (une fois par niveau) — cf. `GameController.shuffleByPlayer`.
  final VoidCallback onShuffle;
  final bool canShuffle;

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
          // Bouton Mélanger — carré compact (icône + libellé réduit) pour
          // tenir sur 4 colonnes quand le bouton Pub est présent.
          _ShuffleButton(enabled: canShuffle, onTap: onShuffle),
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

/// Bouton « Mélanger » compact — gratuit, une seule fois par niveau. Grisé
/// une fois consommé (ré-armé par `restart`).
class _ShuffleButton extends StatelessWidget {
  const _ShuffleButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          key: const ValueKey<String>('game_shuffle_button'),
          width: 64,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.bois,
            borderRadius: BorderRadius.circular(10),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                offset: const Offset(0, 2),
                blurRadius: 6,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(
                Icons.shuffle_rounded,
                size: 22,
                color: AppColors.textePrimaire,
              ),
              const SizedBox(height: 2),
              Text('MÉLANGER', style: AppTypography.bebas(size: 9)),
            ],
          ),
        ),
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
                // `Flexible` + ellipse : un libellé long (traduction, clé
                // i18n brute) se tronque au lieu de déborder du bouton sur
                // les petits écrans (4 boutons sur 375 pt).
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        label,
                        style: AppTypography.bebas(size: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                subtitle!,
                                style: AppTypography.crimson(size: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 3),
                            const CaurisIcon(size: 11),
                          ],
                        ),
                    ],
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
