import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:defi_kilimandjaro/data/repositories/friends_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/leaderboard_entry.dart';
import 'package:defi_kilimandjaro/domain/entities/player_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Repository du classement mondial et amis.
///
/// Index Firestore : `profiles` sur champ `elo` DESC — single-field index
/// auto-créé par Firestore, aucun composite index requis.
///
/// Limite : [kGlobalTop] entrées max pour le classement mondial.
class LeaderboardRepository {
  LeaderboardRepository({
    required this.firestore,
    required this.profileRepo,
    required this.friendsRepo,
  });

  static const int kGlobalTop = 100;

  final FirebaseFirestore firestore;
  final ProfileRepository profileRepo;
  final FriendsRepository friendsRepo;
  final Logger _log = Logger();

  CollectionReference<Map<String, dynamic>> get _profiles =>
      firestore.collection('profiles');

  // ---------------------------------------------------------------------------
  // Global top-N
  // ---------------------------------------------------------------------------

  /// Stream en temps réel du top [kGlobalTop] joueurs par ELO décroissant.
  Stream<List<LeaderboardEntry>> watchGlobalTop100() {
    return _profiles
        .orderBy('elo', descending: true)
        .limit(kGlobalTop)
        .snapshots()
        .map(
          (snap) => snap.docs
              .asMap()
              .entries
              .map(
                (e) => _docToEntry(
                  uid: e.value.id,
                  data: e.value.data(),
                  rank: e.key + 1,
                ),
              )
              .toList(),
        );
  }

  /// Rang approximatif d'un joueur donné.
  ///
  /// Stratégie :
  /// 1. Si l'uid est dans le top-100, retourne son rang exact.
  /// 2. Sinon, count les profils avec elo > monElo → rank = count + 1.
  Future<LeaderboardEntry?> fetchMyRank(String uid) async {
    try {
      final mySnap = await _profiles.doc(uid).get();
      if (!mySnap.exists || mySnap.data() == null) return null;
      final data = mySnap.data()!;
      final myElo = (data['elo'] as num?)?.toInt() ?? PlayerProfile.eloInitial;
      final rawDisplayName = data['display_name'] as String?;
      final myDisplayName =
          (rawDisplayName?.isNotEmpty ?? false) ? rawDisplayName! : 'Grimpeur anonyme';

      // Vérifier si dans top-100.
      final top100Snap = await _profiles
          .orderBy('elo', descending: true)
          .limit(kGlobalTop)
          .get();
      final top100Ids = top100Snap.docs.map((d) => d.id).toList();
      final posInTop100 = top100Ids.indexOf(uid);

      if (posInTop100 >= 0) {
        return LeaderboardEntry(
          uid: uid,
          displayName: myDisplayName,
          elo: myElo,
          rank: posInTop100 + 1,
        );
      }

      // Hors top-100 : count des profils avec elo strictement supérieur.
      final countSnap = await _profiles
          .where('elo', isGreaterThan: myElo)
          .count()
          .get();
      final rank = (countSnap.count ?? 0) + 1;

      return LeaderboardEntry(
        uid: uid,
        displayName: myDisplayName,
        elo: myElo,
        rank: rank,
      );
    } on Exception catch (e) {
      _log.e('fetchMyRank($uid) error', error: e);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Friends leaderboard
  // ---------------------------------------------------------------------------

  /// Stream du classement parmi les amis + soi-même, triés par ELO desc.
  ///
  /// Chaque mise à jour du set d'amis provoque un re-fetch de tous les profils.
  /// Inclut le joueur lui-même au bon rang relatif.
  Stream<List<LeaderboardEntry>> watchFriendsLeaderboard(String myUid) {
    return friendsRepo.watchMyFriends(myUid).asyncMap((friendUids) async {
      final uids = {...friendUids, myUid};
      final profiles = <PlayerProfile>[];

      for (final uid in uids) {
        final p = await profileRepo.fetchProfile(uid);
        if (p != null) profiles.add(p);
      }

      // Tri ELO décroissant.
      profiles.sort((a, b) => b.elo.compareTo(a.elo));

      return profiles
          .asMap()
          .entries
          .map(
            (e) => LeaderboardEntry(
              uid: e.value.uid,
              displayName: e.value.displayLabel,
              elo: e.value.elo,
              rank: e.key + 1,
            ),
          )
          .toList();
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  LeaderboardEntry _docToEntry({
    required String uid,
    required Map<String, dynamic> data,
    required int rank,
  }) {
    final rawName = data['display_name'] as String?;
    final displayName =
        (rawName?.isNotEmpty ?? false) ? rawName! : 'Grimpeur anonyme';
    return LeaderboardEntry(
      uid: uid,
      displayName: displayName,
      elo: (data['elo'] as num?)?.toInt() ?? PlayerProfile.eloInitial,
      rank: rank,
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) {
  return LeaderboardRepository(
    firestore: ref.watch(firestoreProvider),
    profileRepo: ref.watch(profileRepositoryProvider),
    friendsRepo: ref.watch(friendsRepositoryProvider),
  );
});

/// Stream top-100 mondial.
final globalLeaderboardProvider =
    StreamProvider<List<LeaderboardEntry>>((ref) {
  return ref.watch(leaderboardRepositoryProvider).watchGlobalTop100();
});

/// Stream classement amis pour un uid donné.
final friendsLeaderboardProvider =
    StreamProvider.family<List<LeaderboardEntry>, String>((ref, myUid) {
  return ref
      .watch(leaderboardRepositoryProvider)
      .watchFriendsLeaderboard(myUid);
});
