import 'package:cloud_firestore/cloud_firestore.dart';

/// Statut d'une version d'un pack.
enum PackVersionStatus {
  active,
  archived,
  draft;

  static PackVersionStatus parse(Object? raw) {
    return switch (raw) {
      'active' => PackVersionStatus.active,
      'archived' => PackVersionStatus.archived,
      'draft' => PackVersionStatus.draft,
      _ => PackVersionStatus.archived,
    };
  }
}

/// Une version publiée d'un pack. Lu depuis `packs/{packId}/versions/{N}`.
///
/// Snapshot immuable du manifest au moment du publish. Permet rollback.
class PackVersion {
  const PackVersion({
    required this.number,
    required this.hashSha256,
    required this.sizeBytes,
    required this.count,
    required this.storagePath,
    required this.downloadUrl,
    required this.langs,
    required this.status,
    required this.publishedAt,
    required this.publishedBy,
    required this.previousVersion,
    required this.archivedAt,
    required this.restoredAt,
  });

  final int number;
  final String? hashSha256;
  final int? sizeBytes;
  final int? count;
  final String? storagePath;
  final String? downloadUrl;
  final List<String> langs;
  final PackVersionStatus status;
  final DateTime? publishedAt;
  final String? publishedBy;
  final int? previousVersion;
  final DateTime? archivedAt;
  final DateTime? restoredAt;

  factory PackVersion.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    return PackVersion(
      number: (data['number'] as num?)?.toInt() ??
          int.tryParse(doc.id) ??
          0,
      hashSha256: data['hash_sha256'] as String?,
      sizeBytes: (data['size_bytes'] as num?)?.toInt(),
      count: (data['count'] as num?)?.toInt(),
      storagePath: data['storage_path'] as String?,
      downloadUrl: data['download_url'] as String?,
      langs: (data['langs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['fr'],
      status: PackVersionStatus.parse(data['status']),
      publishedAt: (data['published_at'] as Timestamp?)?.toDate(),
      publishedBy: data['published_by'] as String?,
      previousVersion: (data['previous_version'] as num?)?.toInt(),
      archivedAt: (data['archived_at'] as Timestamp?)?.toDate(),
      restoredAt: (data['restored_at'] as Timestamp?)?.toDate(),
    );
  }
}
