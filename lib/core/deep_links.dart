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
/// - `kilimandjaro://join?m=ABC&s=secret` (QR flow — scheme différent)
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

/// Service singleton qui écoute les URL scheme `kilimandjaro://duel/<matchId>`
/// et navigue vers `/duel/join/<matchId>`.
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
    final matchId = parseDeepLinkMatchId(uri);
    if (matchId == null) return;
    final context = navigatorKey.currentContext;
    if (context == null) {
      _log.w('DeepLink: contexte navigator null pour $uri');
      return;
    }
    GoRouter.of(context).go(AppRoutes.duelJoinPath(matchId));
  }
}

/// Provider Riverpod du DeepLinkService.
///
/// Utilise appRouterNavigatorKey défini dans app_router.dart.
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  return DeepLinkService(navigatorKey: appRouterNavigatorKey);
});
