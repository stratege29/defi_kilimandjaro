import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/presentation/game/game_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests de la logique `reverse` côté [GameState].
/// `GameController.validate` compare `state.formedWord == state.expectedAnswer`,
/// donc la couverture de `expectedAnswer` et `hintTileIndices` garantit
/// que la mécanique reverse se comporte correctement bout-en-bout.

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
}) {
  return GameState(
    devinette: _foutou(),
    selectedIndices: const <int>[],
    timeLeft: 30,
    phase: GamePhase.playing,
    cauris: 0,
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

  group('GameState.hintTileIndices avec reverse', () {
    test('reverse off : 1er indice révèle la 1ère lettre canonique (F)', () {
      // shuffle identité : pool[0] = F.
      final s = _state(
        reverseAnswer: false,
        shuffledIndices: const <int>[0, 1, 2, 3, 4, 5],
        hintRevealedCount: 1,
      );
      // L'indice doit pointer sur la tuile contenant F → gridIdx 0.
      expect(s.hintTileIndices, <int>[0]);
    });

    test('reverse on : 1er indice révèle la 1ère lettre du mot inversé (U)',
        () {
      // shuffle identité : pool = [F, O, U, T, O, U]. La 1ère lettre du
      // mot inversé est 'U' (la dernière du mot canonique). Le matcher
      // doit pointer sur la première occurrence non utilisée d'un 'U'.
      final s = _state(
        reverseAnswer: true,
        shuffledIndices: const <int>[0, 1, 2, 3, 4, 5],
        hintRevealedCount: 1,
      );
      // Première occurrence de U dans le pool → gridIdx 2.
      expect(s.hintTileIndices, <int>[2]);
    });

    test('reverse on : 2 indices révèlent U puis O (sans réutiliser la case)',
        () {
      // Mot inversé : U-O-T-U-O-F. Les 2 premières lettres : U puis O.
      // pool = [F, O, U, T, O, U]. Première U non utilisée : gridIdx 2.
      // Première O non utilisée (≠ 2) : gridIdx 1.
      final s = _state(
        reverseAnswer: true,
        shuffledIndices: const <int>[0, 1, 2, 3, 4, 5],
        hintRevealedCount: 2,
      );
      expect(s.hintTileIndices, <int>[2, 1]);
    });

    test('hintRevealedCount=0 → liste vide quel que soit reverseAnswer', () {
      final off = _state(
        reverseAnswer: false,
        shuffledIndices: const <int>[0, 1, 2, 3, 4, 5],
      );
      final on = _state(
        reverseAnswer: true,
        shuffledIndices: const <int>[0, 1, 2, 3, 4, 5],
      );
      expect(off.hintTileIndices, isEmpty);
      expect(on.hintTileIndices, isEmpty);
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
