import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sommet « en cours » pour le Hub d'Accueil.
///
/// Définition : 1ʳᵉ montagne (par altitude croissante) dont
/// `completedLevels < totalLevels`. `null` si tous les sommets ont été
/// gravis — l'UI montre alors un état "tout gravi".
final currentMountainProvider = FutureProvider<Mountain?>((ref) async {
  final mountains = await ref.watch(mountainsProvider.future);
  for (final m in mountains) {
    if (m.completedLevels < m.totalLevels) return m;
  }
  return null;
});
