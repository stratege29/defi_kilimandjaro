// Data class — chaque champ est nommé en camelCase miroir du champ Firestore
// (snake_case). On évite de dupliquer les docs sur chaque field.
// ignore_for_file: public_member_api_docs

import 'package:cloud_firestore/cloud_firestore.dart';

/// Question d'un pack — doc `content_packs/{packId}/questions/{questionId}`.
/// Format v3 strict — cf. `question_validators.dart` pour les invariants.
class Question {
  const Question({
    required this.id,
    required this.pack,
    required this.country,
    required this.answer,
    required this.answerNormalized,
    required this.lettersPool,
    required this.riddleFr,
    required this.explanationFr,
    required this.difficulty,
    required this.estimatedTimeS,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Question.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final riddle = (d['riddle'] as Map?)?.cast<String, dynamic>() ?? const {};
    final explanation =
        (d['explanation'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Question(
      id: doc.id,
      pack: (d['pack'] ?? '') as String,
      country: (d['country'] ?? 'ci') as String,
      answer: (d['answer'] ?? '') as String,
      answerNormalized: (d['answer_normalized'] ?? '') as String,
      lettersPool: List<String>.from((d['letters_pool'] as List?) ?? const []),
      riddleFr: (riddle['fr'] ?? '') as String,
      explanationFr: (explanation['fr'] ?? '') as String,
      difficulty: (d['difficulty'] as num?)?.toInt() ?? 3,
      estimatedTimeS: (d['estimated_time_s'] as num?)?.toInt() ?? 30,
      tags: List<String>.from((d['tags'] as List?) ?? const []),
      createdAt: (d['created_at'] as Timestamp?)?.toDate(),
      updatedAt: (d['updated_at'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String pack;
  final String country;
  final String answer;
  final String answerNormalized;
  final List<String> lettersPool;
  final String riddleFr;
  final String explanationFr;
  final int difficulty;
  final int estimatedTimeS;
  final List<String> tags;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Produit la map Firestore canonique conforme au format v3.
  /// `created_at` / `updated_at` sont gérés en dehors (serverTimestamp).
  Map<String, dynamic> toFirestoreMap() => {
        'id': id,
        'pack': pack,
        'country': country,
        'answer': answer,
        'answer_normalized': answerNormalized,
        'letters_pool': lettersPool,
        'riddle': {'fr': riddleFr},
        'explanation': {'fr': explanationFr},
        'difficulty': difficulty,
        'estimated_time_s': estimatedTimeS,
        'tags': tags,
        'format_version': 3,
      };

  Question copyWith({
    String? id,
    String? pack,
    String? country,
    String? answer,
    String? answerNormalized,
    List<String>? lettersPool,
    String? riddleFr,
    String? explanationFr,
    int? difficulty,
    int? estimatedTimeS,
    List<String>? tags,
  }) {
    return Question(
      id: id ?? this.id,
      pack: pack ?? this.pack,
      country: country ?? this.country,
      answer: answer ?? this.answer,
      answerNormalized: answerNormalized ?? this.answerNormalized,
      lettersPool: lettersPool ?? this.lettersPool,
      riddleFr: riddleFr ?? this.riddleFr,
      explanationFr: explanationFr ?? this.explanationFr,
      difficulty: difficulty ?? this.difficulty,
      estimatedTimeS: estimatedTimeS ?? this.estimatedTimeS,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
