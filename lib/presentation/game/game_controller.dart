import 'dart:async';
import 'dart:math';

import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/level_star_rating.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:flutter/services.dart' show HapticFeedback;
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
    this.validationCorrect = false,
    this.reverseAnswer = false,
    this.starsEarned = 0,
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

  /// Nombre de lettres révélées par l'indice.
  final int hintRevealedCount;

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

  /// Séquence de lettres attendue compte tenu du modifier `reverse`.
  /// Stockée comme String pour permettre l'égalité directe avec
  /// [formedWord] et l'itération par indice dans [hintTileIndices].
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

  /// Indices de tuiles (positions dans la grille shufflée) révélées par
  /// l'indice — pour les `hintRevealedCount` premières lettres de la
  /// réponse. Chaque entrée pointe sur la prochaine occurrence disponible
  /// dans le pool (gestion des doublons type "FOUTOU" avec 2× O et 2× U).
  ///
  /// L'ancienne logique `i < hintRevealedCount` dans la grille traitait
  /// `hintRevealedCount` comme un index sur l'ordre physique du cercle,
  /// ce qui révélait une tuile aléatoire au lieu de pointer la prochaine
  /// lettre de la réponse.
  List<int> get hintTileIndices {
    final answer = expectedAnswer;
    final n = hintRevealedCount.clamp(0, answer.length);
    if (n == 0) return const <int>[];
    final used = <int>{};
    final result = <int>[];
    for (var k = 0; k < n; k++) {
      final target = answer[k];
      for (var gridIdx = 0; gridIdx < shuffledIndices.length; gridIdx++) {
        if (used.contains(gridIdx)) continue;
        final letter = effectivePool[shuffledIndices[gridIdx]];
        if (letter == target) {
          result.add(gridIdx);
          used.add(gridIdx);
          break;
        }
      }
    }
    return result;
  }

  GameState copyWith({
    Devinette? devinette,
    List<int>? selectedIndices,
    int? timeLeft,
    GamePhase? phase,
    int? cauris,
    List<int>? shuffledIndices,
    List<String>? effectivePool,
    int? hintRevealedCount,
    bool? validationCorrect,
    bool? reverseAnswer,
    int? starsEarned,
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
      validationCorrect: validationCorrect ?? this.validationCorrect,
      reverseAnswer: reverseAnswer ?? this.reverseAnswer,
      starsEarned: starsEarned ?? this.starsEarned,
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
  GameController(this._args, this._audio, this._progress)
    : super(
        _initialState(_args, _progress.state.cauris),
      ) {
    _startTimer();
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

  static const int _hintCost = 20;
  static const int _caurisBase = 30;

  final GameArgs _args;
  final AudioController _audio;
  final PlayerProgressNotifier _progress;
  Timer? _timer;

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

    final selected = List<int>.from(state.selectedIndices);

    // Slide-back classique : entrer sur l'avant-dernière retire la dernière.
    if (selected.length >= 2 && selected[selected.length - 2] == gridIndex) {
      selected.removeLast();
      state = state.copyWith(
        selectedIndices: selected,
        validationCorrect: false,
      );
      unawaited(HapticFeedback.selectionClick());
      return;
    }

    // Re-tap sur la dernière lettre : on la retire.
    if (selected.isNotEmpty && selected.last == gridIndex) {
      selected.removeLast();
      state = state.copyWith(
        selectedIndices: selected,
        validationCorrect: false,
      );
      unawaited(HapticFeedback.selectionClick());
      return;
    }

    // Lettre antérieure (ni avant-dernière ni dernière) : ignorée.
    if (selected.contains(gridIndex)) return;

    selected.add(gridIndex);
    state = state.copyWith(selectedIndices: selected, validationCorrect: false);

    // Audio: balafon note ascending (cf. maquette p.12).
    unawaited(_audio.playLetterSelect(selected.length - 1));
    // Haptique: tick discret synchronisé avec la note.
    unawaited(HapticFeedback.selectionClick());

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

  /// Révèle la prochaine lettre (coûte [_hintCost] cauris).
  void useHint() {
    if (state.phase != GamePhase.playing) return;
    if (state.cauris < _hintCost) return;
    if (state.hintRevealedCount >= state.devinette.answer.length) return;

    state = state.copyWith(
      cauris: state.cauris - _hintCost,
      hintRevealedCount: state.hintRevealedCount + 1,
    );

    // Persist deduction.
    unawaited(_progress.spendOnHint(_hintCost));
    // Audio: kora 2 notes douces descendantes.
    unawaited(_audio.playHintUsed());
    unawaited(HapticFeedback.lightImpact());
  }

  /// Valide le mot formé par les tuiles sélectionnées.
  void validate() {
    if (state.phase != GamePhase.playing) return;
    if (state.selectedIndices.isEmpty) return;

    final formed = state.formedWord;
    if (formed == state.expectedAnswer) {
      _timer?.cancel();
      // Récompense : (base 30 + bonus vitesse 2×timeLeft) × multiplier
      // de difficulté (1.0 → 2.5 selon le tier).
      final raw = _caurisBase + state.timeLeft * 2;
      final caurisAwarded = (raw * _args.config.caurisMultiplier).round();
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
      );
      // Persiste la victoire (cauris + level mountain + total + lastPlay
      // + meilleur score étoile pour ce niveau).
      unawaited(
        _progress.recordWin(
          mountainId: _args.mountainId,
          caurisAwarded: caurisAwarded,
          levelIndex: _args.levelIndex,
          starsEarned: stars,
        ),
      );
      // Audio: balafon accord 5 notes puis fanfare griot.
      unawaited(_audio.playWordComplete());
      // Haptique victoire: medium puis heavy à 350ms (sync avec la fanfare).
      unawaited(HapticFeedback.mediumImpact());
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        unawaited(_audio.playVictory());
        unawaited(HapticFeedback.heavyImpact());
      });
    } else {
      // Audio: djembé ×2 + effacement.
      unawaited(_audio.playWrongAnswer());
      unawaited(HapticFeedback.heavyImpact());
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
  }

  /// Reprend le décompte depuis le `timeLeft` actuel. No-op si la partie n'est
  /// pas en phase playing ou si un timer tourne déjà.
  void resume() {
    if (state.phase != GamePhase.playing) return;
    if (_timer != null && _timer!.isActive) return;
    _startTimer();
  }

  /// Re-démarre la même devinette : re-shuffle, timer adaptatif depuis
  /// la config, sélection vide. Génère de nouveaux distracteurs aléatoires
  /// pour éviter la mémorisation d'une grille spécifique entre runs.
  void restart() {
    _timer?.cancel();
    state = _initialState(_args, _progress.state.cauris);
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.phase != GamePhase.playing) {
        _timer?.cancel();
        return;
      }
      if (state.timeLeft <= 1) {
        _timer?.cancel();
        state = state.copyWith(timeLeft: 0, phase: GamePhase.lost);
        unawaited(_audio.playFailure());
        unawaited(HapticFeedback.heavyImpact());
      } else {
        state = state.copyWith(timeLeft: state.timeLeft - 1);
      }
    });
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
      ),
    );
