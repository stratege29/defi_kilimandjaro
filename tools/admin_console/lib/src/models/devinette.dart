import 'package:cloud_firestore/cloud_firestore.dart';

/// Statut backoffice d'une devinette.
///
/// Cycle : draft → published → archived → deleted (soft).
/// Cf docs/backoffice_schema.md §4.
enum DevinetteStatus {
  draft,
  published,
  archived,
  deleted;

  static DevinetteStatus parse(Object? raw) {
    return switch (raw) {
      'draft' => DevinetteStatus.draft,
      'published' => DevinetteStatus.published,
      'archived' => DevinetteStatus.archived,
      'deleted' => DevinetteStatus.deleted,
      _ => DevinetteStatus.draft,
    };
  }
}

/// Modèle complet d'une devinette (format v3 + champs de cycle de vie
/// backoffice). Lu depuis `packs/{packId}/devinettes/{deviId}`.
class Devinette {
  const Devinette({
    required this.id,
    required this.pack,
    required this.country,
    required this.answer,
    required this.answerNormalized,
    required this.lettersPool,
    required this.riddle,
    required this.explanation,
    required this.difficulty,
    required this.estimatedTimeS,
    required this.tags,
    required this.status,
    required this.publishedVersion,
    required this.draftVersion,
    required this.deletedAt,
    required this.updatedAt,
    required this.updatedBy,
  });

  final String id;
  final String pack;
  final String country;
  final String answer;
  final String answerNormalized;
  final List<String> lettersPool;
  final Map<String, String> riddle;
  final Map<String, String> explanation;
  final int difficulty;
  final int estimatedTimeS;
  final List<String> tags;
  final DevinetteStatus status;
  final int? publishedVersion;
  final int? draftVersion;
  final DateTime? deletedAt;
  final DateTime? updatedAt;
  final String? updatedBy;

  /// Vrai si elle apparaîtra dans le prochain publish (draft ou published
  /// sans deleted_at).
  bool get isPublishable =>
      (status == DevinetteStatus.draft || status == DevinetteStatus.published) &&
      deletedAt == null;

  factory Devinette.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    return Devinette(
      id: data['id'] as String? ?? doc.id,
      pack: data['pack'] as String? ?? '',
      country: data['country'] as String? ?? 'ci',
      answer: data['answer'] as String? ?? '',
      answerNormalized: data['answer_normalized'] as String? ?? '',
      lettersPool: (data['letters_pool'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      riddle: _parseI18nMap(data['riddle']),
      explanation: _parseI18nMap(data['explanation']),
      difficulty: (data['difficulty'] as num?)?.toInt() ?? 1,
      estimatedTimeS: (data['estimated_time_s'] as num?)?.toInt() ?? 30,
      tags: (data['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      status: DevinetteStatus.parse(data['status']),
      publishedVersion: (data['published_version'] as num?)?.toInt(),
      draftVersion: (data['draft_version'] as num?)?.toInt(),
      deletedAt: (data['deleted_at'] as Timestamp?)?.toDate(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate(),
      updatedBy: data['updated_by'] as String?,
    );
  }

  static Map<String, String> _parseI18nMap(dynamic raw) {
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
  }

  /// Sérialisation vers JSON pour `upsertDevinette` CF (sans champs de cycle
  /// de vie — ils sont gérés serveur).
  Map<String, dynamic> toUpsertPayload() {
    return {
      'id': id,
      'pack': pack,
      'country': country,
      'answer': answer,
      'riddle': riddle,
      'explanation': explanation,
      'difficulty': difficulty,
      'estimated_time_s': estimatedTimeS,
      'tags': tags,
    };
  }
}
