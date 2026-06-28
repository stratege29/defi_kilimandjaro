import 'package:defi_kilimandjaro/data/local/devinette_database.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_devinette_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/sync/content_pack_manifest.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/domain/services/pack_notification_detector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistance locale des notifications de packs : quels packs ont déjà été
/// annoncés à l'utilisateur, et jusqu'à quand reporter une relance.
///
/// Stocké en `SharedPreferences` (même approche que le cache catalog distant).
/// La détection elle-même est sans réseau au boot : elle s'appuie sur le
/// snapshot catalog déjà mis en cache disque (cf `RemoteCatalogDatasource`).
class PackNotificationRepository {
  PackNotificationRepository({
    Future<SharedPreferences> Function()? prefsFactory,
  }) : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsFactory;

  /// Ids de packs déjà présentés à l'utilisateur (modale « nouveau pack »).
  static const String _seenKey = 'pack_notif_seen_ids_v1';

  /// Flag de premier passage : permet de *baseliner* le catalogue existant
  /// sans rien annoncer au tout premier lancement.
  static const String _initializedKey = 'pack_notif_initialized_v1';

  /// Timestamp epoch (ms) jusqu'auquel on ne relance pas la modale (« Plus
  /// tard »). Ne marque PAS les packs comme vus — ils réapparaîtront ensuite.
  static const String _snoozeKey = 'pack_notif_snooze_until_v1';

  Future<Set<String>> seenPackIds() async {
    final prefs = await _prefsFactory();
    return (prefs.getStringList(_seenKey) ?? const <String>[]).toSet();
  }

  Future<bool> isInitialized() async {
    final prefs = await _prefsFactory();
    return prefs.getBool(_initializedKey) ?? false;
  }

  /// Marque le référentiel comme initialisé en considérant `currentIds` comme
  /// déjà connus. À appeler une seule fois, au premier lancement.
  Future<void> initializeBaseline(Iterable<String> currentIds) async {
    final prefs = await _prefsFactory();
    await prefs.setStringList(_seenKey, currentIds.toSet().toList());
    await prefs.setBool(_initializedKey, true);
  }

  /// Ajoute des ids à l'ensemble « vu » (après affichage / découverte).
  Future<void> markSeen(Iterable<String> ids) async {
    final prefs = await _prefsFactory();
    final current = (prefs.getStringList(_seenKey) ?? const <String>[]).toSet()
      ..addAll(ids);
    await prefs.setStringList(_seenKey, current.toList());
  }

  Future<DateTime?> snoozeUntil() async {
    final prefs = await _prefsFactory();
    final ms = prefs.getInt(_snoozeKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> snooze(DateTime until) async {
    final prefs = await _prefsFactory();
    await prefs.setInt(_snoozeKey, until.millisecondsSinceEpoch);
  }

  /// Vrai si le contenu OTA distant est plus récent que ce qui est installé
  /// localement — soit jamais téléchargé, soit version/hash différents.
  ///
  /// Mire exacte de la décision de download dans `ManifestSyncService`
  /// (`upToDate`), pour que le bandeau ne signale une MAJ que si un sync la
  /// téléchargerait effectivement.
  static bool needsUpdate(ContentPackManifest manifest, PackStateRow? local) {
    if (!manifest.enabled) return false;
    if (local == null) return true;
    final upToDate = local.packVersion == manifest.currentVersion &&
        local.hashSha256 == manifest.hashSha256;
    return !upToDate;
  }
}

// ===========================================================================
// Providers Riverpod
// ===========================================================================

final packNotificationRepositoryProvider =
    Provider<PackNotificationRepository>((ref) {
  return PackNotificationRepository();
});

/// Délai de relance après un « Plus tard » sur la modale nouveau pack.
const Duration kNewPackSnoozeDuration = Duration(days: 3);

/// Nouveaux packs à annoncer au boot (modale). **Zéro réseau** : lit le
/// catalogue résolu (bundle + cache disque). Gère le baselining premier run
/// et le snooze « Plus tard ».
final newPacksProvider = FutureProvider<List<Pack>>((ref) async {
  final repo = ref.watch(packNotificationRepositoryProvider);
  final catalog = await ref.watch(packCatalogProvider.future);
  final owned = ref.watch(ownedPacksProvider);

  // Premier lancement : on considère le catalogue existant comme connu et on
  // n'annonce rien (sinon déluge de « nouveautés » dès l'install).
  if (!await repo.isInitialized()) {
    await repo.initializeBaseline(catalog.map((p) => p.id));
    return const <Pack>[];
  }

  final snoozeUntil = await repo.snoozeUntil();
  if (snoozeUntil != null && DateTime.now().isBefore(snoozeUntil)) {
    return const <Pack>[];
  }

  final seen = await repo.seenPackIds();
  return PackNotificationDetector.newPacks(
    catalog: catalog,
    ownedIds: owned,
    seenIds: seen,
  );
});

/// Ids des packs **possédés** pour lesquels une mise à jour de contenu OTA est
/// disponible. Réseau borné (une requête `whereIn` sur les packs possédés) —
/// résolu à l'ouverture de « Mes packs », jamais au boot.
final packUpdatesProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final owned = ref.watch(ownedPacksProvider).toList(growable: false);
  if (owned.isEmpty) return const <String>[];

  final remote = ref.watch(remoteDevinettePackDatasourceProvider);
  final cache = ref.watch(localDevinetteCacheDatasourceProvider);

  final manifests = await remote.fetchManifests(owned);
  final updatable = <String>[];
  for (final manifest in manifests) {
    final local = await cache.packState(manifest.packId);
    if (PackNotificationRepository.needsUpdate(manifest, local)) {
      updatable.add(manifest.packId);
    }
  }
  return updatable;
});
