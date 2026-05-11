import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Repository des relations d'abonnement (unidirectional follow).
///
/// Schéma Firestore : `friendships/{myUid}/followed/{friendUid}`
///   → `{ created_at: Timestamp }`
///
/// Règles de sécurité : le bloc `friendships` est ouvert en écriture
/// authentifiée (cf. firestore.rules étendu pour cette PR).
///
/// Limite UI : [kMaxFriends] amis max par profil — appliquée côté lecture via
/// `.limit()` sur la query Firestore. Cette limite protège contre l'explosion
/// des streams sans bloquer les writes légitimes.
class FriendsRepository {
  FriendsRepository({required this.firestore});

  /// Nombre maximum d'amis streamés.
  static const int kMaxFriends = 50;

  final FirebaseFirestore firestore;
  final Logger _log = Logger();

  CollectionReference<Map<String, dynamic>> _followedRef(String myUid) =>
      firestore
          .collection('friendships')
          .doc(myUid)
          .collection('followed');

  DocumentReference<Map<String, dynamic>> _friendDoc(
    String myUid,
    String friendUid,
  ) =>
      _followedRef(myUid).doc(friendUid);

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Abonne [myUid] à [friendUid].
  Future<void> addFriend(String myUid, String friendUid) async {
    if (myUid == friendUid) {
      throw ArgumentError('Cannot follow yourself');
    }
    try {
      await _friendDoc(myUid, friendUid).set(<String, dynamic>{
        'created_at': FieldValue.serverTimestamp(),
      });
      _log.i('$myUid → follow $friendUid');
    } on Exception catch (e) {
      _log.e('addFriend error', error: e);
      rethrow;
    }
  }

  /// Désabonne [myUid] de [friendUid].
  Future<void> removeFriend(String myUid, String friendUid) async {
    try {
      await _friendDoc(myUid, friendUid).delete();
      _log.i('$myUid → unfollow $friendUid');
    } on Exception catch (e) {
      _log.e('removeFriend error', error: e);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Stream des UIDs suivis (limité à [kMaxFriends]).
  Stream<Set<String>> watchMyFriends(String myUid) {
    return _followedRef(myUid)
        .limit(kMaxFriends)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toSet());
  }

  /// Vérifie si [myUid] suit [friendUid] (lecture ponctuelle).
  Future<bool> isFriend(String myUid, String friendUid) async {
    final doc = await _friendDoc(myUid, friendUid).get();
    return doc.exists;
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final friendsRepositoryProvider = Provider<FriendsRepository>((ref) {
  return FriendsRepository(
    firestore: ref.watch(firestoreProvider),
  );
});
