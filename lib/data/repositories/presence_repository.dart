import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Repository pour la présence en ligne des joueurs.
///
/// Utilise un modèle standard : source de vérité = ensemble `presence/{uid}`;
/// une Cloud Function planifiée (prunePresence) recalcule proprement
/// `/lobby/stats/online` toutes les 1 minute en purgant les entrées TTL >= 120s.
///
/// Le client responsabilités :
/// - Écrire `presence/{uid} = { ts: ServerValue.timestamp }` au démarrage.
/// - Configurer `onDisconnect().remove()` pour nettoyer à la déconnexion.
/// - Maintenir un heartbeat toutes les 45s (réécrit `ts`) — idempotent.
/// - Appeler `stop()` explicitement à la déconnexion (annule le timer).
///
/// Le client lit simplement `/lobby/stats/online` (entier calculé par la CF).
class PresenceRepository {
  PresenceRepository({
    required this.database,
    required this.auth,
  });

  final FirebaseDatabase database;
  final FirebaseAuth auth;
  final Logger _log = Logger();

  Timer? _heartbeatTimer;
  bool _isRunning = false;

  DatabaseReference get _statsRef => database.ref('lobby/stats');
  DatabaseReference get _onlineRef => _statsRef.child('online');

  /// Démarre la présence du joueur courant.
  ///
  /// Écrit `presence/{uid} = { ts: ServerValue.timestamp }`,
  /// configure `onDisconnect().remove()`, et lance un heartbeat
  /// toutes les 45 secondes. Idempotent : ne double pas le timer
  /// si déjà démarré.
  Future<void> start() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      _log.w('start() called with null uid, no-op');
      return;
    }

    if (_isRunning) {
      _log.i('Presence already running for $uid');
      return;
    }

    try {
      final presenceRef = database.ref('presence/$uid');

      // Écriture initiale + setup onDisconnect
      await presenceRef.set({
        'ts': ServerValue.timestamp,
      });
      await presenceRef.onDisconnect().remove();

      _isRunning = true;

      // Heartbeat : réécrit ts toutes les 45 secondes
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 45),
        (_) async {
          try {
            if (_isRunning) {
              await presenceRef.update({
                'ts': ServerValue.timestamp,
              });
              _log.d('Heartbeat sent for $uid');
            }
          } on Exception catch (e) {
            _log.e('Heartbeat failed for $uid', error: e);
          }
        },
      );

      _log.i('Presence started for $uid with 45s heartbeat');
    } on Exception catch (e) {
      _log.e('start() failed', error: e);
      _isRunning = false;
      rethrow;
    }
  }

  /// Arrête la présence du joueur courant.
  ///
  /// Annule le timer de heartbeat, détruit `onDisconnect()` s'il n'a pas
  /// déclenché, et supprime l'entrée `presence/{uid}`.
  Future<void> stop() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    if (!_isRunning) return;

    try {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _isRunning = false;

      final presenceRef = database.ref('presence/$uid');
      await Future.wait([
        presenceRef.onDisconnect().cancel(),
        presenceRef.remove(),
      ]);

      _log.i('Presence stopped for $uid');
    } on Exception catch (e) {
      _log.e('stop() failed', error: e);
    }
  }

  /// Stream the online player count.
  ///
  /// Listens to `/lobby/stats/online` (calculé par prunePresence CF).
  /// Emits 0 if the path doesn't exist or is null.
  Stream<int> watchOnlineCount() {
    return _onlineRef.onValue.map((event) {
      final value = event.snapshot.value;
      if (value == null) return 0;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return 0;
    });
  }
}

final presenceRepositoryProvider = Provider<PresenceRepository>((ref) {
  return PresenceRepository(
    database: FirebaseDatabase.instance,
    auth: FirebaseAuth.instance,
  );
});

/// Provider autoDispose qui gère le cycle de vie de la présence.
///
/// Démarre le heartbeat au premier watch et l'arrête à la disposition.
/// Utilisé dans DuelHubView pour maintenir la présence tant que le hub est affiché.
final presenceHeartbeatProvider = Provider.autoDispose<void>((ref) {
  final repo = ref.watch(presenceRepositoryProvider)..start();
  ref.onDispose(repo.stop);
});

/// Stream provider : nombre actuel de joueurs en ligne.
///
/// Émet 0 si pas connecté ou si le compteur n'existe pas.
/// Utilisé pour afficher "N grimpeurs en ligne" dans le hub.
final onlinePlayersCountProvider = StreamProvider<int>((ref) {
  return ref.watch(presenceRepositoryProvider).watchOnlineCount();
});
