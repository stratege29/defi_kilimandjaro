import 'package:defi_kilimandjaro/domain/entities/pack.dart';

/// Logique pure de détection des nouveaux packs à annoncer à l'utilisateur.
///
/// Volontairement sans I/O ni dépendance data : prend en entrée un catalogue
/// déjà résolu (bundle + cache distant), l'ensemble des packs possédés et
/// l'ensemble des packs déjà « vus » (persistés ailleurs), et retourne la
/// liste des packs réellement nouveaux. Testable unitairement.
///
/// Le calcul des **mises à jour de contenu** (comparaison version installée vs
/// manifest distant) vit côté data — il manipule des types data-layer
/// (`PackStateRow`, `ContentPackManifest`) et n'a pas sa place dans le domain.
class PackNotificationDetector {
  const PackNotificationDetector._();

  /// Packs « nouveaux » à annoncer : présents au catalogue, non possédés,
  /// jamais vus. L'ordre du catalogue (déjà trié par `ordering`) est conservé.
  ///
  /// L'appelant est responsable du *baselining* au premier lancement : tant que
  /// l'utilisateur n'a pas de référentiel « vu », il faut considérer tout le
  /// catalogue courant comme déjà connu (sinon on annoncerait tout d'un coup).
  static List<Pack> newPacks({
    required List<Pack> catalog,
    required Set<String> ownedIds,
    required Set<String> seenIds,
  }) {
    return catalog
        .where((p) => !ownedIds.contains(p.id) && !seenIds.contains(p.id))
        .toList(growable: false);
  }
}
