import 'dart:convert';

import 'package:defi_kilimandjaro/domain/entities/proverb.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Repository des proverbes ivoiriens (asset JSON local).
class ProverbRepository {
  ProverbRepository();

  static const _assetPath = 'assets/data/proverbes_ci.json';

  List<Proverb>? _cache;

  Future<List<Proverb>> loadAll() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString(_assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['proverbs'] as List<dynamic>)
        .map((e) => Proverb.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    _cache = list;
    return list;
  }
}

final proverbRepositoryProvider =
    Provider<ProverbRepository>((_) => ProverbRepository());

/// Proverbe du jour : sélection déterministe basée sur le jour de l'année.
///
/// La même seed produit le même proverbe pour tous les joueurs ouvrant
/// l'app le même jour — cohérent avec « Sagesse du jour ».
final dailyProverbProvider = FutureProvider<Proverb>((ref) async {
  final repo = ref.watch(proverbRepositoryProvider);
  final proverbs = await repo.loadAll();
  if (proverbs.isEmpty) {
    throw StateError('proverbes_ci.json is empty');
  }
  final now = DateTime.now();
  final dayOfYear =
      now.difference(DateTime(now.year)).inDays + now.year;
  final index = dayOfYear.abs() % proverbs.length;
  return proverbs[index];
});
