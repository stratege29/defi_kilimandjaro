import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:defi_kilimandjaro/domain/entities/tournament.dart';
import 'package:defi_kilimandjaro/domain/entities/tournament_participant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tournament.fromFirestore', () {
    final start = DateTime(2026, 6, 28, 20);
    final end = DateTime(2026, 6, 28, 20, 30);

    Map<String, dynamic> baseData() => {
          'name': 'Arène du soir',
          'status': 'live',
          'start_at': Timestamp.fromDate(start),
          'end_at': Timestamp.fromDate(end),
          'duration_min': 30,
          'participant_count': 12,
          'points_win': 3,
          'points_draw': 1,
          'streak_min': 2,
          'streak_mult': 2,
          'min_participants': 4,
          'rewards': [
            {'rank_min': 1, 'rank_max': 1, 'cauris': 500, 'badge_id': 'gold'},
            {'rank_min': 2, 'rank_max': 3, 'cauris': 250},
          ],
        };

    test('maps all fields including reward tiers', () {
      final t = Tournament.fromFirestore('T1', baseData());
      expect(t.id, 'T1');
      expect(t.name, 'Arène du soir');
      expect(t.status, TournamentStatus.live);
      expect(t.isLive, isTrue);
      expect(t.startAt, start);
      expect(t.endAt, end);
      expect(t.participantCount, 12);
      expect(t.minParticipants, 4);
      expect(t.rewards.length, 2);
      expect(t.rewards.first.cauris, 500);
      expect(t.rewards.first.badgeId, 'gold');
      expect(t.rewards[1].badgeId, isNull);
    });

    test('applies defaults for missing scoring fields', () {
      final data = baseData()
        ..remove('points_win')
        ..remove('streak_min');
      final t = Tournament.fromFirestore('T1', data);
      expect(t.pointsWin, 3);
      expect(t.streakMin, 2);
    });

    test('countdown helpers clamp to zero when elapsed', () {
      final t = Tournament.fromFirestore('T1', baseData());
      final afterEnd = end.add(const Duration(minutes: 5));
      expect(t.endsIn(afterEnd), Duration.zero);
      expect(t.startsIn(afterEnd), Duration.zero);
    });

    test('startsIn / endsIn compute positive remaining', () {
      final t = Tournament.fromFirestore('T1', baseData());
      final before = start.subtract(const Duration(minutes: 10));
      expect(t.startsIn(before), const Duration(minutes: 10));
    });

    test('unknown status falls back to scheduled', () {
      final data = baseData()..['status'] = 'weird';
      expect(
        Tournament.fromFirestore('T1', data).status,
        TournamentStatus.scheduled,
      );
    });
  });

  group('TournamentParticipant.fromFirestore', () {
    test('maps fields and onFire flag', () {
      final p = TournamentParticipant.fromFirestore('u1', {
        'display_name': 'Kacou',
        'points': 9,
        'matches_played': 4,
        'wins': 3,
        'draws': 0,
        'losses': 1,
        'current_streak': 2,
        'rank': 1,
        'reward_cauris': 500,
        'reward_badge': 'gold',
      });
      expect(p.uid, 'u1');
      expect(p.displayName, 'Kacou');
      expect(p.points, 9);
      expect(p.wins, 3);
      expect(p.onFire, isTrue);
      expect(p.rank, 1);
      expect(p.rewardCauris, 500);
    });

    test('defaults anonymous name and not on fire', () {
      final p = TournamentParticipant.fromFirestore('u2', {
        'points': 1,
        'current_streak': 1,
      });
      expect(p.displayName, 'Grimpeur anonyme');
      expect(p.onFire, isFalse);
      expect(p.rank, isNull);
    });
  });
}
