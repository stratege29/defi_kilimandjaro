import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Snapshot complet du catalogue distant à un instant T.
///
/// Lu depuis `catalog/index` Firestore (Phase 3 backoffice). Contient
/// `catalog_version` (compteur incrémenté à chaque publish) pour permettre
/// invalidation client efficace.
class RemoteCatalogSnapshot {
  const RemoteCatalogSnapshot({
    required this.schemaVersion,
    required this.catalogVersion,
    required this.packs,
    required this.fetchedAt,
  });

  /// Version du schéma `catalog/index` (4 actuellement, cf doc backoffice).
  /// Permet de gérer une migration future sans casser les vieux clients.
  final int schemaVersion;

  /// Version du catalogue (incrémentée à chaque publishPack/rollbackPack
  /// côté CFs). Sert de cache-bust et de signal de fraîcheur.
  final int catalogVersion;

  /// Packs publiés, triés par `ordering` croissant. Inclut les `visible:false`
  /// (le composite filtrera selon le besoin).
  final List<Pack> packs;

  /// Timestamp local du dernier fetch réussi (pour UI "Synchronisé il y a X").
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'catalog_version': catalogVersion,
    'fetched_at': fetchedAt.toIso8601String(),
    'packs': packs.map((p) => _packToCacheMap(p)).toList(),
  };

  static RemoteCatalogSnapshot? fromCachedJson(Map<String, dynamic> json) {
    try {
      return RemoteCatalogSnapshot(
        schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 0,
        catalogVersion: (json['catalog_version'] as num?)?.toInt() ?? 0,
        fetchedAt: DateTime.parse(json['fetched_at'] as String),
        packs: (json['packs'] as List<dynamic>)
            .map(
              (p) => Pack.fromCatalogEntry(Map<String, dynamic>.from(p as Map)),
            )
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _packToCacheMap(Pack p) => {
    'id': p.id,
    'visible': p.visible,
    'ordering': p.ordering,
    'count': p.questionCount,
    'free_choice_eligible': p.freeChoiceEligible,
    'unlock_cost_cauris': p.unlockCostCauris ?? p.priceCauris,
    'theme_color_hex': p.themeColorHex,
    'theme_id': p.themeId,
    'theme_overrides': p.themeOverrides,
    'theme_motif': p.themeMotif,
    'theme_tile_shape': p.themeTileShape,
    'icon_url': p.iconUrl,
    'min_app_version': p.minAppVersion,
    'available_from': p.availableFrom?.toIso8601String(),
    'available_until': p.availableUntil?.toIso8601String(),
  };
}

/// Source de vérité Firestore pour le catalogue distant.
///
/// **Contraintes OTA v0.2** (cf `docs/ota_v2_design.md`) :
///   - **Pas de fetch au boot** (jetsam OOM iOS 26)
///   - Fetch déclenché manuellement (bouton SYNC dans Settings/MyPacks)
///     ou différé post-onboarding
///   - Cache disque (SharedPreferences) pour persistance entre sessions
///
/// Cette classe est un **datasource pur** : pas de logique de merge avec
/// le bundle (faite par `CompositeCatalogRepository`). Pas de provider
/// Riverpod ici (couche data uniquement).
class RemoteCatalogDatasource {
  RemoteCatalogDatasource({
    FirebaseFirestore? firestore,
    Future<SharedPreferences> Function()? prefsFactory,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  final FirebaseFirestore _firestore;
  final Future<SharedPreferences> Function() _prefsFactory;

  static const String _cacheKey = 'remote_catalog_snapshot_v1';

  /// Fetch le doc `catalog/index` depuis Firestore.
  ///
  /// Lance `Source.server` pour bypasser le cache Firestore SDK (on a notre
  /// propre cache disque). Retourne null si le doc n'existe pas (ne throw pas
  /// pour permettre fallback bundle silencieux).
  ///
  /// Throw [FirebaseException] si erreur réseau / permission — à catch par
  /// l'appelant pour decider de l'UX (snackbar erreur ou fallback silencieux).
  Future<RemoteCatalogSnapshot?> fetch() async {
    final snap = await _firestore
        .collection('catalog')
        .doc('index')
        .get(const GetOptions(source: Source.server));
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    final packsRaw = data['packs'] as List<dynamic>?;
    if (packsRaw == null) return null;

    final packs =
        packsRaw
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => Pack.fromCatalogEntry(Map<String, dynamic>.from(m)))
            .toList()
          ..sort((a, b) => a.ordering.compareTo(b.ordering));

    final result = RemoteCatalogSnapshot(
      schemaVersion: (data['schema_version'] as num?)?.toInt() ?? 4,
      catalogVersion: (data['catalog_version'] as num?)?.toInt() ?? 0,
      packs: packs,
      fetchedAt: DateTime.now().toUtc(),
    );

    // Persiste en cache disque pour la prochaine session
    await _saveCache(result);
    return result;
  }

  /// Stream live du `catalog/index` (alternative à `fetch()` quand on veut
  /// observer les changements en temps réel). Pas utilisé au boot, mais utile
  /// pour la page MyPacks ouverte longtemps si un admin publie une nouvelle
  /// version pendant la session.
  Stream<RemoteCatalogSnapshot?> watch() {
    return _firestore.collection('catalog').doc('index').snapshots().map((
      snap,
    ) {
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null) return null;
      final packsRaw = data['packs'] as List<dynamic>?;
      if (packsRaw == null) return null;
      final packs =
          packsRaw
              .whereType<Map<dynamic, dynamic>>()
              .map((m) => Pack.fromCatalogEntry(Map<String, dynamic>.from(m)))
              .toList()
            ..sort((a, b) => a.ordering.compareTo(b.ordering));
      final snapshot = RemoteCatalogSnapshot(
        schemaVersion: (data['schema_version'] as num?)?.toInt() ?? 4,
        catalogVersion: (data['catalog_version'] as num?)?.toInt() ?? 0,
        packs: packs,
        fetchedAt: DateTime.now().toUtc(),
      );
      // Sauve en cache au passage
      unawaited(_saveCache(snapshot));
      return snapshot;
    });
  }

  /// Lit le snapshot persisté sur disque. Retourne null si pas de cache
  /// (premier lancement) ou cache corrompu.
  Future<RemoteCatalogSnapshot?> loadCache() async {
    final prefs = await _prefsFactory();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return RemoteCatalogSnapshot.fromCachedJson(decoded);
    } catch (_) {
      // Cache corrompu — on l'efface pour éviter retry boucle
      await prefs.remove(_cacheKey);
      return null;
    }
  }

  Future<void> _saveCache(RemoteCatalogSnapshot snapshot) async {
    try {
      final prefs = await _prefsFactory();
      await prefs.setString(_cacheKey, jsonEncode(snapshot.toJson()));
    } catch (_) {
      // Best effort — si SharedPreferences fail, on continue sans cache
    }
  }

  /// Efface le cache. Utile pour test ou bouton "Reset catalog" debug.
  Future<void> clearCache() async {
    final prefs = await _prefsFactory();
    await prefs.remove(_cacheKey);
  }
}
