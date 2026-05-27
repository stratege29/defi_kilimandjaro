import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/repositories/daily_challenge_repository.dart';
import 'package:defi_kilimandjaro/domain/services/daily_challenge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Implémentation **Firestore** du repo daily : lit le document
/// `daily_challenges/{yyyy-MM-dd}` et persiste le dernier doc lu en
/// `SharedPreferences` (cache local) pour servir le mode offline.
///
/// **Stratégie réseau** :
/// 1. Tente une lecture Firestore avec timeout court (3 s).
/// 2. Si succès → écrit la réponse en cache local + retourne.
/// 3. Si échec (offline, timeout, doc absent) → lit le cache local
///    pour cette date exacte. Si présent → retourne. Sinon `null`.
///
/// Le cache stocke 1 entrée par date (clé `daily_cache_{yyyy-MM-dd}`).
/// Auto-clean : aucune politique de purge active dans cette PR — la
/// taille reste minime (1 entrée/jour, ~1 KB chacune). À ajouter si
/// le seed Firestore grossit beaucoup.
///
/// Le doc Firestore attendu suit le schéma `Devinette.toJson()`. Côté
/// console / scripts admin, c'est à l'éditorial de pusher des docs
/// conformes (cf. `tools/admin_console/`).
class FirestoreDailyChallengeRepository implements DailyChallengeRepository {
  FirestoreDailyChallengeRepository({
    required FirebaseFirestore firestore,
    required SharedPreferences prefs,
    Duration networkTimeout = const Duration(seconds: 3),
  })  : _firestore = firestore,
        _prefs = prefs,
        _networkTimeout = networkTimeout;

  static const String _collectionPath = 'daily_challenges';
  static const String _cacheKeyPrefix = 'daily_cache_';

  final FirebaseFirestore _firestore;
  final SharedPreferences _prefs;
  final Duration _networkTimeout;

  @override
  Future<Devinette?> fetchDevinetteForDate(DateTime date) async {
    final docId = DailyChallengeService.dailyKeyForDate(date);
    // 1. Tentative Firestore.
    try {
      final snap = await _firestore
          .collection(_collectionPath)
          .doc(docId)
          .get()
          .timeout(_networkTimeout);
      final data = snap.data();
      if (data != null) {
        final devinette = Devinette.fromJson(
          data,
          source: DevinetteSource.remotePack,
        );
        // Cache pour les futurs accès offline.
        await _writeCache(docId, data);
        return devinette;
      }
      // Doc inexistant : aucun mot configuré pour cette date côté
      // remote — on retourne null, le composite enchaînera sur le
      // bundle fallback.
      return null;
    } on Object catch (e, stack) {
      // Échec réseau / timeout — on tente le cache local.
      developer.log(
        'FirestoreDailyChallengeRepository: fetch failed for $docId — '
        'fallback to local cache',
        error: e,
        stackTrace: stack,
      );
      return _readCache(docId);
    }
  }

  Future<void> _writeCache(String docId, Map<String, dynamic> data) async {
    try {
      await _prefs.setString(
        '$_cacheKeyPrefix$docId',
        jsonEncode(data),
      );
    } on Object {
      // Best-effort cache write — pas critique de planter ici.
    }
  }

  Devinette? _readCache(String docId) {
    final raw = _prefs.getString('$_cacheKeyPrefix$docId');
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return Devinette.fromJson(data, source: DevinetteSource.remotePack);
    } on FormatException {
      return null;
    }
  }
}
