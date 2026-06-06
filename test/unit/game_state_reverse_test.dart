import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/presentation/game/game_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests de la logique `reverse` côté [GameState].
/// `GameController.validate` compare `state.formedWord == state.expectedAnswer`,
/// donc la couverture de `expectedAnswer` garantit que la mécanique reverse
/// se comporte correctement bout-en-bout.

Devinette _foutou() {
  // F-O-U-T-O-U (6 lettres, 2× O, 2× U — bon test pour les doublons).
  return const Devinette(
    id: 'foutou',
    pack: 'culture_ci',
    country: 'ci',
    answer: 'FOUTOU',
    lettersPool: <String>['F', 'O', 'U', 'T', 'O', 'U'],
    riddleByLang: <String, String>{'fr': 'Plat du sud'},
    explanationByLang: <String, String>{'fr': '...'},
    difficulty: 1,
    estimatedTimeS: 20,
    tags: <String>[],
  );
}

GameState _state({
  required bool reverseAnswer,
  required List<int> shuffledIndices,
  int hintRevealedCount = 0,
  List<String>? effectivePool,
}) {
  final dev = _foutou();
  return GameState(
    devinette: dev,
    selectedIndices: const <int>[],
    timeLeft: 30,
    phase: GamePhase.playing,
    cauris: 0,
    // Pool effectif = lettres originales par défaut (pas de distracteurs
    // dans ces tests reverse). Possibilité d'override pour des cas
    // spécifiques (distracteurs ajoutés en fin).
    effectivePool: effectivePool ?? dev.lettersPool,
    shuffledIndices: shuffledIndices,
    hintRevealedCount: hintRevealedCount,
    reverseAnswer: reverseAnswer,
  );
}

void main() {
  group('GameState.expectedAnswer', () {
    test('reverseAnswer=false → mot canonique', () {
      final s = _state(
        reverseAnswer: false,
        shuffledIndices: const <int>[0, 1, 2, 3, 4, 5],
      );
      expect(s.expectedAnswer, 'FOUTOU');
    });

    test('reverseAnswer=true → mot inversé', () {
      final s = _state(
        reverseAnswer: true,
        shuffledIndices: const <int>[0, 1, 2, 3, 4, 5],
      );
      expect(s.expectedAnswer, 'UOTUOF');
    });
  });

  group('GameState.copyWith préserve reverseAnswer', () {
    test('copyWith sans reverseAnswer conserve la valeur courante', () {
      final s = _state(
        reverseAnswer: true,
        shuffledIndices: const <int>[0, 1, 2, 3, 4, 5],
      );
      final next = s.copyWith(timeLeft: 10);
      expect(next.reverseAnswer, isTrue);
      expect(next.timeLeft, 10);
    });
  });
}
