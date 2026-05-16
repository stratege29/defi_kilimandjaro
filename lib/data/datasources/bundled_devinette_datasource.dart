import 'dart:convert';

import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;

/// Charge le starter pack bundlé depuis `assets/data/devinettes/starter/<packId>.json`.
///
/// Toujours disponible, même offline first-launch — c'est la base que la
/// composite repository augmente avec les packs téléchargés.
class BundledDevinetteDatasource {
  BundledDevinetteDatasource({String basePath = 'assets/data/devinettes/starter'})
      : _basePath = basePath;

  final String _basePath;
  final Map<String, List<Devinette>> _memCache = <String, List<Devinette>>{};

  Future<List<Devinette>> loadPack(String packId) async {
    final cached = _memCache[packId];
    if (cached != null) return cached;

    final String raw;
    try {
      raw = await rootBundle.loadString('$_basePath/$packId.json');
      // ignore: avoid_catching_errors
    } on FlutterError {
      // rootBundle.loadString lève un FlutterError quand l'asset est absent.
      // Pour un pack non encore curé, on retombe sur un starter vide plutôt
      // que de propager — la composite peut alors compléter avec le cache
      // remote. Voir aussi `pubspec.yaml > assets`.
      _memCache[packId] = const <Devinette>[];
      return _memCache[packId]!;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      _memCache[packId] = const <Devinette>[];
      return _memCache[packId]!;
    }

    final list = decoded
        .cast<Map<String, dynamic>>()
        .map(Devinette.fromJson)
        .toList(growable: false);

    _memCache[packId] = list;
    return list;
  }

  /// Vide le cache mémoire (utile pour les tests ou un éventuel "reset
  /// content" depuis les paramètres).
  void clearCache() => _memCache.clear();
}
