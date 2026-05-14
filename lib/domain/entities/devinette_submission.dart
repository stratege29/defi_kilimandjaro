import 'package:equatable/equatable.dart';

/// Statut d'une soumission UGC dans le pipeline de modération.
enum SubmissionStatus {
  /// En attente d'évaluation par le curateur (auto + humain).
  pending,

  /// Auto-approuvée par le curateur LLM (score ≥ 80) — toujours visible
  /// dans la file de modération humaine pour les 30 premiers jours.
  preApproved,

  /// Approuvée et publiée dans le pack communautaire.
  approved,

  /// Rejetée par le curateur ou un modérateur.
  rejected,

  /// Auto-flaggée après reports utilisateurs.
  flagged;

  static SubmissionStatus fromWireName(String? raw) {
    return switch (raw) {
      'pending' => SubmissionStatus.pending,
      'pre_approved' => SubmissionStatus.preApproved,
      'approved' => SubmissionStatus.approved,
      'rejected' => SubmissionStatus.rejected,
      'flagged' => SubmissionStatus.flagged,
      _ => SubmissionStatus.pending,
    };
  }
}

/// Une soumission de devinette par un utilisateur.
///
/// Les `riddle`/`explanation`/`proverb` sont mono-langue à la soumission
/// (l'utilisateur choisit explicitement la langue via [lang]). Les autres
/// langues sont ajoutées par les modérateurs au moment de l'approbation.
class DevinetteSubmission extends Equatable {
  const DevinetteSubmission({
    required this.id,
    required this.authorUid,
    required this.status,
    required this.lang,
    required this.world,
    required this.country,
    required this.answer,
    required this.answerNormalized,
    required this.lettersPool,
    required this.riddle,
    required this.explanation,
    required this.proverb,
    required this.difficulty,
    required this.tags,
    required this.createdAt,
    this.authorDisplayName,
    this.rejectionReason,
    this.reviewedAt,
    this.reviewedBy,
  });

  factory DevinetteSubmission.fromJson(Map<String, dynamic> json) {
    DateTime? readDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      // Firestore Timestamp expose `toDate()` via dynamic, mais on évite
      // la dépendance ici (entité = pure domain).
      try {
        // ignore: avoid_dynamic_calls
        final d = (raw as dynamic).toDate();
        if (d is DateTime) return d;
      } on Object {
        // fallthrough
      }
      return null;
    }

    return DevinetteSubmission(
      id: json['id'] as String,
      authorUid: json['authorUid'] as String,
      authorDisplayName: json['authorDisplayName'] as String?,
      status: SubmissionStatus.fromWireName(json['status'] as String?),
      lang: json['lang'] as String,
      world: json['world'] as String,
      country: json['country'] as String,
      answer: json['answer'] as String,
      answerNormalized: json['answerNormalized'] as String,
      lettersPool: List<String>.from(
        (json['lettersPool'] as List<dynamic>).map((e) => e.toString()),
      ),
      riddle: json['riddle'] as String,
      explanation: json['explanation'] as String,
      proverb: json['proverb'] as String,
      difficulty: (json['difficulty'] as num).toInt(),
      tags: List<String>.from(
        (json['tags'] as List<dynamic>).map((e) => e.toString()),
      ),
      createdAt: readDate(json['createdAt']) ?? DateTime.now(),
      reviewedAt: readDate(json['reviewedAt']),
      reviewedBy: json['reviewedBy'] as String?,
      rejectionReason: json['rejectionReason'] as String?,
    );
  }

  final String id;
  final String authorUid;
  final String? authorDisplayName;
  final SubmissionStatus status;
  final String lang;
  final String world;
  final String country;
  final String answer;
  final String answerNormalized;
  final List<String> lettersPool;
  final String riddle;
  final String explanation;
  final String proverb;
  final int difficulty;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectionReason;

  @override
  List<Object?> get props => [
        id,
        authorUid,
        authorDisplayName,
        status,
        lang,
        world,
        country,
        answer,
        answerNormalized,
        lettersPool,
        riddle,
        explanation,
        proverb,
        difficulty,
        tags,
        createdAt,
        reviewedAt,
        reviewedBy,
        rejectionReason,
      ];
}
