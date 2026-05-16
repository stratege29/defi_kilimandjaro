import 'package:defi_kilimandjaro/domain/entities/pack.dart';

/// Catalogue des packs thématiques disponibles dans le bundle.
///
/// Source de vérité v1 : `assets/data/devinettes/starter/_index.json`
/// (manifest livré avec l'APK, cf. plan.md §3.6). Une v2 pourra remplacer
/// l'implémentation par un appel Cloud Functions sans toucher au domain.
abstract interface class PackCatalogRepository {
  /// Charge la liste complète des packs disponibles. Cache en mémoire.
  Future<List<Pack>> loadAll();

  /// Renvoie un pack par id, ou `null` si inconnu.
  Future<Pack?> byId(String packId);

  /// Liste des packs éligibles au choix gratuit (free_choice_eligible = true).
  /// Utilisé par l'écran d'onboarding "choisis ton premier pack".
  Future<List<Pack>> freeChoiceCandidates();
}
