import 'dart:async';
import 'dart:math';

import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
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
    this.hintRevealedCount = 0,
    this.validationCorrect = false,
  });

  final Devinette devinette;

  /// Indices (dans shuffledIndices) des tuiles sélectionnées dans l'ordre.
  final List<int> selectedIndices;

  final int timeLeft;
  final GamePhase phase;
  final int cauris;

  /// Permutation des indices de lettersPool (Fisher-Yates au départ).
  final List<int> shuffledIndices;

  /// Nombre de lettres révélées par l'indice.
  final int hintRevealedCount;

  /// Vrai juste après une validation correcte (pour déclencher le flash).
  final bool validationCorrect;

  /// Lettres dans l'ordre shufflé.
  List<String> get displayLetters => shuffledIndices
      .map((i) => devinette.lettersPool[i])
      .toList(growable: false);

  /// Mot formé par les indices sélectionnés (lettres dans l'ordre de sélection).
  String get formedWord => selectedIndices
      .map((si) => devinette.lettersPool[shuffledIndices[si]])
      .join();

  bool get isComplete => selectedIndices.length == devinette.answer.length;

  GameState copyWith({
    Devinette? devinette,
    List<int>? selectedIndices,
    int? timeLeft,
    GamePhase? phase,
    int? cauris,
    List<int>? shuffledIndices,
    int? hintRevealedCount,
    bool? validationCorrect,
  }) {
    return GameState(
      devinette: devinette ?? this.devinette,
      selectedIndices: selectedIndices ?? this.selectedIndices,
      timeLeft: timeLeft ?? this.timeLeft,
      phase: phase ?? this.phase,
      cauris: cauris ?? this.cauris,
      shuffledIndices: shuffledIndices ?? this.shuffledIndices,
      hintRevealedCount: hintRevealedCount ?? this.hintRevealedCount,
      validationCorrect: validationCorrect ?? this.validationCorrect,
    );
  }
}

/// Contrôleur principal de l'écran de jeu (cf. plan.md §2 Phase 1.2).
///
/// - Timer 30 s géré ici via [Timer.periodic].
/// - Sélection par index (pas par lettre) pour gérer les doublons.
/// - Auto-validation quand [selectedIndices.length == answer.length].
class GameController extends StateNotifier<GameState> {
  GameController(this._args, this._audio, this._progress)
    : super(
        GameState(
          devinette: _args.devinette,
          selectedIndices: const <int>[],
          timeLeft: _gameDuration,
          phase: GamePhase.playing,
          cauris: _progress.state.cauris,
          shuffledIndices: _shuffleIndices(_args.devinette.lettersPool.length),
        ),
      ) {
    _startTimer();
  }

  static const int _hintCost = 20;
  static const int _gameDuration = 30;
  static const int _caurisBase = 30;

  final GameArgs _args;
  final AudioController _audio;
  final PlayerProgressNotifier _progress;
  Timer? _timer;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Sélectionne une tuile par son index dans la grille shufflée.
  /// Gère le slide-back (pointer revient sur l'avant-dernier → supprime le dernier).
  void selectTile(int gridIndex) {
    if (state.phase != GamePhase.playing) return;

    final selected = List<int>.from(state.selectedIndices);

    // Slide-back.
    if (selected.length >= 2 && selected[selected.length - 2] == gridIndex) {
      selected.removeLast();
      state = state.copyWith(
        selectedIndices: selected,
        validationCorrect: false,
      );
      return;
    }

    // Ne pas re-sélectionner un index déjà dans la liste.
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
    if (formed == state.devinette.answer) {
      _timer?.cancel();
      // Récompense : base 30 + bonus vitesse (timeLeft × 2).
      final caurisAwarded = _caurisBase + state.timeLeft * 2;
      state = state.copyWith(
        phase: GamePhase.won,
        validationCorrect: true,
        cauris: state.cauris + caurisAwarded,
      );
      // Persiste la victoire (cauris + level mountain + total + lastPlay).
      unawaited(
        _progress.recordWin(
          mountainId: _args.mountainId,
          caurisAwarded: caurisAwarded,
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

  /// Re-démarre la même devinette : re-shuffle, timer 30 s, sélection vide.
  void restart() {
    _timer?.cancel();
    state = GameState(
      devinette: state.devinette,
      selectedIndices: const <int>[],
      timeLeft: _gameDuration,
      phase: GamePhase.playing,
      cauris: _progress.state.cauris,
      shuffledIndices: _shuffleIndices(state.devinette.lettersPool.length),
    );
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

  /// Fisher-Yates shuffle sur [0..count-1].
  static List<int> _shuffleIndices(int count) {
    final rng = Random();
    final list = List<int>.generate(count, (i) => i);
    for (var i = list.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
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
