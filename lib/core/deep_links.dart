import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';

/// Extrait le matchId depuis une URI deep link `kilimandjaro://duel/<matchId>`.
///
/// Retourne null si l'URI ne correspond pas au schéma attendu.
///
/// Exemples valides :
/// - `kilimandjaro://duel/ABC123` → `'ABC123'`
/// - `kilimandjaro://duel/ABC123/` → `'ABC123'`
///
/// Exemples invalides (retournent null) :
/// - `https://kilimandjaro.app/duel/ABC123`
/// - `kilimandjaro://join?m=ABC&s=secret` (QR de duel — voir
///   [parseDeepLinkJoin], qui porte en plus le secret)
/// - `kilimandjaro://duel/` (matchId vide)
String? parseDeepLinkMatchId(Uri uri) {
  if (uri.scheme != 'kilimandjaro') return null;
  if (uri.host != 'duel') return null;
  final segments = uri.pathSegments;
  if (segments.isEmpty) return null;
  final matchId = segments.first.trim();
  if (matchId.isEmpty) return null;
  return matchId;
}

/// Extrait `(matchId, secret)` depuis le payload d'un QR de duel
/// `kilimandjaro://join?m=<matchId>&s=<secret>`.
///
/// C'est la valeur encodée par `DuelSession.toQrPayload()`. Le scanner
/// in-app la lit via `DuelSession.parseQrPayload`, mais le même QR peut
/// être scanné par l'appareil photo du téléphone : iOS/Android ouvrent
/// alors l'URL comme un deep link, et c'est ce parseur qui la reçoit.
///
/// Retourne null si l'URI ne correspond pas au schéma attendu.
///
/// Exemples valides :
/// - `kilimandjaro://join?m=ABC123&s=deadbeef` → `('ABC123', 'deadbeef')`
///
/// Exemples invalides (retournent null) :
/// - `kilimandjaro://join?m=ABC123` (secret manquant)
/// - `kilimandjaro://duel/ABC123` (autre schéma)
({String matchId, String secret})? parseDeepLinkJoin(Uri uri) {
  if (uri.scheme != 'kilimandjaro') return null;
  if (uri.host != 'join') return null;
  final matchId = uri.queryParameters['m']?.trim() ?? '';
  final secret = uri.queryParameters['s']?.trim() ?? '';
  if (matchId.isEmpty || secret.isEmpty) return null;
  return (matchId: matchId, secret: secret);
}

/// Extrait l'uid depuis une URI deep link `kilimandjaro://friend/<uid>`.
///
/// Retourne null si l'URI ne correspond pas au schéma attendu.
///
/// Exemples valides :
/// - `kilimandjaro://friend/abc123uid` → `'abc123uid'`
///
/// Exemples invalides (retournent null) :
/// - `https://kilimandjaro.app/friend/uid`
/// - `kilimandjaro://duel/ABC123`
/// - `kilimandjaro://friend/` (uid vide)
String? parseDeepLinkFriendUid(Uri uri) {
  if (uri.scheme != 'kilimandjaro') return null;
  if (uri.host != 'friend') return null;
  final segments = uri.pathSegments;
  if (segments.isEmpty) return null;
  final uid = segments.first.trim();
  if (uid.isEmpty) return null;
  return uid;
}

/// Service singleton qui écoute les URL scheme `kilimandjaro://…` et navigue
/// vers la route correspondante.
///
/// Schémas pris en charge :
/// - `kilimandjaro://duel/<matchId>` → `/duel/join/<matchId>`
/// - `kilimandjaro://join?m=…&s=…` (QR de duel) → idem, secret en query
/// - `kilimandjaro://friend/<uid>` → `/friend/add/<uid>`
///
/// La vue DuelDeepLinkView gère ensuite le join Firebase asynchrone et
/// l'affichage de l'état de chargement / erreur.
///
/// Gère les deux cas :
/// - **Cold start** : URI disponible immédiatement via AppLinks.getInitialLink.
/// - **Warm start** : URI poussée via AppLinks.uriLinkStream.
class DeepLinkService {
  DeepLinkService({required this.navigatorKey});

  /// Clé de navigation du router go_router (exposée via appRouterNavigatorKey).
  final GlobalKey<NavigatorState> navigatorKey;

  final _appLinks = AppLinks();
  final _log = Logger();
  StreamSubscription<Uri>? _sub;

  /// Démarre l'écoute. Appeler une seule fois au boot depuis _BootGate.
  Future<void> init() async {
    // Cold start — récupère l'URI avant de s'abonner au stream.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _log.i('DeepLink cold-start: $initial');
        // Diffère pour laisser le router monter complètement.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        _handle(initial);
      }
    } on Exception catch (e) {
      _log.w('DeepLink getInitialLink error: $e');
    }

    // Warm start — app en background.
    _sub = _appLinks.uriLinkStream.listen(
      (uri) {
        _log.i('DeepLink warm-start: $uri');
        _handle(uri);
      },
      onError: (Object e) => _log.w('DeepLink stream error: $e'),
    );
  }

  /// Arrête l'écoute (utile pour les tests et le dispose propre).
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  void _handle(Uri uri) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      _log.w('DeepLink: contexte navigator null pour $uri');
      return;
    }

    // `kilimandjaro://join?m=<matchId>&s=<secret>` → QR de duel scanné
    // hors de l'app (appareil photo). Le secret est transmis pour rester
    // sur le flux vérifié côté serveur.
    final join = parseDeepLinkJoin(uri);
    if (join != null) {
      GoRouter.of(context).go(
        AppRoutes.duelJoinPath(join.matchId, secret: join.secret),
      );
      return;
    }

    // `kilimandjaro://duel/<matchId>` → join duel.
    final matchId = parseDeepLinkMatchId(uri);
    if (matchId != null) {
      GoRouter.of(context).go(AppRoutes.duelJoinPath(matchId));
      return;
    }

    // `kilimandjaro://friend/<uid>` → confirmation ajout ami.
    final friendUid = parseDeepLinkFriendUid(uri);
    if (friendUid != null) {
      GoRouter.of(context).go(AppRoutes.friendAddPath(friendUid));
    }
  }
}

/// Provider Riverpod du DeepLinkService.
///
/// Utilise appRouterNavigatorKey défini dans app_router.dart.
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  return DeepLinkService(navigatorKey: appRouterNavigatorKey);
});
