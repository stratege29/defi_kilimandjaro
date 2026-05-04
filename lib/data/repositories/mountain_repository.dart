import 'dart:convert';

import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Source des montagnes africaines (51 entrées, une par pays).
///
/// Triées par altitude croissante, du Red Rocks de Gambie (53 m)
/// jusqu'au Kilimandjaro (5 895 m, Tanzanie) — boss final.
/// Charge les 51 montagnes d'Afrique depuis le JSON bundlé.
class MountainRepository {
  MountainRepository();

  static const String _path = 'assets/data/mountains.json';
  List<Mountain>? _cache;

  /// Charge la liste complète, triée par altitude croissante.
  // ignore: prefer_expression_function_bodies
  Future<List<Mountain>> loadAll() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(_path);
    final parsed = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(Mountain.fromJson)
        .toList()
      ..sort((a, b) => a.altitude.compareTo(b.altitude));

    // Phase 2.1 stub: les 5 plus petites montagnes sont déverrouillées
    // par défaut (placeholder avant l'éco-progression Phase 2.3).
    final unlocked = <Mountain>[
      for (var i = 0; i < parsed.length; i++)
        parsed[i].copyWith(unlocked: i < 5),
    ];

    _cache = unlocked;
    return unlocked;
  }
}

final mountainRepositoryProvider = Provider<MountainRepository>((ref) {
  return MountainRepository();
});

/// Provider qui expose la liste prête à afficher.
final mountainsProvider = FutureProvider<List<Mountain>>((ref) async {
  return ref.watch(mountainRepositoryProvider).loadAll();
});
