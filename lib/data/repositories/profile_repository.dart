import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/player_profile.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Repository Firestore pour les profils ELO des joueurs.
///
/// Règles de sécurité :
/// - **Lecture** : autorisée côté client (pour afficher l'altitude).
/// - **Écriture** : bloquée côté client — uniquement via Admin SDK
///   (Cloud Functions `endMatch` et `requestMatch`).
///
/// L'initialisation du profil (elo=1000) est faite par `requestMatch`
/// lors du premier appel au matchmaking.
class ProfileRepository {
  ProfileRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final Logger _log = Logger();

  CollectionReference<Map<String, dynamic>> get _profiles =>
      firestore.collection('profiles');

  /// Stream live du profil du joueur courant.
  /// Retourne [PlayerProfile.initial] si le document n'existe pas encore.
  Stream<PlayerProfile> watchMyProfile() {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      _log.w('watchMyProfile appelé sans uid — retourne profil initial');
      return Stream.value(PlayerProfile.initial('anonymous'));
    }
    return _profiles.doc(uid).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return PlayerProfile.initial(uid);
      }
      return PlayerProfile.fromJson(uid, snap.data()!);
    });
  }

  /// Lecture ponctuelle du profil du joueur courant.
  Future<PlayerProfile> fetchMyProfile() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return PlayerProfile.initial('anonymous');

    final snap = await _profiles.doc(uid).get();
    if (!snap.exists || snap.data() == null) {
      return PlayerProfile.initial(uid);
    }
    return PlayerProfile.fromJson(uid, snap.data()!);
  }

  /// Lecture du profil d'un autre joueur (pour affichage dans l'écran de
  /// résultat ou le lobby).
  Future<PlayerProfile?> fetchProfile(String uid) async {
    try {
      final snap = await _profiles.doc(uid).get();
      if (!snap.exists || snap.data() == null) return null;
      return PlayerProfile.fromJson(uid, snap.data()!);
    } on Exception catch (e) {
      _log.e('fetchProfile($uid) failed', error: e);
      return null;
    }
  }
}

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

/// Stream provider de l'altitude (ELO) du joueur courant.
/// Utilisé dans le lobby, le profil, l'en-tête hub.
final playerProfileStreamProvider = StreamProvider<PlayerProfile>((ref) {
  return ref.watch(profileRepositoryProvider).watchMyProfile();
});
