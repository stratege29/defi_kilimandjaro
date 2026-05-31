import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Repository pour la présence en ligne des joueurs.
///
/// Utilise un compteur centralisé `/lobby/stats/online` en Realtime DB
/// pour éviter les contentions lors de la lecture de `/lobby/*`.
/// Incrémenté/décrémenté via onDisconnect() dans le Cloud Function
/// `requestMatch` et lors de l'entrée au lobby (client-side via updatePresence).
class PresenceRepository {
  PresenceRepository({
    required this.database,
    required this.auth,
  });

  final FirebaseDatabase database;
  final FirebaseAuth auth;
  final Logger _log = Logger();

  DatabaseReference get _statsRef => database.ref('lobby/stats');
  DatabaseReference get _onlineRef => _statsRef.child('online');

  /// Enregistre la présence du joueur courant et l'ajoute au compteur.
  ///
  /// Écrit un timestamp dans `presence/{uid}` et configure
  /// `onDisconnect()` pour décrémenter le compteur `/lobby/stats/online`.
  /// Appelé une seule fois à l'entrée au hub/lobby.
  Future<void> registerPresence() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final updates = <String, Object?>{
        'presence/$uid': {
          'ts': now,
        },
        'lobby/stats/online': ServerValue.increment(1),
      };

      await database.ref().update(updates);

      // Setup onDisconnect to decrement counter when connection drops
      await _onlineRef.onDisconnect().set(
        ServerValue.increment(-1),
      );

      _log.i('Presence registered for $uid');
    } on Exception catch (e) {
      _log.e('registerPresence failed', error: e);
    }
  }

  /// Unregisters presence explicitly (e.g., on logout).
  Future<void> unregisterPresence() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await database.ref().update(<String, Object?>{
        'presence/$uid': null,
        'lobby/stats/online': ServerValue.increment(-1),
      });

      _log.i('Presence unregistered for $uid');
    } on Exception catch (e) {
      _log.e('unregisterPresence failed', error: e);
    }
  }

  /// Stream the online player count.
  ///
  /// Listens to `/lobby/stats/online` and emits the count.
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

/// Stream provider : nombre actuel de joueurs en ligne.
///
/// Émet 0 si pas connecté ou si le compteur n'existe pas.
/// Utilisé pour afficher "N grimpeurs en ligne" dans le hub.
final onlinePlayersCountProvider = StreamProvider<int>((ref) {
  return ref.watch(presenceRepositoryProvider).watchOnlineCount();
});
