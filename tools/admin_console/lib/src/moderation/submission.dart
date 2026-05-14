import 'package:cloud_firestore/cloud_firestore.dart';

class Submission {
  const Submission({
    required this.id,
    required this.authorUid,
    required this.locale,
    required this.country,
    required this.question,
    required this.answer,
    required this.tags,
    required this.difficulty,
    required this.status,
    required this.score,
    required this.createdAt,
    this.proverb,
    this.curatedBy,
  });

  factory Submission.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return Submission(
      id: doc.id,
      authorUid: (d['authorUid'] ?? '') as String,
      locale: (d['locale'] ?? 'fr-CI') as String,
      country: (d['country'] ?? 'CI') as String,
      question: (d['question'] ?? '') as String,
      answer: (d['answer'] ?? '') as String,
      tags: List<String>.from((d['tags'] as List?) ?? const []),
      difficulty: (d['difficulty'] as num? ?? 3).toInt(),
      status: (d['status'] ?? 'pending') as String,
      score: (d['score'] as num? ?? 0).toInt(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      proverb: d['proverb'] as String?,
      curatedBy: d['curatedBy'] as String?,
    );
  }

  final String id;
  final String authorUid;
  final String locale;
  final String country;
  final String question;
  final String answer;
  final String? proverb;
  final List<String> tags;
  final int difficulty;
  final String status;
  final int score;
  final DateTime? createdAt;
  final String? curatedBy;
}
