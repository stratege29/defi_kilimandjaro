/// Représentation Dart d'un manifest pack tel que stocké dans Firestore
/// (`content_packs/{worldId}` ou `content_packs/{worldId}_community`).
///
/// Voir `firestore.rules` et le script `tool/seed_content_packs.dart` pour
/// le schéma serveur authoritatif.
class ContentPackManifest {
  const ContentPackManifest({
    required this.packId,
    required this.world,
    required this.currentVersion,
    required this.formatVersion,
    required this.hashSha256,
    required this.sizeBytes,
    required this.count,
    required this.storagePath,
    required this.downloadUrl,
    required this.minAppVersion,
    required this.langs,
    required this.defaultLang,
    required this.enabled,
    required this.isCommunity,
  });

  factory ContentPackManifest.fromFirestore({
    required String docId,
    required Map<String, dynamic> data,
  }) {
    return ContentPackManifest(
      packId: docId,
      world: data['world'] as String,
      currentVersion: (data['current_version'] as num).toInt(),
      formatVersion: (data['format_version'] as num?)?.toInt() ?? 2,
      hashSha256: data['hash_sha256'] as String,
      sizeBytes: (data['size_bytes'] as num?)?.toInt() ?? 0,
      count: (data['count'] as num?)?.toInt() ?? 0,
      storagePath: data['storage_path'] as String,
      downloadUrl: data['download_url'] as String,
      minAppVersion: data['min_app_version'] as String? ?? '0.0.0',
      langs: (data['langs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const <String>['fr'],
      defaultLang: data['default_lang'] as String? ?? 'fr',
      enabled: data['enabled'] as bool? ?? true,
      isCommunity: docId.endsWith('_community'),
    );
  }

  /// Identifiant du document Firestore (e.g. `village_des_or` ou
  /// `village_des_or_community`).
  final String packId;
  final String world;
  final int currentVersion;
  final int formatVersion;
  final String hashSha256;
  final int sizeBytes;
  final int count;
  final String storagePath;
  final String downloadUrl;
  final String minAppVersion;
  final List<String> langs;
  final String defaultLang;
  final bool enabled;

  /// `true` si le doc concerne le pack communautaire (UGC reconstruit). Sert
  /// à choisir la `DevinetteSource` à l'insertion en cache.
  final bool isCommunity;
}
