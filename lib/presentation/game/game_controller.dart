import 'dart:async';
import 'dart:math';

import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/audio/tempo_scheduler.dart';
import 'package:defi_kilimandjaro/data/firebase/analytics_service.dart';
import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/game_economy_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/level_star_rating.dart';
import 'package:defi_kilimandjaro/domain/services/daily_challenge_service.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Phase du cycle de vie d'une partie.
enum GamePhase { playing, validating, won, lost }

/// État immutable d'une partie en cours.
class GameState {
  const GameState({
    required this.devinette,
    required this.selectedIndices,
    required this.timeLeft,
    required this.phase,
    required this.cauris,
    required this.shuffledIndices,
    required this.effectivePool,
    this.hintRevealedCount = 0,
    this.revealedPositions = const <int>{},
    this.validationCorrect = false,
    this.reverseAnswer = false,
    this.starsEarned = 0,
    this.fogHiddenIndices = const <int>{},
    this.caurisAwarded = 0,
  });

  final Devinette devinette;

  /// Indices (dans shuffledIndices) des tuiles sélectionnées dans l'ordre.
  final List<int> selectedIndices;

  final int timeLeft;
  final GamePhase phase;
  final int cauris;

  /// Pool effectif affiché dans la grille : lettres de `devinette.answer`
  /// + N lettres parasites (cf. `LevelDifficultyConfig.distractorCount`).
  /// Reste fixé au début de la partie, identique à `devinette.lettersPool`
  /// quand `distractorCount == 0`.
  final List<String> effectivePool;

  /// Permutation des indices de [effectivePool] (Fisher-Yates au départ).
  final List<int> shuffledIndices;

  /// Nombre de lettres révélées par l'indice. Égal à `revealedPositions.length`
  /// ; conservé comme compteur pour le scaling du coût et le calcul des
  /// étoiles (« sans indice »).
  final int hintRevealedCount;

  /// Positions (dans [expectedAnswer]) révélées par l'indice. Chaque appel à
  /// [GameController.useHint] place une lettre correcte dans une case encore
  /// non révélée tirée au hasard. `AnswerCells` l'affiche en aperçu fantôme
  /// (avec une animation pop + flip) jusqu'à ce que le joueur forme
  /// réellement la lettre dans la roue.
  final Set<int> revealedPositions;

  /// Vrai juste après une validation correcte (pour déclencher le flash).
  final bool validationCorrect;

  /// Modifier `reverse` actif : le joueur doit former le mot inversé.
  /// La validation et la révélation par indice itèrent sur
  /// `devinette.answer` lu de droite à gauche.
  final bool reverseAnswer;

  /// Nombre d'étoiles obtenues une fois la partie en phase `won`
  /// (0 sinon). Calculé une seule fois lors de la validation (cf.
  /// `LevelStarRating.computeStars`).
  final int starsEarned;

  /// Indices grille (positions dans [shuffledIndices]) actuellement
  /// masqués par le modifier `fog`. Le widget `CircularGrid` rend ces
  /// tuiles avec opacité 0 et ignore les taps dessus. Rotation 5 s côté
  /// controller. Vide quand le modifier n'est pas actif.
  final Set<int> fogHiddenIndices;

  /// Cauris crédités à la **dernière** victoire (= delta, pas solde
  /// cumulé). Lu par `VictoryView` pour animer le chip "+N CAURIS" et
  /// servir de base au bouton "Doubler la récompense". 0 tant que la
  /// partie n'est pas en phase `won`.
  final int caurisAwarded;

  /// Séquence de lettres attendue compte tenu du modifier `reverse`.
  /// Stockée comme String pour permettre l'égalité directe avec
  /// [formedWord] et le placement des lettres par indice ([revealedPositions]).
  String get expectedAnswer => reverseAnswer
      ? String.fromCharCodes(devinette.answer.runes.toList().reversed)
      : devinette.answer;

  /// Lettres dans l'ordre shufflé (inclut les distracteurs si présents).
  List<String> get displayLetters => shuffledIndices
      .map((i) => effectivePool[i])
      .toList(growable: false);

  /// Mot formé par les indices sélectionnés (lettres dans l'ordre de sélection).
  /// Inclut les distracteurs si le joueur en tape un — la validation
  /// le rejettera puisque le mot formé ne matchera plus `expectedAnswer`.
  String get formedWord => selectedIndices
      .map((si) => effectivePool[shuffledIndices[si]])
      .join();

  bool get isComplete => selectedIndices.length == devinette.answer.length;

  GameState copyWith({
    Devinette? devinette,
    List<int>? selectedIndices,
    int? timeLeft,
    GamePhase? phase,
    int? cauris,
    List<int>? shuffledIndices,
    List<String>? effectivePool,
    int? hintRevealedCount,
    Set<int>? revealedPositions,
    bool? validationCorrect,
    bool? reverseAnswer,
    int? starsEarned,
    Set<int>? fogHiddenIndices,
    int? caurisAwarded,
  }) {
    return GameState(
      devinette: devinette ?? this.devinette,
      selectedIndices: selectedIndices ?? this.selectedIndices,
      timeLeft: timeLeft ?? this.timeLeft,
      phase: phase ?? this.phase,
      cauris: cauris ?? this.cauris,
      shuffledIndices: shuffledIndices ?? this.shuffledIndices,
      effectivePool: effectivePool ?? this.effectivePool,
      hintRevealedCount: hintRevealedCount ?? this.hintRevealedCount,
      revealedPositions: revealedPositions ?? this.revealedPositions,
      validationCorrect: validationCorrect ?? this.validationCorrect,
      reverseAnswer: reverseAnswer ?? this.reverseAnswer,
      starsEarned: starsEarned ?? this.starsEarned,
      fogHiddenIndices: fogHiddenIndices ?? this.fogHiddenIndices,
      caurisAwarded: caurisAwarded ?? this.caurisAwarded,
    );
  }
}

/// Contrôleur principal de l'écran de jeu (cf. plan.md §2 Phase 1.2).
///
/// - Timer adaptatif provenant de `args.config.timerSeconds`
///   (cf. `LevelDifficultyResolver`).
/// - Sélection par index (pas par lettre) pour gérer les doublons.
/// - Auto-validation quand [selectedIndices.length == answer.length].
/// - Modifier `reverse` : la validation compare au mot inversé et
///   l'ordre des lettres révélées par l'indice suit le mot inversé.
/// - Récompense finale multipliée par `args.config.caurisMultiplier`
///   pour valoriser les niveaux difficiles.
class GameController extends StateNotifier<GameState> {
  GameController(
    this._args,
    this._audio,
    this._progress,
    this._economy,
    this._analytics,
    this._tempo,
  ) : super(
        _initialState(_args, _progress.state.cauris),
      ) {
    _startTimer();
    _startModifierTimer();
  }

  /// Construit l'état initial : génère les distracteurs selon la config,
  /// shuffle le pool effectif, applique le flag reverse. Extrait pour
  /// être réutilisable par [restart].
  static GameState _initialState(GameArgs args, int cauris) {
    final rng = Random();
    final effectivePool = _buildEffectivePool(
      original: args.devinette.lettersPool,
      answer: args.devinette.answer,
      distractorCount: args.config.distractorCount,
      rng: rng,
    );
    return GameState(
      devinette: args.devinette,
      selectedIndices: const <int>[],
      timeLeft: args.config.timerSeconds,
      phase: GamePhase.playing,
      cauris: cauris,
      effectivePool: effectivePool,
      shuffledIndices: _shuffleIndices(effectivePool.length, rng),
      reverseAnswer: args.config.hasReverse,
    );
  }

  /// Génère le pool effectif = pool original + N distracteurs aléatoires
  /// pris dans l'alphabet français hors lettres de `answer` (pour ne pas
  /// créer d'ambiguïté avec les lettres légitimes du mot — un distracteur
  /// 'O' alors que le mot contient déjà 'O' pourrait piéger le `hint`).
  static List<String> _buildEffectivePool({
    required List<String> original,
    required String answer,
    required int distractorCount,
    required Random rng,
  }) {
    if (distractorCount <= 0) return List<String>.from(original);
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final excluded = answer.toUpperCase().split('').toSet();
    final available = alphabet
        .split('')
        .where((l) => !excluded.contains(l))
        .toList(growable: false);
    final picks = List<String>.from(available)..shuffle(rng);
    return <String>[
      ...original,
      ...picks.take(distractorCount),
    ];
  }

  static const int _windPeriodSeconds = 8;
  static const int _earthquakePeriodSeconds = 6;
  static const int _fogPeriodSeconds = 5;
  static const int _shufflePeriodSeconds = 15;

  final GameArgs _args;
  final AudioController _audio;
  final PlayerProgressNotifier _progress;

  /// Snapshot Remote Config capturé à la construction — figé pour la durée
  /// du niveau pour ne pas mutiler les invariants (cf. doc du
  /// `RemoteConfigService`).
  final GameEconomyConfig _economy;

  /// Instrumentation analytics (events victoire / indice). Fail-soft.
  final AnalyticsService _analytics;

  /// Scheduler partagé pilotant la cadence du tic-tac audio (maquette p.12).
  /// Propriété du `tempoSchedulerProvider` — NE PAS `dispose()` ici.
  final TempoScheduler _tempo;

  Timer? _timer;
  Timer? _modifierTimer;

  /// Abonnement aux ticks du [TempoScheduler] tant que la partie est active.
  StreamSubscription<int>? _tempoSub;
  int _modifierTick = 0;
  final Random _modifierRng = Random();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Sélectionne une tuile par son index dans la grille shufflée.
  ///
  /// Règles (volontairement restrictives pour éviter qu'un tap accidentel
  /// au milieu du chemin n'explose la sélection) :
  /// - Tuile **pas encore sélectionnée** → ajoutée en fin.
  /// - Tuile **avant-dernière** (slide-back classique : le doigt revient
  ///   en arrière pendant un drag) → retire la dernière. Cascade naturelle
  ///   lettre par lettre si l'utilisateur continue à reculer.
  /// - Tuile **dernière sélectionnée** → retirée (re-tap discret = effacer).
  /// - Tuile **antérieure mais ni avant-dernière ni dernière** → ignorée.
  ///   La troncature mid-chemin serait trop destructrice sur un toucher
  ///   imprécis.
  void selectTile(int gridIndex) {
    if (state.phase != GamePhase.playing) return;
    // Une tuile masquée par le fog est intaptable. Le widget devrait
    // déjà bloquer le tap (pointer ignored), filet de sécurité côté
    // controller pour les call-sites synthétiques (tests, debug overlay).
    if (state.fogHiddenIndices.contains(gridIndex)) return;

    final selected = List<int>.from(state.selectedIndices);

    // Slide-back classique : entrer sur l'avant-dernière retire la dernière.
    if (selected.length >= 2 && selected[selected.length - 2] == gridIndex) {
      selected.removeLast();
      state = state.copyWith(
        selectedIndices: selected,
        validationCorrect: false,
      );
      _audio.hapticDeselect();
      return;
    }

    // Re-tap sur la dernière lettre : on la retire.
    if (selected.isNotEmpty && selected.last == gridIndex) {
      selected.removeLast();
      state = state.copyWith(
        selectedIndices: selected,
        validationCorrect: false,
      );
      _audio.hapticDeselect();
      return;
    }

    // Lettre antérieure (ni avant-dernière ni dernière) : ignorée.
    if (selected.contains(gridIndex)) return;

    selected.add(gridIndex);
    state = state.copyWith(selectedIndices: selected, validationCorrect: false);

    // Audio + haptique couplés (le tick haptique est déclenché par
    // AudioController.playLetterSelect — source unique, synchro garantie).
    unawaited(_audio.playLetterSelect(selected.length - 1));

    // Auto-validate when word is complete.
    if (state.isComplete) {
      validate();
    }
  }

  /// Efface la sélection courante.
  void clearSelection() {
    if (state.phase != GamePhase.playing) return;
    state = state.copyWith(
      selectedIndices: const <int>[],
      validationCorrect: false,
    );
  }

  /// Coût en cauris du **prochain** indice à utiliser (avec scaling
  /// intra-niveau : 1er = base, 2e = base × multiplier, etc.).
  int get nextHintCost => _economy.hintCostForIndex(
        state.hintRevealedCount,
        tierMultiplier: _args.config.caurisMultiplier,
      );

  /// Place une lettre correcte dans une case **au hasard** parmi celles
  /// encore non révélées, et l'affiche en aperçu dans `AnswerCells` (le
  /// joueur doit toujours la former dans la roue pour valider). Le coût
  /// est progressif intra-niveau (cf. [GameEconomyConfig.hintCostMultiplier])
  /// — 1er indice au prix de base, suivants multipliés.
  void useHint() {
    if (state.phase != GamePhase.playing) return;
    if (state.hintRevealedCount >= state.devinette.answer.length) return;
    final cost = nextHintCost;

    // **Priorité au freebie quotidien** : si un indice gratuit est
    // dispo, on ne décrémente PAS le solde local — le repo le consomme
    // côté `spendOnHint` sans toucher aux cauris. Garde le state UI
    // synchrone avec la persistance.
    final hasFreeHint = _progress.state.freeHintAvailable;
    if (!hasFreeHint && state.cauris < cost) return;

    // Tire une position de la réponse encore non révélée (au hasard).
    final answerLen = state.expectedAnswer.length;
    final candidates = <int>[
      for (var p = 0; p < answerLen; p++)
        if (!state.revealedPositions.contains(p)) p,
    ];
    if (candidates.isEmpty) return;
    final pos = candidates[_modifierRng.nextInt(candidates.length)];

    state = state.copyWith(
      cauris: hasFreeHint ? state.cauris : state.cauris - cost,
      hintRevealedCount: state.hintRevealedCount + 1,
      revealedPositions: <int>{...state.revealedPositions, pos},
    );

    // Persist deduction (consomme d'abord le freebie, sinon débite).
    unawaited(_progress.spendOnHint(cost));
    // Analytics : taux d'usage des indices par variante A/B (free vs payant).
    unawaited(
      _analytics.logHintUsed(
        tier: _args.config.difficultyTier,
        cost: hasFreeHint ? 0 : cost,
        free: hasFreeHint,
        levelIndex: _args.levelIndex,
      ),
    );
    // Audio: kora 2 notes douces descendantes.
    unawaited(_audio.playHintUsed());
  }

  /// Valide le mot formé par les tuiles sélectionnées.
  void validate() {
    if (state.phase != GamePhase.playing) return;
    if (state.selectedIndices.isEmpty) return;

    final formed = state.formedWord;
    if (formed == state.expectedAnswer) {
      _timer?.cancel();
      _stopTempo();
      // Récompense :
      // - **Mode standard** : (base + bonus vitesse × timeLeft) ×
      //   multiplier de difficulté (1.0 → 2.5 selon le tier). Base et
      //   bonus pilotés par Remote Config (cf. `GameEconomyConfig`).
      // - **Mode défi du jour** : montant fixe = base daily (100). Le
      //   bonus de palier (3/7/30 jours) est octroyé en plus par le
      //   notifier daily, mais n'est PAS affiché ici (VictoryView reste
      //   sur le montant base — feedback bonus géré côté hub).
      final int caurisAwarded;
      if (_args.isDailyChallenge) {
        caurisAwarded = DailyChallengeService.rewardCauris;
      } else {
        final raw = _economy.winRewardBase +
            state.timeLeft * _economy.speedBonusPerSecond;
        caurisAwarded = (raw * _args.config.caurisMultiplier).round();
      }
      // Étoiles : (1) victoire (2) sans indice (3) ≥ 50 % timer restant.
      final stars = LevelStarRating.computeStars(
        won: true,
        hintUsed: state.hintRevealedCount > 0,
        timerSeconds: _args.config.timerSeconds,
        timeLeftAtVictory: state.timeLeft,
      );
      state = state.copyWith(
        phase: GamePhase.won,
        validationCorrect: true,
        cauris: state.cauris + caurisAwarded,
        starsEarned: stars,
        caurisAwarded: caurisAwarded,
      );
      // Persiste la victoire — sauf en mode défi du jour qui a son
      // propre flow (cf. `GameView` qui appelle
      // `recordDailyChallengeResult` avec un montant fixe et n'utilise
      // pas le compteur de niveaux montagne).
      if (!_args.isDailyChallenge) {
        unawaited(
          _progress.recordWin(
            mountainId: _args.mountainId,
            caurisAwarded: caurisAwarded,
            levelIndex: _args.levelIndex,
            starsEarned: stars,
            devinetteId: state.devinette.id,
          ),
        );
      }
      // Analytics : métrique de gameplay/économie pour l'experiment A/B.
      unawaited(
        _analytics.logLevelWon(
          tier: _args.config.difficultyTier,
          caurisAwarded: caurisAwarded,
          hintsUsed: state.hintRevealedCount,
          timeLeft: state.timeLeft,
          stars: stars,
          isDaily: _args.isDailyChallenge,
          levelIndex: _args.levelIndex,
          mountainId: _args.mountainId,
        ),
      );
      // Audio + haptique couplés (déclenchés par AudioController) : accord
      // balafon + impact moyen immédiats, puis fanfare griot (boss ou
      // standard) + impact fort décalés de 350 ms pour s'aligner avec
      // l'attaque percussive de la fanfare.
      unawaited(_audio.playWordComplete());
      final isBoss = _args.config.isBoss;
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (isBoss) {
          unawaited(_audio.playBossVictory());
        } else {
          unawaited(_audio.playVictory());
        }
      });
    } else {
      // Audio + haptique couplés (djembé ×2 + impact fort) puis effacement.
      unawaited(_audio.playWrongAnswer());
      state = state.copyWith(
        selectedIndices: const <int>[],
        validationCorrect: false,
      );
    }
  }

  /// Suspend le décompte sans changer la phase. Idempotent — no-op si la
  /// partie n'est pas en cours. Appelé quand l'app passe en arrière-plan ou
  /// quand on ouvre un modal bloquant (confirmation, ad, IAP…).
  void pause() {
    if (state.phase != GamePhase.playing) return;
    _timer?.cancel();
    _timer = null;
    _stopTempo();
    _modifierTimer?.cancel();
    _modifierTimer = null;
  }

  /// Reprend le décompte depuis le `timeLeft` actuel. No-op si la partie n'est
  /// pas en phase playing ou si un timer tourne déjà.
  void resume() {
    if (state.phase != GamePhase.playing) return;
    if (_timer != null && _timer!.isActive) return;
    _startTimer();
    _startModifierTimer();
  }

  /// Re-démarre la même devinette : re-shuffle, timer adaptatif depuis
  /// la config, sélection vide. Génère de nouveaux distracteurs aléatoires
  /// pour éviter la mémorisation d'une grille spécifique entre runs.
  void restart() {
    _timer?.cancel();
    _modifierTimer?.cancel();
    state = _initialState(_args, _progress.state.cauris);
    _startTimer();
    _startModifierTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopTempo();
    _modifierTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _startTimer() {
    _timer?.cancel();
    _startTempo();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.phase != GamePhase.playing) {
        _timer?.cancel();
        _stopTempo();
        return;
      }
      if (state.timeLeft <= 1) {
        _timer?.cancel();
        _stopTempo();
        state = state.copyWith(timeLeft: 0, phase: GamePhase.lost);
        // Audio + haptique couplés (balafon descendant + tam-tam + impact fort).
        unawaited(_audio.playFailure());
      } else {
        state = state.copyWith(timeLeft: state.timeLeft - 1);
        // Accélère le tic-tac quand le temps s'épuise (60→90→140 BPM).
        _tempo.updateForTimeLeft(state.timeLeft);
      }
    });
  }

  /// Démarre le tic-tac audio adaptatif et s'abonne aux ticks du scheduler.
  /// Idempotent : repart toujours d'un état propre (le scheduler est partagé).
  void _startTempo() {
    _tempoSub?.cancel();
    _tempo
      ..stop()
      ..updateForTimeLeft(state.timeLeft);
    _tempoSub = _tempo.ticks.listen((_) {
      // Le scheduler peut émettre un dernier tick juste après une
      // victoire/défaite : on ne joue le tic que pendant le jeu actif.
      if (state.phase != GamePhase.playing) return;
      unawaited(_audio.playTimerTick(_tempo.bpm));
    });
    _tempo.start();
  }

  /// Stoppe le tic-tac et libère l'abonnement. NE dispose PAS le scheduler
  /// (propriété du `tempoSchedulerProvider` partagé).
  void _stopTempo() {
    _tempoSub?.cancel();
    _tempoSub = null;
    _tempo.stop();
  }

  /// Timer séparé pour les effets des modifiers (wind / earthquake / fog /
  /// shuffle). Tick chaque seconde et déclenche chaque effet selon sa
  /// période propre. Indépendant du timer principal pour pouvoir être
  /// suspendu sans toucher au compte à rebours.
  void _startModifierTimer() {
    final mods = _args.config.modifiers;
    final hasAny = mods.contains(LevelModifier.wind) ||
        mods.contains(LevelModifier.earthquake) ||
        mods.contains(LevelModifier.fog) ||
        mods.contains(LevelModifier.shuffle);
    if (!hasAny) return; // Pas de tic-tac inutile si aucun modifier visuel.
    _modifierTimer?.cancel();
    _modifierTick = 0;
    _modifierTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.phase != GamePhase.playing) {
        _modifierTimer?.cancel();
        return;
      }
      _modifierTick++;
      if (mods.contains(LevelModifier.wind) &&
          _modifierTick % _windPeriodSeconds == 0) {
        _applyWind();
      }
      if (mods.contains(LevelModifier.earthquake) &&
          _modifierTick % _earthquakePeriodSeconds == 0) {
        _applyEarthquake();
      }
      if (mods.contains(LevelModifier.fog) &&
          _modifierTick % _fogPeriodSeconds == 0) {
        _applyFog();
      }
      if (mods.contains(LevelModifier.shuffle) &&
          _modifierTick % _shufflePeriodSeconds == 0) {
        _applyShuffle();
      }
    });
  }

  /// Wind : choisit une case au hasard et swap avec sa voisine logique
  /// dans le cercle (gridIdx + 1 mod len). Léger drift d'une lettre.
  void _applyWind() {
    final len = state.shuffledIndices.length;
    if (len < 2) return;
    final a = _modifierRng.nextInt(len);
    final b = (a + 1) % len;
    _swapTiles(a, b);
  }

  /// Earthquake : choisit 2 cases distinctes au hasard et les échange.
  /// Mouvement plus brutal que wind (positions arbitraires, pas forcément
  /// voisines).
  void _applyEarthquake() {
    final len = state.shuffledIndices.length;
    if (len < 2) return;
    final a = _modifierRng.nextInt(len);
    var b = _modifierRng.nextInt(len);
    while (b == a) {
      b = _modifierRng.nextInt(len);
    }
    _swapTiles(a, b);
  }

  /// Fog : masque 1 tuile aléatoire (différente de la précédente quand
  /// possible). Le widget `CircularGrid` rend opacity 0 et ignore les
  /// taps sur cet index.
  void _applyFog() {
    final len = state.shuffledIndices.length;
    if (len < 2) return;
    final previous = state.fogHiddenIndices;
    var next = _modifierRng.nextInt(len);
    // Tente d'éviter de re-masquer la même tuile (rotation visible).
    var attempts = 0;
    while (previous.contains(next) && attempts < 5) {
      next = _modifierRng.nextInt(len);
      attempts++;
    }
    state = state.copyWith(fogHiddenIndices: <int>{next});
  }

  /// Shuffle : re-Fisher-Yates complet de `shuffledIndices`. Casse la
  /// mémoire spatiale du joueur. La sélection en cours est préservée :
  /// chaque indice sélectionné est remplacé par sa nouvelle position.
  void _applyShuffle() {
    final len = state.shuffledIndices.length;
    if (len < 2) return;
    final newShuffled = _shuffleIndices(len, _modifierRng);
    // Translate selectedIndices via la permutation. Pour chaque case
    // sélectionnée (gridIdx), on trouve où la lettre originale a atterri
    // après le re-shuffle.
    final newSelected = state.selectedIndices.map((oldGridIdx) {
      final letterPoolIdx = state.shuffledIndices[oldGridIdx];
      return newShuffled.indexOf(letterPoolIdx);
    }).toList(growable: false);
    state = state.copyWith(
      shuffledIndices: newShuffled,
      selectedIndices: newSelected,
    );
  }

  /// Swap atomique entre 2 cases de la grille. La sélection « suit » les
  /// lettres : si une case sélectionnée bouge, son indice est remplacé
  /// par le nouvel emplacement de la même lettre.
  void _swapTiles(int a, int b) {
    final newShuffled = List<int>.from(state.shuffledIndices);
    final tmp = newShuffled[a];
    newShuffled[a] = newShuffled[b];
    newShuffled[b] = tmp;
    final newSelected = state.selectedIndices.map((i) {
      if (i == a) return b;
      if (i == b) return a;
      return i;
    }).toList(growable: false);
    state = state.copyWith(
      shuffledIndices: newShuffled,
      selectedIndices: newSelected,
    );
  }

  /// Fisher-Yates shuffle sur [0..count-1]. `rng` injectable pour que la
  /// même instance Random soit partagée avec [_buildEffectivePool] (tirage
  /// distracteurs + shuffle cohérents sur un même run).
  static List<int> _shuffleIndices(int count, [Random? rng]) {
    final r = rng ?? Random();
    final list = List<int>.generate(count, (i) => i);
    for (var i = list.length - 1; i > 0; i--) {
      final j = r.nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }
}

/// Provider family : un [GameController] par [GameArgs].
final gameControllerProvider = StateNotifierProvider.autoDispose
    .family<GameController, GameState, GameArgs>(
      (ref, args) => GameController(
        args,
        ref.read(audioControllerProvider.notifier),
        ref.read(playerProgressProvider.notifier),
        ref.read(gameEconomyConfigProvider),
        ref.read(analyticsServiceProvider),
        ref.read(tempoSchedulerProvider),
      ),
    );
