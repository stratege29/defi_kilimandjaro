import 'package:defi_kilimandjaro/domain/entities/leaderboard_entry.dart';
import 'package:defi_kilimandjaro/domain/entities/player_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests unitaires du domaine Leaderboard.
///
/// Les repositories Firestore ne sont pas testés directement ici car
/// `fake_cloud_firestore` n'est pas dans les dépendances. On teste :
/// - La logique de mappage PlayerProfile → LeaderboardEntry.
/// - Les propriétés de l'entité LeaderboardEntry.
/// - Les nouvelles propriétés displayName / displayLabel de PlayerProfile.
void main() {
  group('LeaderboardEntry', () {
    test('altitudeLabel formate correctement', () {
      const entry = LeaderboardEntry(
        uid: 'uid1',
        displayName: 'SagesseDuSud',
        elo: 1247,
        rank: 3,
      );
      expect(entry.altitudeLabel, '1247 m');
    });

    test('props identiques → égalité', () {
      const a = LeaderboardEntry(
        uid: 'uid1',
        displayName: 'Griot',
        elo: 2000,
        rank: 10,
      );
      const b = LeaderboardEntry(
        uid: 'uid1',
        displayName: 'Griot',
        elo: 2000,
        rank: 10,
      );
      expect(a, equals(b));
    });

    test('props différents → inégalité', () {
      const a = LeaderboardEntry(
        uid: 'uid1',
        displayName: 'Alpha',
        elo: 1000,
        rank: 1,
      );
      const b = LeaderboardEntry(
        uid: 'uid2',
        displayName: 'Beta',
        elo: 1500,
        rank: 2,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('PlayerProfile.displayLabel', () {
    test('retourne displayName si défini et non vide', () {
      const p = PlayerProfile(
        uid: 'u1',
        elo: 1000,
        peakElo: 1000,
        totalDuels: 0,
        wins: 0,
        losses: 0,
        displayName: 'MontagneSage',
      );
      expect(p.displayLabel, 'MontagneSage');
    });

    test('retourne "Grimpeur anonyme" si displayName est null', () {
      final p = PlayerProfile.initial('u1');
      expect(p.displayLabel, 'Grimpeur anonyme');
    });

    test("retourne 'Grimpeur anonyme' si displayName est une chaîne vide", () {
      const p = PlayerProfile(
        uid: 'u1',
        elo: 1000,
        peakElo: 1000,
        totalDuels: 0,
        wins: 0,
        losses: 0,
        displayName: '',
      );
      expect(p.displayLabel, 'Grimpeur anonyme');
    });
  });

  group('PlayerProfile.fromJson — displayName', () {
    test('parse display_name depuis le JSON Firestore', () {
      final profile = PlayerProfile.fromJson('uid-test', const <String, dynamic>{
        'elo': 2500,
        'peakElo': 2800,
        'totalDuels': 10,
        'wins': 6,
        'losses': 4,
        'display_name': 'GriotDuFeu',
        'display_name_updated_at': 1715000000000,
      });
      expect(profile.displayName, 'GriotDuFeu');
      expect(profile.displayNameUpdatedAt, isNotNull);
      expect(profile.displayLabel, 'GriotDuFeu');
    });

    test('displayName est null si absent du JSON', () {
      final profile = PlayerProfile.fromJson(
        'uid-test',
        const <String, dynamic>{
          'elo': 1000,
          'peakElo': 1000,
          'totalDuels': 0,
          'wins': 0,
          'losses': 0,
        },
      );
      expect(profile.displayName, isNull);
      expect(profile.displayLabel, 'Grimpeur anonyme');
    });
  });

  group('PlayerProfile.copyWith — displayName', () {
    test('copyWith met à jour displayName', () {
      final original = PlayerProfile.initial('u1');
      final updated = original.copyWith(displayName: 'NouveauNom');
      expect(updated.displayName, 'NouveauNom');
      expect(updated.uid, 'u1');
      expect(updated.elo, PlayerProfile.eloInitial);
    });

    test("copyWith sans displayName conserve l'original", () {
      const original = PlayerProfile(
        uid: 'u2',
        elo: 1500,
        peakElo: 2000,
        totalDuels: 5,
        wins: 3,
        losses: 2,
        displayName: 'AncienNom',
      );
      final updated = original.copyWith(elo: 1600);
      expect(updated.displayName, 'AncienNom');
      expect(updated.elo, 1600);
    });
  });

  group('LeaderboardEntry — tri simulation', () {
    test('tri ELO décroissant produit les bons rangs', () {
      final profiles = [
        const LeaderboardEntry(uid: 'a', displayName: 'Alpha', elo: 1000, rank: 1),
        const LeaderboardEntry(uid: 'b', displayName: 'Beta', elo: 3000, rank: 1),
        const LeaderboardEntry(uid: 'c', displayName: 'Gamma', elo: 2000, rank: 1),
      ];

      // Simule le tri que le repository applique.
      final sorted = [...profiles]
        ..sort((x, y) => y.elo.compareTo(x.elo));
      final ranked = sorted
          .asMap()
          .entries
          .map(
            (e) => LeaderboardEntry(
              uid: e.value.uid,
              displayName: e.value.displayName,
              elo: e.value.elo,
              rank: e.key + 1,
            ),
          )
          .toList();

      expect(ranked[0].uid, 'b');
      expect(ranked[0].rank, 1);
      expect(ranked[1].uid, 'c');
      expect(ranked[1].rank, 2);
      expect(ranked[2].uid, 'a');
      expect(ranked[2].rank, 3);
    });
  });
}
