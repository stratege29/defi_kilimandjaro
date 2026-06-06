import 'package:defi_kilimandjaro/data/sync/progress_merge.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergeProgress — best-of-both non destructif', () {
    test('compteurs : prend le max de chaque côté', () {
      final local = PlayerProgress.initial(cauris: 100).copyWith(
        totalLevelsCompleted: 5,
        dailyStreak: 2,
        dailyChallengeStreak: 1,
        freezeTokens: 1,
      );
      final cloud = PlayerProgress.initial(cauris: 999).copyWith(
        totalLevelsCompleted: 3,
        dailyStreak: 7,
        dailyChallengeStreak: 4,
        freezeTokens: 3,
      );

      final merged = mergeProgress(local, cloud);

      expect(merged.totalLevelsCompleted, 5);
      expect(merged.dailyStreak, 7);
      expect(merged.dailyChallengeStreak, 4);
      expect(merged.freezeTokens, 3);
    });

    test('cauris : conservé local (autorité wallet serveur)', () {
      final local = PlayerProgress.initial(cauris: 100);
      final cloud = PlayerProgress.initial(cauris: 999999);

      expect(mergeProgress(local, cloud).cauris, 100);
    });

    test('maps niveau→valeur : max clé par clé, union des clés', () {
      final local = PlayerProgress.initial().copyWith(
        completedLevelsByMountain: {'kili': 3, 'toubkal': 1},
        starsByLevel: {'kili#1': 3, 'kili#2': 1},
      );
      final cloud = PlayerProgress.initial().copyWith(
        completedLevelsByMountain: {'kili': 2, 'kenya': 4},
        starsByLevel: {'kili#2': 2, 'kenya#1': 3},
      );

      final merged = mergeProgress(local, cloud);

      expect(merged.completedLevelsByMountain, {
        'kili': 3,
        'toubkal': 1,
        'kenya': 4,
      });
      expect(merged.starsByLevel, {
        'kili#1': 3,
        'kili#2': 2,
        'kenya#1': 3,
      });
    });

    test('sets : union des packs et des modifiers rencontrés', () {
      final local = PlayerProgress.initial().copyWith(
        ownedPacks: {'culture_ci'},
        encounteredModifiers: {LevelModifier.values.first},
      );
      final cloud = PlayerProgress.initial().copyWith(
        ownedPacks: {'crack_nouchi'},
        encounteredModifiers: {LevelModifier.values.last},
      );

      final merged = mergeProgress(local, cloud);

      expect(merged.ownedPacks, {'culture_ci', 'crack_nouchi'});
      expect(merged.encounteredModifiers, {
        LevelModifier.values.first,
        LevelModifier.values.last,
      });
    });

    test("flags d'achat : OU logique", () {
      final local = PlayerProgress.initial().copyWith(noAdsPurchased: true);
      final cloud =
          PlayerProgress.initial().copyWith(starterPackPurchased: true);

      final merged = mergeProgress(local, cloud);

      expect(merged.noAdsPurchased, isTrue);
      expect(merged.starterPackPurchased, isTrue);
    });

    test('dates : dernière activité la plus récente, install la plus ancienne',
        () {
      final older = DateTime(2026, 1, 2);
      final newer = DateTime(2026, 5, 3);
      final local = PlayerProgress.initial().copyWith(
        lastPlayDate: older,
        installDate: newer,
      );
      final cloud = PlayerProgress.initial().copyWith(
        lastPlayDate: newer,
        installDate: older,
      );

      final merged = mergeProgress(local, cloud);

      expect(merged.lastPlayDate, newer);
      expect(merged.installDate, older);
    });

    test("freePackChosen : adopté du cloud si le device n'a pas tranché", () {
      final local = PlayerProgress.initial();
      final cloud =
          PlayerProgress.initial().copyWith(freePackChosen: 'culture_ci');

      expect(mergeProgress(local, cloud).freePackChosen, 'culture_ci');
    });

    test('pack actif : préfère un pack local valable sur les packs fusionnés',
        () {
      final local = PlayerProgress.initial().copyWith(
        ownedPacks: {'culture_ci'},
        activePackId: 'culture_ci',
      );
      final cloud = PlayerProgress.initial().copyWith(
        ownedPacks: {'crack_nouchi'},
        activePackId: 'crack_nouchi',
      );

      final merged = mergeProgress(local, cloud);

      expect(merged.ownedPacks, {'culture_ci', 'crack_nouchi'});
      expect(merged.activePackId, 'culture_ci');
    });

    test('cloud vide ne régresse jamais le local', () {
      final local = PlayerProgress.initial(cauris: 250).copyWith(
        totalLevelsCompleted: 12,
        ownedPacks: {'culture_ci'},
        freePackChosen: 'culture_ci',
        activePackId: 'culture_ci',
      );
      final cloud = PlayerProgress.initial();

      final merged = mergeProgress(local, cloud);

      expect(merged.totalLevelsCompleted, 12);
      expect(merged.cauris, 250);
      expect(merged.ownedPacks, {'culture_ci'});
      expect(merged.activePackId, 'culture_ci');
    });
  });
}
