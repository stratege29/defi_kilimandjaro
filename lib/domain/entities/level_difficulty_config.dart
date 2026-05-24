import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:equatable/equatable.dart';

/// Configuration de difficulté résolue pour un niveau précis.
///
/// Value object porté par `GameArgs` et calculé par `LevelDifficultyResolver`
/// à partir de la montagne et de l'index du niveau. Remplace le `int
/// targetDifficulty` historique en regroupant tous les leviers de
/// difficulté en un seul contrat.
///
/// Champs :
/// - [difficultyTier] : palier global 1–5 (anciennement `difficultyForAltitude`).
///   Sert au matching primaire d'une devinette dans le pool.
/// - [wordLengthBucket] : bucket de longueur de mot préféré (1–5).
///   Bucket 1 ≈ 3–4 lettres, 5 ≈ 9+ lettres. Filtrage secondaire dans
///   le service de sélection avec fallback progressif.
/// - [timerSeconds] : durée de la partie en secondes (déjà adaptée à la
///   longueur du mot et au tier).
/// - [caurisMultiplier] : multiplicateur appliqué à la récompense finale
///   pour valoriser les niveaux difficiles.
/// - [distractorCount] : nombre de lettres parasites à ajouter au pool
///   affiché (déclaré ici mais non encore appliqué — S2).
/// - [modifiers] : modificateurs gameplay actifs (cf. `LevelModifier`).
/// - [isBoss] : niveau final d'une montagne (préparation S4).
class LevelDifficultyConfig extends Equatable {
  const LevelDifficultyConfig({
    required this.difficultyTier,
    required this.wordLengthBucket,
    required this.timerSeconds,
    required this.caurisMultiplier,
    this.distractorCount = 0,
    this.modifiers = const <LevelModifier>{},
    this.isBoss = false,
  })  : assert(
          difficultyTier >= 1 && difficultyTier <= 5,
          'difficultyTier must be in 1..5',
        ),
        assert(
          wordLengthBucket >= 1 && wordLengthBucket <= 5,
          'wordLengthBucket must be in 1..5',
        ),
        assert(timerSeconds > 0, 'timerSeconds must be positive'),
        assert(
          caurisMultiplier > 0,
          'caurisMultiplier must be positive',
        ),
        assert(distractorCount >= 0, 'distractorCount must be non-negative');

  /// Config par défaut pour les call-sites legacy qui n'ont pas encore
  /// migré (Hub mode sans montagne, lancement debug, etc.). Reproduit
  /// l'ancien comportement : 30 s de timer, tier 1, multiplier 1.0.
  static const LevelDifficultyConfig fallback = LevelDifficultyConfig(
    difficultyTier: 1,
    wordLengthBucket: 1,
    timerSeconds: 30,
    caurisMultiplier: 1,
  );

  final int difficultyTier;
  final int wordLengthBucket;
  final int timerSeconds;
  final double caurisMultiplier;
  final int distractorCount;
  final Set<LevelModifier> modifiers;
  final bool isBoss;

  /// Raccourci : vrai si le modifier `reverse` est actif.
  /// Utilisé par `GameController.validate` pour comparer le mot formé à
  /// la version inversée de la réponse.
  bool get hasReverse => modifiers.contains(LevelModifier.reverse);

  /// Raccourci : vrai si le modifier `thinAir` est actif (timer ×0.8).
  bool get hasThinAir => modifiers.contains(LevelModifier.thinAir);

  LevelDifficultyConfig copyWith({
    int? difficultyTier,
    int? wordLengthBucket,
    int? timerSeconds,
    double? caurisMultiplier,
    int? distractorCount,
    Set<LevelModifier>? modifiers,
    bool? isBoss,
  }) {
    return LevelDifficultyConfig(
      difficultyTier: difficultyTier ?? this.difficultyTier,
      wordLengthBucket: wordLengthBucket ?? this.wordLengthBucket,
      timerSeconds: timerSeconds ?? this.timerSeconds,
      caurisMultiplier: caurisMultiplier ?? this.caurisMultiplier,
      distractorCount: distractorCount ?? this.distractorCount,
      modifiers: modifiers ?? this.modifiers,
      isBoss: isBoss ?? this.isBoss,
    );
  }

  @override
  List<Object?> get props => [
        difficultyTier,
        wordLengthBucket,
        timerSeconds,
        caurisMultiplier,
        distractorCount,
        modifiers,
        isBoss,
      ];
}
