import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Repository FCM — gestion du token FCM et des permissions de notification.
///
/// Responsabilités :
/// - Demander les permissions de notification (iOS + Android 13+).
/// - Lire le token FCM courant et le persister dans Firestore.
/// - Écouter les rafraîchissements de token et mettre à jour Firestore.
///
/// Usage dans _BootGateState :
/// ```dart
/// unawaited(ref.read(fcmRepositoryProvider).init());
/// ```
class FcmRepository {
  FcmRepository({
    required FirebaseMessaging messaging,
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  })  : _messaging = messaging,
        _firestore = firestore,
        _auth = auth;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Logger _log = Logger();

  StreamSubscription<String>? _tokenRefreshSub;

  /// Initialise FCM : demande les permissions puis enregistre le token.
  ///
  /// Fire-and-forget depuis le boot — ne jamais await dans main.dart.
  /// Toutes les erreurs sont catchées pour ne pas bloquer l'application.
  Future<void> init() async {
    try {
      await _requestPermission();
      await _persistCurrentToken();
      _listenTokenRefresh();
    } on Exception catch (e, stack) {
      _log.e('FCM init failed', error: e, stackTrace: stack);
    }
  }

  /// Demande les permissions de notification.
  ///
  /// Sur iOS : dialog système obligatoire (APNs).
  /// Sur Android 13+ : permission POST_NOTIFICATIONS (manifest + dialog).
  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission();

    if (kDebugMode) {
      _log.d(
        'FCM permission: ${settings.authorizationStatus.name}',
      );
    }
  }

  /// Lit le token FCM courant et le persiste dans Firestore.
  Future<void> _persistCurrentToken() async {
    // Sur iOS en mode debug/simulator APNs peut ne pas être disponible.
    // getToken() retourne null dans ce cas.
    final token = await _messaging.getToken();
    if (token == null) {
      _log.w('FCM token null (APNs indisponible ? simulateur ?)');
      return;
    }
    await _writeToken(token);
  }

  /// Écoute les renouvellements de token (rotation automatique FCM).
  void _listenTokenRefresh() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _messaging.onTokenRefresh.listen(
      _writeToken,
      onError: (Object e) {
        _log.e('FCM token refresh error', error: e);
      },
    );
  }

  /// Écrit le token dans Firestore profiles/{uid}/fcm_token.
  ///
  /// Utilise [SetOptions(merge: true)] pour ne pas écraser les autres champs.
  Future<void> _writeToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      _log.w('FCM writeToken: aucun utilisateur connecté, skip.');
      return;
    }

    try {
      await _firestore.collection('profiles').doc(uid).set(
        {
          'fcm_token': token,
          'fcm_updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _log.i('FCM token enregistre pour uid=$uid');
    } on Exception catch (e) {
      _log.e('FCM writeToken Firestore failed', error: e);
    }
  }

  /// Libère les ressources (listener token refresh).
  void dispose() {
    _tokenRefreshSub?.cancel();
  }
}

/// Provider Riverpod du FcmRepository.
final fcmRepositoryProvider = Provider<FcmRepository>((ref) {
  final repo = FcmRepository(
    messaging: FirebaseMessaging.instance,
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
  ref.onDispose(repo.dispose);
  return repo;
});
