import 'package:equatable/equatable.dart';

/// Proverbe ivoirien pour la Sagesse du jour du Hub d'Accueil.
class Proverb extends Equatable {
  const Proverb({
    required this.id,
    required this.text,
    required this.ethnie,
    required this.region,
  });

  factory Proverb.fromJson(Map<String, dynamic> json) => Proverb(
        id: json['id'] as String,
        text: json['text'] as String,
        ethnie: json['ethnie'] as String,
        region: json['region'] as String,
      );

  final String id;
  final String text;
  final String ethnie;
  final String region;

  @override
  List<Object?> get props => [id, text, ethnie, region];
}
