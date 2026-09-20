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
    this.levelIndex,
    this.isDailyChallenge = false,
    this.dailyDate,
    this.extraDevinettes = const <Devinette>[],
    this.isExposed = false,
  });

  /// Constructeur de commodité pour les call-sites qui n'ont pas encore
  /// migré : applique la config fallback. À supprimer une fois toute la
  /// codebase migrée.
  GameArgs.legacy({
    required this.devinette,
    this.mountainId,
    this.levelIndex,
  })  : config = LevelDifficultyConfig.fallback,
        isDailyChallenge = false,
        dailyDate = null,
        extraDevinettes = const <Devinette>[],
        isExposed = false;

  /// Factory pour le **mode défi du jour**. Bypass les flows
  /// `recordWin`/`recordFailure` standard et redirige vers
  /// `recordDailyChallengeResult` (cf. GameController et GameView).
  ///
  /// `mountainId` reste null par construction — un daily n'appartient à
  /// aucune montagne, donc le compteur de niveaux et les étoiles ne sont
  /// pas affectés.
  GameArgs.daily({
    required this.devinette,
    required this.config,
    required DateTime date,
  })  : mountainId = null,
        levelIndex = null,
        isDailyChallenge = true,
        dailyDate = date,
        extraDevinettes = const <Devinette>[],
        isExposed = false;

  final Devinette devinette;

  /// Devinettes supplémentaires du niveau, selon `config.kind` : deux mots
  /// de plus pour une rafale, un second mot pour un duo, vide sinon. Tirées
  /// par `LevelDevinetteDrawer` au lancement, ids distincts de [devinette].
  final List<Devinette> extraDevinettes;

  /// Vrai quand le joueur a choisi la « voie exposée » à l'embranchement
  /// du niveau 3 (config déjà durcie par `LevelDifficultyResolver
  /// .exposedVariant`). Purement informatif (analytics) — non persisté.
  final bool isExposed;

  /// Toutes les devinettes du niveau, principale en tête.
  List<Devinette> get allDevinettes => <Devinette>[
        devinette,
        ...extraDevinettes,
      ];

  final String? mountainId;

  /// Index 1-based du niveau dans la montagne. Utilisé pour persister
  /// le score étoile par niveau (`PlayerProgress.starsByLevel`). Null en
  /// mode Hub (jeu sans contexte géographique) et en mode daily.
  final int? levelIndex;

  final LevelDifficultyConfig config;

  /// True quand ce game est lancé comme défi du jour. Le controller et
  /// la view utilisent ce flag pour court-circuiter les flows
  /// `recordWin`/`recordFailure` standard et appeler
  /// `recordDailyChallengeResult` à la place.
  final bool isDailyChallenge;

  /// Date calendaire du défi (utilisée par `recordDailyChallengeResult`
  /// pour comparer au `lastDailyChallengeDate` persisté). Null hors mode
  /// daily.
  final DateTime? dailyDate;
}
