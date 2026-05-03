import 'package:equatable/equatable.dart';

/// Un monde thématique du Hub (cf. maquette p.4).
///
/// Chaque monde regroupe des devinettes culturelles d'un même registre :
/// Village des Or (cuisine, vie quotidienne), Forêt Sacrée (masques, animaux),
/// Lagune des Saveurs (Abidjan, marchés), Monts des Légendes (héros, sagesse).
class World extends Equatable {
  const World({
    required this.id,
    required this.name,
    required this.emoji,
    required this.unlocked,
    required this.completedLevels,
    required this.totalLevels,
    this.unlockCost = 0,
  });

  final String id;
  final String name;
  final String emoji;
  final bool unlocked;
  final int completedLevels;
  final int totalLevels;

  /// Coût en Coins de Sagesse pour déverrouiller ce monde.
  /// 0 si le monde est gratuit (premier monde) ou déjà déverrouillé.
  final int unlockCost;

  double get progress =>
      totalLevels == 0 ? 0 : completedLevels / totalLevels;

  @override
  List<Object?> get props => [
        id,
        name,
        emoji,
        unlocked,
        completedLevels,
        totalLevels,
        unlockCost,
      ];
}
