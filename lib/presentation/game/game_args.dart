import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';

/// Argument de navigation pour `/game`.
///
/// `mountainId` est null quand le jeu est lancé depuis le Hub des mondes
/// thématiques (sans contexte géographique).
///
/// [config] porte tous les leviers de difficulté résolus pour ce niveau
/// (timer adaptatif, multiplicateur de récompense, modifiers comme
/// `reverse`/`thinAir`, etc.). Cf. `LevelDifficultyResolver.resolve`.
/// Quand le launcher n'a pas de contexte montagne, on utilise
/// `LevelDifficultyConfig.fallback` (30 s, tier 1, multiplier 1.0).
class GameArgs {
  const GameArgs({
    required this.devinette,
    required this.config,
    this.mountainId,
  });

  /// Constructeur de commodité pour les call-sites qui n'ont pas encore
  /// migré : applique la config fallback. À supprimer une fois toute la
  /// codebase migrée (S2+).
  GameArgs.legacy({
    required this.devinette,
    this.mountainId,
  }) : config = LevelDifficultyConfig.fallback;

  final Devinette devinette;
  final String? mountainId;
  final LevelDifficultyConfig config;
}
