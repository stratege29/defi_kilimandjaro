import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sauvegarde cloud de la progression **solo** dans `player_progress/{uid}`.
///
/// Permet la récupération multi-appareil : un joueur qui réinstalle l'app et
/// reconnecte son compte Google/Apple retrouve niveaux, étoiles, séries,
/// freeze tokens, packs possédés, etc.
///
/// **Hors périmètre — cauris** : le solde reste autorité serveur (wallet
/// Cloud Functions, `users/{uid}/inventory/wallet`). On ne sauvegarde ni ne
/// restaure jamais le solde via ce doc client-inscriptible (anti-inflation).
///
/// Tout est *fail-soft* : une erreur réseau ne dégrade jamais le jeu offline.
class ProgressSyncService {
  ProgressSyncService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const String _collection = 'player_progress';

  /// Clés jamais écrites/relues côté cloud (autorité wallet serveur).
  /// `coins` est l'ancienne clé pré-rebranding Cauris — exclue par sécurité.
  static const Set<String> _walletKeys = {'cauris', 'coins'};

  DocumentReference<Map<String, dynamic>>? _doc() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    return _db.collection(_collection).doc(uid);
  }

  /// Récupère l'instantané cloud de l'utilisateur courant, ou `null` si
  /// absent / non connecté / erreur. Le solde de cauris éventuellement
  /// présent est ignoré (jamais restauré côté client).
  Future<PlayerProgress?> fetch() async {
    final doc = _doc();
    if (doc == null) return null;
    try {
      final snap = await doc.get();
      final data = snap.data();
      if (data == null) return null;
      final clean = Map<String, dynamic>.from(data)
        ..remove('updated_at')
        ..removeWhere((key, _) => _walletKeys.contains(key));
      return PlayerProgress.fromJson(clean);
    } on Object {
      return null; // fail-soft : ne jamais bloquer le boot / le jeu offline.
    }
  }

  /// Pousse l'instantané local vers le cloud (sans le solde de cauris).
  Future<void> push(PlayerProgress progress) async {
    final doc = _doc();
    if (doc == null) return;
    try {
      final json = progress.toJson()
        ..removeWhere((key, _) => _walletKeys.contains(key));
      json['updated_at'] = FieldValue.serverTimestamp();
      await doc.set(json);
    } on Object {
      // fail-soft : la prochaine mutation re-tentera la sauvegarde.
    }
  }
}

final progressSyncServiceProvider = Provider<ProgressSyncService>(
  (ref) => ProgressSyncService(),
);

/// Orchestration restauration + sauvegarde de la progression solo.
class ProgressSyncCoordinator {
  ProgressSyncCoordinator(this._ref);

  final Ref _ref;

  /// Récupère le cloud, le fusionne dans l'état local (best-of-both) puis
  /// repousse l'état fusionné — de sorte que le cloud reflète aussi les
  /// gains réalisés hors-ligne sur ce device. À appeler au boot et après
  /// une (re)connexion de compte.
  Future<void> restoreAndBackup() async {
    final sync = _ref.read(progressSyncServiceProvider);
    final cloud = await sync.fetch();
    if (cloud != null) {
      await _ref.read(playerProgressProvider.notifier).mergeCloud(cloud);
    }
    await sync.push(_ref.read(playerProgressProvider));
  }

  /// Sauvegarde immédiate de l'état local courant.
  Future<void> backup() =>
      _ref.read(progressSyncServiceProvider).push(
            _ref.read(playerProgressProvider),
          );
}

final progressSyncCoordinatorProvider = Provider<ProgressSyncCoordinator>(
  ProgressSyncCoordinator.new,
);

/// Sauvegarde cloud **debouncée** : à chaque mutation de la progression,
/// (re)planifie un push 3 s plus tard. Coalesce les rafales de mutations
/// (ex. fin de niveau : cauris + étoiles + streak en quelques ms) en une
/// seule écriture Firestore.
///
/// À instancier une fois au boot (`ref.read(progressAutoBackupProvider)`)
/// après que la session Firebase est prête. Reste vivant tant que le
/// `ProviderScope` racine existe.
final progressAutoBackupProvider = Provider<void>((ref) {
  Timer? timer;
  ref
    ..onDispose(() => timer?.cancel())
    ..listen<PlayerProgress>(playerProgressProvider, (_, __) {
      timer?.cancel();
      timer = Timer(const Duration(seconds: 3), () {
        ref.read(progressSyncServiceProvider).push(
              ref.read(playerProgressProvider),
            );
      });
    });
});
