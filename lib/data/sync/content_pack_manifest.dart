/// Représentation Dart d'un manifest pack tel que stocké dans Firestore
/// (`content_packs/{packId}` ou `content_packs/{packId}_community`).
///
/// Voir `firestore.rules` et le script `tool/seed_content_packs.dart` pour
/// le schéma serveur authoritatif.
class ContentPackManifest {
  const ContentPackManifest({
    required this.packId,
    required this.pack,
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
    this.imageUrl,
  });

  factory ContentPackManifest.fromFirestore({
    required String docId,
    required Map<String, dynamic> data,
  }) {
    return ContentPackManifest(
      packId: docId,
      pack: data['pack'] as String,
      currentVersion: (data['current_version'] as num).toInt(),
      formatVersion: (data['format_version'] as num?)?.toInt() ?? 3,
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
      imageUrl: data['image_url'] as String?,
    );
  }

  /// Identifiant du document Firestore (e.g. `culture_ci` ou
  /// `culture_ci_community`).
  final String packId;

  /// Identifiant logique du pack thématique (`culture_ci`, `crack_nouchi`, ...).
  /// Remplace le champ `world` v2.
  final String pack;
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

  /// URL CDN de l'illustration carrée 512×512 du pack (WebP). `null` si
  /// aucune image n'a encore été uploadée via le backoffice — l'app
  /// utilise alors l'asset bundlé `assets/images/packs/{packId}.png` en
  /// fallback (cf. `_PackIcon` dans `pack_chooser_view.dart`).
  /// L'URL inclut un query-param `?v={timestamp}` pour le cache busting.
  final String? imageUrl;
}
