import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_kind.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = LevelDifficultyConfig(
    difficultyTier: 2,
    wordLengthBucket: 2,
    timerSeconds: 34,
    caurisMultiplier: 1.3,
    distractorCount: 1,
    modifiers: <LevelModifier>{LevelModifier.rain},
  );

  group('LevelDifficultyConfig — kind', () {
    test('classic par défaut, fallback inclus', () {
      expect(base.kind, LevelKind.classic);
      expect(LevelDifficultyConfig.fallback.kind, LevelKind.classic);
    });

    test("kind participe à l'égalité et au hashCode", () {
      final duo = base.copyWith(kind: LevelKind.duo);
      expect(duo, isNot(equals(base)));
      expect(duo.hashCode, isNot(base.hashCode));
      expect(base.copyWith(), base);
    });
  });

  group('LevelDifficultyConfig — copyWith', () {
    test('ne modifie que les champs fournis', () {
      final exposed = base.copyWith(
        distractorCount: 2,
        timerSeconds: 27,
        caurisMultiplier: 2.6,
      );
      expect(exposed.distractorCount, 2);
      expect(exposed.timerSeconds, 27);
      expect(exposed.caurisMultiplier, 2.6);
      expect(exposed.difficultyTier, base.difficultyTier);
      expect(exposed.wordLengthBucket, base.wordLengthBucket);
      expect(exposed.modifiers, base.modifiers);
      expect(exposed.isBoss, base.isBoss);
      expect(exposed.kind, base.kind);
    });

    test('copyWith(kind:) et copyWith(isBoss:)', () {
      final boss = base.copyWith(isBoss: true, kind: LevelKind.blindBoss);
      expect(boss.isBoss, isTrue);
      expect(boss.kind, LevelKind.blindBoss);
    });
  });

  group('LevelKind', () {
    test('devinetteCount : 3 rafale, 2 duo, 1 sinon', () {
      expect(LevelKind.rafale.devinetteCount, 3);
      expect(LevelKind.duo.devinetteCount, 2);
      expect(LevelKind.classic.devinetteCount, 1);
      expect(LevelKind.blindBoss.devinetteCount, 1);
    });

    test('isMultiWord : rafale et duo seulement', () {
      expect(LevelKind.rafale.isMultiWord, isTrue);
      expect(LevelKind.duo.isMultiWord, isTrue);
      expect(LevelKind.classic.isMultiWord, isFalse);
      expect(LevelKind.blindBoss.isMultiWord, isFalse);
    });
  });
}
