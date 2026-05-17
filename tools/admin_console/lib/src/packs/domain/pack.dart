// Data class — chaque champ est documenté inline (camelCase mirror du nom
// Firestore correspondant). On ne duplique pas en doc-comment.
// ignore_for_file: public_member_api_docs

import 'package:cloud_firestore/cloud_firestore.dart';

/// Métadonnées d'un pack — doc `content_packs/{packId}`.
///
/// Champs gérés UI / UX (modifiables par admin) :
///   - id (immuable après création), name, description
///   - free_choice_eligible, price_eur, price_cauris
///   - enabled (publish flag)
///
/// Champs maintenus par la Cloud Function `publishPack` (read-only UI) :
///   - current_version, format_version, hash_sha256, size_bytes, count,
///     storage_path, download_url, last_published_at
class Pack {
  const Pack({
    required this.id,
    required this.name,
    required this.description,
    required this.country,
    required this.enabled,
    required this.freeChoiceEligible,
    required this.priceEur,
    required this.priceCauris,
    required this.currentVersion,
    required this.count,
    required this.hashSha256,
    required this.sizeBytes,
    required this.storagePath,
    required this.downloadUrl,
    required this.lastPublishedAt,
  });

  factory Pack.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return Pack(
      id: doc.id,
      name: (d['name'] ?? doc.id) as String,
      description: (d['description'] ?? '') as String,
      country: (d['country'] ?? 'ci') as String,
      enabled: (d['enabled'] ?? false) as bool,
      freeChoiceEligible: (d['free_choice_eligible'] ?? false) as bool,
      priceEur: (d['price_eur'] as num?)?.toDouble() ?? 0,
      priceCauris: (d['price_cauris'] as num?)?.toInt() ?? 0,
      currentVersion: (d['current_version'] as num?)?.toInt() ?? 0,
      count: (d['count'] as num?)?.toInt() ?? 0,
      hashSha256: (d['hash_sha256'] ?? '') as String,
      sizeBytes: (d['size_bytes'] as num?)?.toInt() ?? 0,
      storagePath: (d['storage_path'] ?? '') as String,
      downloadUrl: (d['download_url'] ?? '') as String,
      lastPublishedAt: (d['last_published_at'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String name;
  final String description;
  final String country;
  final bool enabled;
  final bool freeChoiceEligible;
  final double priceEur;
  final int priceCauris;
  final int currentVersion;
  final int count;
  final String hashSha256;
  final int sizeBytes;
  final String storagePath;
  final String downloadUrl;
  final DateTime? lastPublishedAt;

  /// Map des champs éditables UI uniquement (jamais les champs maintenus par
  /// la Cloud Function `publishPack`).
  Map<String, dynamic> toEditableMap() => {
        'name': name,
        'description': description,
        'country': country,
        'enabled': enabled,
        'free_choice_eligible': freeChoiceEligible,
        'price_eur': priceEur,
        'price_cauris': priceCauris,
      };

  Pack copyWith({
    String? name,
    String? description,
    String? country,
    bool? enabled,
    bool? freeChoiceEligible,
    double? priceEur,
    int? priceCauris,
  }) {
    return Pack(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      country: country ?? this.country,
      enabled: enabled ?? this.enabled,
      freeChoiceEligible: freeChoiceEligible ?? this.freeChoiceEligible,
      priceEur: priceEur ?? this.priceEur,
      priceCauris: priceCauris ?? this.priceCauris,
      currentVersion: currentVersion,
      count: count,
      hashSha256: hashSha256,
      sizeBytes: sizeBytes,
      storagePath: storagePath,
      downloadUrl: downloadUrl,
      lastPublishedAt: lastPublishedAt,
    );
  }
}
