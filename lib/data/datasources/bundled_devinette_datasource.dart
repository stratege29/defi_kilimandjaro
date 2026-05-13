import 'dart:convert';

import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;

/// Charge le starter pack bundlé depuis `assets/data/devinettes/starter/<world>.json`.
///
/// Toujours disponible, même offline first-launch — c'est la base que la
/// composite repository augmente avec les packs téléchargés.
class BundledDevinetteDatasource {
  BundledDevinetteDatasource({String basePath = 'assets/data/devinettes/starter'})
      : _basePath = basePath;

  final String _basePath;
  final Map<String, List<Devinette>> _memCache = <String, List<Devinette>>{};

  Future<List<Devinette>> loadWorld(String worldId) async {
    final cached = _memCache[worldId];
    if (cached != null) return cached;

    final String raw;
    try {
      raw = await rootBundle.loadString('$_basePath/$worldId.json');
      // ignore: avoid_catching_errors
    } on FlutterError {
      // rootBundle.loadString lève un FlutterError quand l'asset est absent.
      // Pour un monde non encore curé, on retombe sur un starter vide plutôt
      // que de propager — la composite peut alors compléter avec le cache
      // remote. Voir aussi `pubspec.yaml > assets`.
      _memCache[worldId] = const <Devinette>[];
      return _memCache[worldId]!;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      _memCache[worldId] = const <Devinette>[];
      return _memCache[worldId]!;
    }

    final list = decoded
        .cast<Map<String, dynamic>>()
        .map(Devinette.fromJson)
        .toList(growable: false);

    _memCache[worldId] = list;
    return list;
  }

  /// Vide le cache mémoire (utile pour les tests ou un éventuel "reset
  /// content" depuis les paramètres).
  void clearCache() => _memCache.clear();
}
