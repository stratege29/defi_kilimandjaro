import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_history_entry.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Repository pour l'historique des duels du joueur.
///
/// Schéma Firestore : `profiles/{uid}/duel_history/{matchId}` subcollection.
/// Écrit par Cloud Function `endMatch` — **lecture seule côté client**.
class DuelHistoryRepository {
  DuelHistoryRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final Logger _log = Logger();

  /// Stream des derniers duels du joueur courant (limit 5, ordered by timestamp desc).
  ///
  /// Retourne une liste vide si pas de duels ou pas connecté.
  Stream<List<DuelHistoryEntry>> watchRecentDuels({int limit = 5}) {
    final uid = auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return firestore
        .collection('profiles')
        .doc(uid)
        .collection('duel_history')
        .orderBy('finished_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final entries = <DuelHistoryEntry>[];
      for (final doc in snap.docs) {
        try {
          entries.add(
            DuelHistoryEntry.fromJson(doc.id, doc.data()),
          );
        } on Object catch (e) {
          _log.w('Failed to parse duel history entry ${doc.id}', error: e);
        }
      }
      return entries;
    });
  }

  /// Lecture ponctuelle des derniers duels du joueur courant.
  Future<List<DuelHistoryEntry>> fetchRecentDuels({int limit = 5}) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return [];

    try {
      final snap = await firestore
          .collection('profiles')
          .doc(uid)
          .collection('duel_history')
          .orderBy('finished_at', descending: true)
          .limit(limit)
          .get();

      final entries = <DuelHistoryEntry>[];
      for (final doc in snap.docs) {
        try {
          entries.add(
            DuelHistoryEntry.fromJson(doc.id, doc.data()),
          );
        } on Object catch (e) {
          _log.w('Failed to parse duel history entry ${doc.id}', error: e);
        }
      }
      return entries;
    } on Exception catch (e) {
      _log.e('fetchRecentDuels failed', error: e);
      return [];
    }
  }
}

final duelHistoryRepositoryProvider = Provider<DuelHistoryRepository>((ref) {
  return DuelHistoryRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

/// Stream provider : derniers duels du joueur courant (5 par défaut).
///
/// Émet une liste vide si pas connecté ou pas de duels.
/// Utilisé dans le hub pour afficher l'historique.
final recentDuelsProvider =
    StreamProvider<List<DuelHistoryEntry>>((ref) {
  return ref.watch(duelHistoryRepositoryProvider).watchRecentDuels();
});
