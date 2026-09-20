import 'package:defi_kilimandjaro/domain/entities/level_kind.dart';
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
///   Bucket 1 ≈ 3–4 lettres, 5 ≈ 9+ lettres. Égal au tier, +1 sur le boss.
///   Filtrage secondaire dans le service de sélection avec fallback
///   progressif.
/// - [timerSeconds] : durée de la partie en secondes (déjà adaptée au tier,
///   à la position du niveau dans le sommet et à `thinAir`).
/// - [caurisMultiplier] : multiplicateur appliqué à la récompense finale
///   pour valoriser les niveaux difficiles (croît avec le niveau, majoré
///   sur le boss).
/// - [distractorCount] : nombre de lettres parasites ajoutées au pool
///   affiché par `GameController` (croît avec le niveau, plafonné).
/// - [modifiers] : modificateurs gameplay actifs (cf. `LevelModifier`).
/// - [isBoss] : niveau final d'une montagne (préparation S4).
/// - [kind] : structure du tour (cf. [LevelKind]) — classique par défaut.
class LevelDifficultyConfig extends Equatable {
  const LevelDifficultyConfig({
    required this.difficultyTier,
    required this.wordLengthBucket,
    required this.timerSeconds,
    required this.caurisMultiplier,
    this.distractorCount = 0,
    this.modifiers = const <LevelModifier>{},
    this.isBoss = false,
    this.kind = LevelKind.classic,
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
  final LevelKind kind;

  /// Raccourci : vrai si le modifier `reverse` est actif.
  /// Utilisé par `GameController.validate` pour comparer le mot formé à
  /// la version inversée de la réponse.
  bool get hasReverse => modifiers.contains(LevelModifier.reverse);

  /// Raccourci : vrai si le modifier `thinAir` est actif (timer ×0.8).
  bool get hasThinAir => modifiers.contains(LevelModifier.thinAir);

  /// Vrai pour les niveaux où l'écran d'échec révèle gratuitement la
  /// réponse — réservé au tout premier palier (T1, zone d'amorçage). À
  /// partir du Tier 2, la réponse est masquée par défaut : le joueur doit
  /// soit acheter le reveal (50 cauris), soit échouer 3 fois consécutivement
  /// (filet anti-blocage géré côté `GameView`). Ce choix crée un sink
  /// économique pour les cauris et préserve la tension cognitive dès la
  /// sortie du tutoriel.
  bool get revealsAnswerOnFailure => difficultyTier <= 1;

  LevelDifficultyConfig copyWith({
    int? difficultyTier,
    int? wordLengthBucket,
    int? timerSeconds,
    double? caurisMultiplier,
    int? distractorCount,
    Set<LevelModifier>? modifiers,
    bool? isBoss,
    LevelKind? kind,
  }) {
    return LevelDifficultyConfig(
      difficultyTier: difficultyTier ?? this.difficultyTier,
      wordLengthBucket: wordLengthBucket ?? this.wordLengthBucket,
      timerSeconds: timerSeconds ?? this.timerSeconds,
      caurisMultiplier: caurisMultiplier ?? this.caurisMultiplier,
      distractorCount: distractorCount ?? this.distractorCount,
      modifiers: modifiers ?? this.modifiers,
      isBoss: isBoss ?? this.isBoss,
      kind: kind ?? this.kind,
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
        kind,
      ];
}
