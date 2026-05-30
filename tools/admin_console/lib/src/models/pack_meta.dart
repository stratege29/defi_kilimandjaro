import 'package:cloud_firestore/cloud_firestore.dart';

/// Métadonnées d'un pack (lu depuis `packs/{packId}/meta/doc`).
class PackMeta {
  const PackMeta({
    required this.id,
    required this.bundled,
    required this.latestPublishedVersion,
    required this.nextDraftVersion,
    required this.pendingChanges,
    required this.updatedAt,
    required this.updatedBy,
  });

  final String id;
  final bool bundled;
  final int latestPublishedVersion;
  final int nextDraftVersion;
  final int pendingChanges;
  final DateTime? updatedAt;
  final String? updatedBy;

  factory PackMeta.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    return PackMeta(
      id: data['id'] as String? ?? '',
      bundled: data['bundled'] as bool? ?? false,
      latestPublishedVersion:
          (data['latest_published_version'] as num?)?.toInt() ?? 0,
      nextDraftVersion: (data['next_draft_version'] as num?)?.toInt() ?? 1,
      pendingChanges: (data['pending_changes'] as num?)?.toInt() ?? 0,
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate(),
      updatedBy: data['updated_by'] as String?,
    );
  }
}

/// Internationalisation d'un pack (lu depuis `packs/{packId}/i18n/{lang}`).
class PackI18n {
  const PackI18n({
    required this.lang,
    required this.name,
    required this.description,
    required this.shortTagline,
  });

  final String lang;
  final String name;
  final String description;
  final String shortTagline;

  factory PackI18n.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    return PackI18n(
      lang: data['lang'] as String? ?? doc.id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      shortTagline: data['short_tagline'] as String? ?? '',
    );
  }
}
