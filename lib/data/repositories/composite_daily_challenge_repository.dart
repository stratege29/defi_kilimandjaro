import 'dart:developer' as developer;

import 'package:defi_kilimandjaro/data/repositories/bundle_daily_challenge_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/firestore_daily_challenge_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/repositories/daily_challenge_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Implémentation **composite** du repo daily : tente d'abord Firestore
/// (pour pousser du contenu événementiel sans release), puis fallback
/// sur le bundle (offline-first garanti).
///
/// Pattern de chaîne de responsabilité simple : `primary` (Firestore) →
/// `fallback` (Bundle). Si jamais on rajoute une 3ᵉ source (ex. cache
/// HTTP CDN), il suffira d'enchaîner.
///
/// C'est ce repo qui est branché en production via le provider Riverpod
/// dédié (`dailyChallengeRepositoryProvider`).
class CompositeDailyChallengeRepository implements DailyChallengeRepository {
  CompositeDailyChallengeRepository({
    required DailyChallengeRepository primary,
    required DailyChallengeRepository fallback,
  })  : _primary = primary,
        _fallback = fallback;

  final DailyChallengeRepository _primary;
  final DailyChallengeRepository _fallback;

  @override
  Future<Devinette?> fetchDevinetteForDate(DateTime date) async {
    try {
      final remote = await _primary.fetchDevinetteForDate(date);
      if (remote != null) return remote;
    } on Object catch (e, stack) {
      developer.log(
        'CompositeDailyChallengeRepository: primary failed, '
        'falling back to bundle',
        error: e,
        stackTrace: stack,
      );
    }
    return _fallback.fetchDevinetteForDate(date);
  }
}

/// Provider principal du repo daily — composite Firestore + bundle.
///
/// Branché ici plutôt que dans un fichier dédié pour rester près de
/// l'impl (les 3 repos vivent dans le même dossier). À déplacer si on
/// élargit le scope.
final dailyChallengeRepositoryProvider =
    Provider<DailyChallengeRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  return CompositeDailyChallengeRepository(
    primary: FirestoreDailyChallengeRepository(
      firestore: firestore,
      prefs: prefs,
    ),
    fallback: BundleDailyChallengeRepository(),
  );
});
