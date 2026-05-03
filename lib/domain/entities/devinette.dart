import 'package:equatable/equatable.dart';

/// Une devinette culturelle ivoirienne (cf. devinette-curator.md pour le format JSON).
///
/// Contient le mot réponse, la liste de lettres à afficher dans la grille,
/// la devinette textuelle, l'explication et le proverbe associé.
class Devinette extends Equatable {
  const Devinette({
    required this.id,
    required this.world,
    required this.country,
    required this.answer,
    required this.lettersPool,
    required this.riddle,
    required this.explanation,
    required this.proverb,
    required this.difficulty,
    required this.estimatedTimeS,
    required this.tags,
    this.imageSvg,
  });

  factory Devinette.fromJson(Map<String, dynamic> json) {
    return Devinette(
      id: json['id'] as String,
      world: json['world'] as String,
      country: json['country'] as String,
      answer: (json['answer'] as String).toUpperCase(),
      lettersPool: List<String>.from(
        (json['letters_pool'] as List<dynamic>).map((e) => e.toString()),
      ),
      riddle: json['riddle'] as String,
      explanation: json['explanation'] as String,
      proverb: json['proverb'] as String,
      imageSvg: json['image_svg'] as String?,
      difficulty: json['difficulty'] as int,
      estimatedTimeS: json['estimated_time_s'] as int,
      tags: List<String>.from(
        (json['tags'] as List<dynamic>).map((e) => e.toString()),
      ),
    );
  }

  final String id;
  final String world;
  final String country;

  /// Mot réponse en majuscules (ex. 'FOUTOU').
  final String answer;

  /// Lettres à disposer dans la grille — reflète exactement les lettres du mot,
  /// avec doublons (ex. FOUTOU = 2xO, 2xU).
  final List<String> lettersPool;

  final String riddle;
  final String explanation;
  final String proverb;
  final String? imageSvg;
  final int difficulty;
  final int estimatedTimeS;
  final List<String> tags;

  @override
  List<Object?> get props => [
        id,
        world,
        country,
        answer,
        lettersPool,
        riddle,
        explanation,
        proverb,
        imageSvg,
        difficulty,
        estimatedTimeS,
        tags,
      ];
}
