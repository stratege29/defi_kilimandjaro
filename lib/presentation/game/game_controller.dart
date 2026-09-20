import 'dart:async';
import 'dart:math';

import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/audio/tempo_scheduler.dart';
import 'package:defi_kilimandjaro/data/firebase/analytics_service.dart';
import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/game_economy_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_kind.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/level_star_rating.dart';
import 'package:defi_kilimandjaro/domain/services/daily_challenge_service.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/solo_combo_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Phase du cycle de vie d'une partie.
enum GamePhase { playing, validating, won, lost }

/// Grille prête à jouer : pool effectif, permutation initiale et indices
/// (dans le pool) de la tuile mirage. Cf. `GameController._buildRound`.
typedef _RoundSetup = ({
  List<String> pool,
  List<int> shuffled,
  Set<int> mirage,
});

/// État immutable d'une partie en cours.
class GameState {
  const GameState({
    required this.devinette,
    required this.selectedIndices,
    required this.timeLeft,
    required this.phase,
    required this.cauris,
    required this.shuffledIndices,
    required this.effectivePool,
    this.hintRevealedCount = 0,
    this.revealedPositions = const <int>{},
    this.validationCorrect = false,
    this.reverseAnswer = false,
    this.starsEarned = 0,
    this.fogHiddenIndices = const <int>{},
    this.caurisAwarded = 0,
    this.currentTrailSelfIntersecting = false,
    this.freehandBonusAwarded = 0,
    this.wrongAttempts = 0,
    this.perfectBonusAwarded = 0,
    this.comboStreak = 0,
    this.comboMultiplierApplied = 1.0,
    this.shuffleUsed = false,
    this.mirageIndices = const <int>{},
    this.rainBlurActive = false,
    this.spiritHiddenIndex,
    this.roundIndex = 0,
    this.roundCount = 1,
    this.secondDevinette,
    this.secondRevealedPositions = const <int>{},
    this.solvedWordIndices = const <int>{},
    this.riddleVisible = true,
    this.rereadCount = 0,
    this.rereadTicksLeft = 0,
  });

  /// Devinette **courante** : celle du mot en cours dans une rafale, la
  /// principale (première énigme) dans un duo, l'unique sinon.
  final Devinette devinette;

  /// Indices (dans shuffledIndices) des tuiles sélectionnées dans l'ordre.
  final List<int> selectedIndices;

  final int timeLeft;
  final GamePhase phase;
  final int cauris;

  /// Pool effectif affiché dans la grille : lettres de `devinette.answer`
  /// + N lettres parasites (cf. `LevelDifficultyConfig.distractorCount`).
  /// Reste fixé au début de la partie, identique à `devinette.lettersPool`
  /// quand `distractorCount == 0`.
  final List<String> effectivePool;

  /// Permutation des indices de [effectivePool] (Fisher-Yates au départ).
  final List<int> shuffledIndices;

  /// Nombre de lettres révélées par l'indice. Égal à `revealedPositions.length`
  /// ; conservé comme compteur pour le scaling du coût et le calcul des
  /// étoiles (« sans indice »).
  final int hintRevealedCount;

  /// Positions (dans [expectedAnswer]) révélées par l'indice. Chaque appel à
  /// [GameController.useHint] place une lettre correcte dans une case encore
  /// non révélée tirée au hasard. `AnswerCells` l'affiche en aperçu fantôme
  /// (avec une animation pop + flip) jusqu'à ce que le joueur forme
  /// réellement la lettre dans la roue.
  final Set<int> revealedPositions;

  /// Vrai juste après une validation correcte (pour déclencher le flash).
  final bool validationCorrect;

  /// Modifier `reverse` actif : le joueur doit former le mot inversé.
  /// La validation et la révélation par indice itèrent sur
  /// `devinette.answer` lu de droite à gauche.
  final bool reverseAnswer;

  /// Nombre d'étoiles obtenues une fois la partie en phase `won`
  /// (0 sinon). Calculé une seule fois lors de la validation (cf.
  /// `LevelStarRating.computeStars`).
  final int starsEarned;

  /// Indices grille (positions dans [shuffledIndices]) actuellement
  /// masqués par le modifier `fog`. Le widget `CircularGrid` rend ces
  /// tuiles avec opacité 0 et ignore les taps dessus. Rotation 5 s côté
  /// controller. Vide quand le modifier n'est pas actif.
  final Set<int> fogHiddenIndices;

  /// Cauris crédités à la **dernière** victoire (= delta, pas solde
  /// cumulé). Lu par `VictoryView` pour animer le chip "+N CAURIS" et
  /// servir de base au bouton "Doubler la récompense". 0 tant que la
  /// partie n'est pas en phase `won`.
  final int caurisAwarded;

  /// Vrai si le tracé brut du doigt **en cours** se croise lui-même. Mis à
  /// jour en continu par `CircularGrid` (cf. `updateTrailSelfIntersecting`)
  /// au fil du drag. Lu une seule fois par [GameController.validate] au moment
  /// de la victoire pour décider du bonus « À main levée ». Transitoire — pas
  /// significatif hors `GamePhase.playing`.
  final bool currentTrailSelfIntersecting;

  /// Bonus « À main levée » crédité à la **dernière** victoire (0 si le tracé
  /// se croisait, si le mot était trop court, ou en mode défi du jour). Lu par
  /// `VictoryView` pour afficher la ligne bonus dédiée.
  final int freehandBonusAwarded;

  /// Nombre de mots erronés formés sur ce niveau (incrémenté dans
  /// [GameController.validate] à chaque comparaison ratée). 0 à la victoire
  /// = bonus « Sans faute ». Remis à 0 par [GameController.restart].
  final int wrongAttempts;

  /// Bonus « Sans faute » crédité à la **dernière** victoire (0 si un mot
  /// erroné a été formé, si la devinette était déjà récompensée, ou en défi
  /// du jour). Déjà inclus dans [cauris] — purement informatif pour l'UI.
  final int perfectBonusAwarded;

  /// Longueur de la série intra-session **après** cette victoire (victoire
  /// courante incluse), lue depuis `soloComboProvider`. 0 tant que la partie
  /// n'est pas gagnée ou hors périmètre série (daily, Hub).
  final int comboStreak;

  /// Multiplicateur de série effectivement appliqué à [caurisAwarded]
  /// (1.0 = pas de bonus). Affiché « Série ×N · cauris ×1,5 » par l'UI.
  final double comboMultiplierApplied;

  /// Vrai dès que le joueur a consommé son « Mélanger » gratuit du niveau
  /// (cf. [GameController.shuffleByPlayer]). Remis à false par `restart`.
  final bool shuffleUsed;

  /// Modifier `mirage` : indices **dans [effectivePool]** de la (des) lettre(s)
  /// fausse(s) ajoutée(s) en plus des distracteurs. Fixé à l'initialisation ;
  /// la tuile reste tappable et compte comme une lettre normale (elle n'est
  /// jamais dans la réponse, donc un mot qui l'utilise est toujours rejeté).
  /// Utiliser [mirageGridIndices] pour le rendu. Vide hors modifier.
  final Set<int> mirageIndices;

  /// Modifier `rain` : vrai pendant la seconde où les lettres de la grille
  /// sont floutées (1 s toutes les [GameController._rainPeriodSeconds]).
  /// Dérivé du compteur de ticks du timer des modifiers — remis à false à
  /// chaque pause/reprise, jamais bloqué à true.
  final bool rainBlurActive;

  /// Modifier `spirit` : index grille (position dans [shuffledIndices]) de la
  /// tuile actuellement « empruntée » par l'esprit, `null` sinon. Masquée et
  /// intappable comme le fog (cf. [hiddenTileIndices]), rendue après
  /// [GameController._spiritBorrowSeconds]. Suit sa lettre quand la grille
  /// est permutée (wind / earthquake / shuffle).
  final int? spiritHiddenIndex;

  /// Rafale ([LevelKind.rafale]) : index 0-based du mot en cours et nombre
  /// de mots du niveau. `roundCount == 1` pour toute autre structure.
  final int roundIndex;
  final int roundCount;

  /// Duo ([LevelKind.duo]) : seconde devinette dont le mot partage la grille
  /// avec [devinette]. `null` hors duo.
  final Devinette? secondDevinette;

  /// Duo : positions révélées par l'indice dans le second mot (espace
  /// [expectedSecondAnswer]). Pendant de [revealedPositions].
  final Set<int> secondRevealedPositions;

  /// Duo : indices des mots déjà trouvés (0 = [devinette], 1 =
  /// [secondDevinette]). Le niveau est gagné quand les deux y sont.
  final Set<int> solvedWordIndices;

  /// Boss aveugle ([LevelKind.blindBoss]) : vrai tant que l'énigme est
  /// lisible. Passe à faux [GameController.blindRiddleHideAfterSeconds]
  /// après le départ, redevient vrai le temps d'une relecture.
  final bool riddleVisible;

  /// Boss aveugle : relectures déjà consommées (la première est gratuite).
  final int rereadCount;

  /// Boss aveugle : ticks restants de la relecture en cours (0 = aucune).
  final int rereadTicksLeft;

  /// Vrai en duo (deux mots dans la grille).
  bool get isDuo => secondDevinette != null;

  /// Nombre de mots à afficher (rangées de cases) : 2 en duo, 1 sinon.
  int get wordCount => isDuo ? 2 : 1;

  /// Séquence attendue du second mot (duo), `reverse` appliqué. Vide hors duo.
  String get expectedSecondAnswer {
    final second = secondDevinette;
    if (second == null) return '';
    return reverseAnswer
        ? String.fromCharCodes(second.answer.runes.toList().reversed)
        : second.answer;
  }

  /// Séquence attendue du mot [wordIndex] (0 = principale, 1 = seconde).
  String answerFor(int wordIndex) =>
      wordIndex == 0 ? expectedAnswer : expectedSecondAnswer;

  /// Positions révélées par l'indice dans le mot [wordIndex].
  Set<int> revealedFor(int wordIndex) =>
      wordIndex == 0 ? revealedPositions : secondRevealedPositions;

  /// Vrai si le mot [wordIndex] est déjà trouvé (duo) — toujours faux hors
  /// duo, où la victoire ferme la partie.
  bool isSolved(int wordIndex) => solvedWordIndices.contains(wordIndex);

  /// Lettres à afficher dans la rangée du mot [wordIndex] : la réponse
  /// complète s'il est trouvé, la sélection en cours tant qu'elle peut
  /// encore tenir dans ce mot, rien sinon (la sélection est déjà plus
  /// longue : ce ne peut être que l'autre mot).
  String formedFor(int wordIndex) {
    if (isSolved(wordIndex)) return answerFor(wordIndex);
    final formed = formedWord;
    return formed.length <= answerFor(wordIndex).length ? formed : '';
  }

  /// Réponses attendues encore à trouver, dans l'ordre des mots.
  List<String> get remainingAnswers => <String>[
        for (var i = 0; i < wordCount; i++)
          if (!isSolved(i)) answerFor(i),
      ];

  /// Devinette sur laquelle portent l'indice, l'écran d'échec et la
  /// révélation : premier mot non trouvé en duo, [devinette] sinon.
  Devinette get focusDevinette {
    final second = secondDevinette;
    if (second != null && isSolved(0) && !isSolved(1)) return second;
    return devinette;
  }

  /// Vrai tant qu'au moins une lettre reste à révéler par l'indice dans un
  /// mot non trouvé.
  bool get canRevealMore {
    for (var i = 0; i < wordCount; i++) {
      if (!isSolved(i) && revealedFor(i).length < answerFor(i).length) {
        return true;
      }
    }
    return false;
  }

  /// Union des tuiles masquées, toutes causes confondues (fog ∪ esprit).
  /// Source unique pour le hit-test de la grille et [GameController.selectTile].
  Set<int> get hiddenTileIndices => spiritHiddenIndex == null
      ? fogHiddenIndices
      : <int>{...fogHiddenIndices, spiritHiddenIndex!};

  /// [mirageIndices] projetés en indices **grille** (positions dans
  /// [shuffledIndices]) pour le rendu du scintillement.
  Set<int> get mirageGridIndices => mirageIndices.isEmpty
      ? const <int>{}
      : <int>{
          for (var i = 0; i < shuffledIndices.length; i++)
            if (mirageIndices.contains(shuffledIndices[i])) i,
        };

  /// Séquence de lettres attendue compte tenu du modifier `reverse`.
  /// Stockée comme String pour permettre l'égalité directe avec
  /// [formedWord] et le placement des lettres par indice ([revealedPositions]).
  String get expectedAnswer => reverseAnswer
      ? String.fromCharCodes(devinette.answer.runes.toList().reversed)
      : devinette.answer;

  /// Lettres dans l'ordre shufflé (inclut les distracteurs si présents).
  List<String> get displayLetters => shuffledIndices
      .map((i) => effectivePool[i])
      .toList(growable: false);

  /// Mot formé par les indices sélectionnés (lettres dans l'ordre de sélection).
  /// Inclut les distracteurs si le joueur en tape un — la validation
  /// le rejettera puisque le mot formé ne matchera plus `expectedAnswer`.
  String get formedWord => selectedIndices
      .map((si) => effectivePool[shuffledIndices[si]])
      .join();

  /// Vrai quand la sélection doit être validée :
  /// - classique / rafale : elle a la longueur du mot attendu ;
  /// - duo : elle égale un mot restant, ou elle a atteint la longueur du
  ///   plus long mot restant (elle ne peut plus en former aucun).
  bool get isComplete {
    if (!isDuo) return selectedIndices.length == expectedAnswer.length;
    final remaining = remainingAnswers;
    if (remaining.isEmpty) return false;
    final formed = formedWord;
    if (remaining.contains(formed)) return true;
    final longest = remaining.map((a) => a.length).reduce(max);
    return formed.length >= longest;
  }

  GameState copyWith({
    Devinette? devinette,
    List<int>? selectedIndices,
    int? timeLeft,
    GamePhase? phase,
    int? cauris,
    List<int>? shuffledIndices,
    List<String>? effectivePool,
    int? hintRevealedCount,
    Set<int>? revealedPositions,
    bool? validationCorrect,
    bool? reverseAnswer,
    int? starsEarned,
    Set<int>? fogHiddenIndices,
    int? caurisAwarded,
    bool? currentTrailSelfIntersecting,
    int? freehandBonusAwarded,
    int? wrongAttempts,
    int? perfectBonusAwarded,
    int? comboStreak,
    double? comboMultiplierApplied,
    bool? shuffleUsed,
    Set<int>? mirageIndices,
    bool? rainBlurActive,
    int? spiritHiddenIndex,
    bool clearSpiritHiddenIndex = false,
    int? roundIndex,
    int? roundCount,
    Devinette? secondDevinette,
    Set<int>? secondRevealedPositions,
    Set<int>? solvedWordIndices,
    bool? riddleVisible,
    int? rereadCount,
    int? rereadTicksLeft,
  }) {
    return GameState(
      devinette: devinette ?? this.devinette,
      selectedIndices: selectedIndices ?? this.selectedIndices,
      timeLeft: timeLeft ?? this.timeLeft,
      phase: phase ?? this.phase,
      cauris: cauris ?? this.cauris,
      shuffledIndices: shuffledIndices ?? this.shuffledIndices,
      effectivePool: effectivePool ?? this.effectivePool,
      hintRevealedCount: hintRevealedCount ?? this.hintRevealedCount,
      revealedPositions: revealedPositions ?? this.revealedPositions,
      validationCorrect: validationCorrect ?? this.validationCorrect,
      reverseAnswer: reverseAnswer ?? this.reverseAnswer,
      starsEarned: starsEarned ?? this.starsEarned,
      fogHiddenIndices: fogHiddenIndices ?? this.fogHiddenIndices,
      caurisAwarded: caurisAwarded ?? this.caurisAwarded,
      currentTrailSelfIntersecting:
          currentTrailSelfIntersecting ?? this.currentTrailSelfIntersecting,
      freehandBonusAwarded: freehandBonusAwarded ?? this.freehandBonusAwarded,
      wrongAttempts: wrongAttempts ?? this.wrongAttempts,
      perfectBonusAwarded: perfectBonusAwarded ?? this.perfectBonusAwarded,
      comboStreak: comboStreak ?? this.comboStreak,
      comboMultiplierApplied:
          comboMultiplierApplied ?? this.comboMultiplierApplied,
      shuffleUsed: shuffleUsed ?? this.shuffleUsed,
      mirageIndices: mirageIndices ?? this.mirageIndices,
      rainBlurActive: rainBlurActive ?? this.rainBlurActive,
      // `null` est une valeur légitime (esprit absent) : on passe par un flag
      // explicite plutôt que par le `??` qui ne sait pas « effacer ».
      spiritHiddenIndex: clearSpiritHiddenIndex
          ? null
          : (spiritHiddenIndex ?? this.spiritHiddenIndex),
      roundIndex: roundIndex ?? this.roundIndex,
      roundCount: roundCount ?? this.roundCount,
      secondDevinette: secondDevinette ?? this.secondDevinette,
      secondRevealedPositions:
          secondRevealedPositions ?? this.secondRevealedPositions,
      solvedWordIndices: solvedWordIndices ?? this.solvedWordIndices,
      riddleVisible: riddleVisible ?? this.riddleVisible,
      rereadCount: rereadCount ?? this.rereadCount,
      rereadTicksLeft: rereadTicksLeft ?? this.rereadTicksLeft,
    );
  }
}

/// Contrôleur principal de l'écran de jeu (cf. plan.md §2 Phase 1.2).
///
/// - Timer adaptatif provenant de `args.config.timerSeconds`
///   (cf. `LevelDifficultyResolver`).
/// - Sélection par index (pas par lettre) pour gérer les doublons.
/// - Auto-validation quand [selectedIndices.length == answer.length].
/// - Modifier `reverse` : la validation compare au mot inversé et
///   l'ordre des lettres révélées par l'indice suit le mot inversé.
/// - Modifiers à tick (`wind`, `earthquake`, `fog`, `shuffle`, `rain`,
///   `spirit`) : timer dédié 1 s (cf. [_startModifierTimer]) ; `mirage`
///   ajoute une tuile fausse à l'initialisation.
/// - Récompense finale multipliée par `args.config.caurisMultiplier`
///   pour valoriser les niveaux difficiles.
/// - Série intra-session (`soloComboProvider`) : +1 par victoire Sommets,
///   reset à la défaite ; multiplicateur `eco_combo_multiplier` dès
///   `eco_combo_min_streak` victoires d'affilée sans indice, et bonus
///   « Sans faute » `eco_perfect_bonus` si aucun mot erroné.
/// - Structure du tour (`args.config.kind`, cf. `LevelKind`) :
///   - **rafale** : `args.allDevinettes` enchaînées dans la même partie ;
///     chaque mot validé recharge la grille sans overlay et crédite
///     [rafaleRoundBonusSeconds] au timer, la victoire arrive au dernier
///     mot, l'échec au timer est global ;
///   - **duo** : deux mots dans une grille dont le pool est l'union
///     (multiset) des lettres des deux réponses ; un mot est validé dès que
///     la sélection l'égale, une erreur est comptée quand la sélection
///     atteint la longueur du plus long mot restant sans correspondre ;
///   - **boss aveugle** : l'énigme s'efface après
///     [blindRiddleHideAfterSeconds] ; [rereadRiddle] la réaffiche
///     [blindRereadSeconds], chaque relecture après la première coûte
///     [blindRereadCostSeconds] de timer.
///   Les cauris d'un niveau multi-mots sont calculés **une fois** à la fin
///   sur la somme des mots (cf. [_perWordShare]) ; série, sans-faute et
///   main levée s'appliquent une fois sur la fin.
class GameController extends StateNotifier<GameState> {
  GameController(
    this._args,
    this._audio,
    this._progress,
    this._economy,
    this._analytics,
    this._tempo,
    this._combo,
  ) : super(
        _initialState(_args, _progress.state.cauris),
      ) {
    _startTimer();
    _startModifierTimer();
  }

  /// Construit l'état initial : génère les distracteurs selon la config,
  /// shuffle le pool effectif, applique le flag reverse et la structure du
  /// tour (rafale : premier mot ; duo : seconde devinette). Extrait pour
  /// être réutilisable par [restart].
  ///
  /// Robustesse : une rafale ou un duo lancé sans `extraDevinettes` (route
  /// legacy) se comporte comme un niveau classique.
  static GameState _initialState(GameArgs args, int cauris) {
    final rng = Random();
    final kind = args.config.kind;
    final second = kind == LevelKind.duo && args.extraDevinettes.isNotEmpty
        ? args.extraDevinettes.first
        : null;
    final round = _buildRound(
      config: args.config,
      devinette: args.devinette,
      second: second,
      rng: rng,
    );
    return GameState(
      devinette: args.devinette,
      selectedIndices: const <int>[],
      timeLeft: args.config.timerSeconds,
      phase: GamePhase.playing,
      cauris: cauris,
      effectivePool: round.pool,
      shuffledIndices: round.shuffled,
      reverseAnswer: args.config.hasReverse,
      mirageIndices: round.mirage,
      roundCount: kind == LevelKind.rafale ? args.allDevinettes.length : 1,
      secondDevinette: second,
    );
  }

  /// Pool effectif + permutation + tuile mirage pour une grille donnée :
  /// les lettres de [devinette] (union multiset avec celles de [second] en
  /// duo), puis les distracteurs de la config, puis l'éventuel mirage.
  ///
  /// Mirage : UNE lettre fausse de plus, tirée comme un distracteur (hors
  /// réponse, distincte des autres parasites). Jamais au-delà du plafond de
  /// tuiles que les patterns de grille absorbent proprement — plafond qui
  /// borne aussi les distracteurs d'un duo (deux mots longs réunis).
  static _RoundSetup _buildRound({
    required LevelDifficultyConfig config,
    required Devinette devinette,
    required Devinette? second,
    required Random rng,
  }) {
    final original = second == null
        ? devinette.lettersPool
        : _unionLetters(devinette.answer, second.answer);
    final answers = second == null
        ? devinette.answer
        : '${devinette.answer}${second.answer}';
    final distractorCount = min(
      config.distractorCount,
      max(0, _maxGridTiles - original.length),
    );
    final addMirage =
        config.modifiers.contains(LevelModifier.mirage) &&
        original.length + distractorCount < _maxGridTiles;
    final pool = _buildEffectivePool(
      original: original,
      answer: answers,
      distractorCount: distractorCount + (addMirage ? 1 : 0),
      rng: rng,
    );
    // La lettre mirage est la dernière ajoutée au pool effectif.
    final mirage = addMirage ? <int>{pool.length - 1} : const <int>{};
    return (
      pool: pool,
      shuffled: _shuffleIndices(pool.length, rng),
      mirage: mirage,
    );
  }

  /// Union **multiset** des lettres de deux mots : chaque lettre apparaît
  /// autant de fois que dans celui des deux mots qui l'utilise le plus,
  /// de sorte que chacun reste formable seul (les lettres restent
  /// disponibles après le premier mot trouvé).
  static List<String> _unionLetters(String a, String b) {
    final counts = <String, int>{};
    for (final word in <String>[a, b]) {
      final local = <String, int>{};
      for (final ch in word.split('')) {
        local[ch] = (local[ch] ?? 0) + 1;
      }
      for (final entry in local.entries) {
        counts[entry.key] = max(counts[entry.key] ?? 0, entry.value);
      }
    }
    return <String>[
      for (final entry in counts.entries)
        for (var i = 0; i < entry.value; i++) entry.key,
    ];
  }

  /// Génère le pool effectif = pool original + N distracteurs aléatoires
  /// pris dans l'alphabet français hors lettres de `answer` (pour ne pas
  /// créer d'ambiguïté avec les lettres légitimes du mot — un distracteur
  /// 'O' alors que le mot contient déjà 'O' pourrait piéger le `hint`).
  static List<String> _buildEffectivePool({
    required List<String> original,
    required String answer,
    required int distractorCount,
    required Random rng,
  }) {
    if (distractorCount <= 0) return List<String>.from(original);
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final excluded = answer.toUpperCase().split('').toSet();
    final available = alphabet
        .split('')
        .where((l) => !excluded.contains(l))
        .toList(growable: false);
    final picks = List<String>.from(available)..shuffle(rng);
    return <String>[
      ...original,
      ...picks.take(distractorCount),
    ];
  }

  /// Rafale : secondes créditées au timer à chaque mot validé (hors dernier).
  static const int rafaleRoundBonusSeconds = 8;

  /// Boss aveugle : délai avant que l'énigme ne s'efface, durée d'une
  /// relecture et coût (en secondes de timer) de chaque relecture après
  /// la première.
  static const int blindRiddleHideAfterSeconds = 8;
  static const int blindRereadSeconds = 2;
  static const int blindRereadCostSeconds = 2;

  static const int _windPeriodSeconds = 8;
  static const int _earthquakePeriodSeconds = 6;
  static const int _fogPeriodSeconds = 5;
  static const int _shufflePeriodSeconds = 15;

  /// Rain : une averse toutes les [_rainPeriodSeconds], qui floute les lettres
  /// pendant [_rainBlurSeconds] (tick 4 → flou, tick 5 → net).
  static const int _rainPeriodSeconds = 4;
  static const int _rainBlurSeconds = 1;

  /// Spirit : toutes les [_spiritPeriodSeconds], l'esprit emprunte une tuile
  /// pendant [_spiritBorrowSeconds] puis la rend (tick 10 → masquée,
  /// tick 13 → rendue).
  static const int _spiritPeriodSeconds = 10;
  static const int _spiritBorrowSeconds = 3;

  /// Plafond de tuiles affichables sans dégrader la grille : correspond au
  /// maximum déjà atteignable par la rampe de distracteurs (mot de 12 lettres
  /// + 4 parasites, cf. `LevelDifficultyResolver._maxDistractorCount`). Le
  /// mirage n'ajoute pas de tuile si le pool est déjà à ce plafond.
  static const int _maxGridTiles = 16;

  final GameArgs _args;
  final AudioController _audio;
  final PlayerProgressNotifier _progress;

  /// Snapshot Remote Config capturé à la construction — figé pour la durée
  /// du niveau pour ne pas mutiler les invariants (cf. doc du
  /// `RemoteConfigService`).
  final GameEconomyConfig _economy;

  /// Instrumentation analytics (events victoire / indice). Fail-soft.
  final AnalyticsService _analytics;

  /// Scheduler partagé pilotant la cadence du tic-tac audio (maquette p.12).
  /// Propriété du `tempoSchedulerProvider` — NE PAS `dispose()` ici.
  final TempoScheduler _tempo;

  /// Série intra-session partagée (propriété du `soloComboProvider`, non
  /// disposée ici). Hors périmètre en défi du jour et en mode Hub.
  final SoloComboNotifier _combo;

  /// La série ne concerne que les niveaux Sommets : ni le défi du jour
  /// (récompense fixe), ni le Hub legacy (sans progression par niveau).
  bool get _comboTracked => !_args.isDailyChallenge && _args.mountainId != null;

  Timer? _timer;
  Timer? _modifierTimer;

  /// Boss aveugle : secondes de jeu écoulées (hors pause) — pilote
  /// l'effacement initial de l'énigme. Remis à 0 par [restart].
  int _blindTicks = 0;

  /// Abonnement aux ticks du [TempoScheduler] tant que la partie est active.
  StreamSubscription<int>? _tempoSub;
  int _modifierTick = 0;
  final Random _modifierRng = Random();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Sélectionne une tuile par son index dans la grille shufflée.
  ///
  /// Règles (volontairement restrictives pour éviter qu'un tap accidentel
  /// au milieu du chemin n'explose la sélection) :
  /// - Tuile **pas encore sélectionnée** → ajoutée en fin.
  /// - Tuile **avant-dernière** (slide-back classique : le doigt revient
  ///   en arrière pendant un drag) → retire la dernière. Cascade naturelle
  ///   lettre par lettre si l'utilisateur continue à reculer.
  /// - Tuile **dernière sélectionnée** → retirée (re-tap discret = effacer).
  /// - Tuile **antérieure mais ni avant-dernière ni dernière** → ignorée.
  ///   La troncature mid-chemin serait trop destructrice sur un toucher
  ///   imprécis.
  void selectTile(int gridIndex) {
    if (state.phase != GamePhase.playing) return;
    // Une tuile masquée (fog ou empruntée par l'esprit) est intaptable. Le
    // widget devrait déjà bloquer le tap (pointer ignored), filet de sécurité
    // côté controller pour les call-sites synthétiques (tests, debug overlay).
    if (state.hiddenTileIndices.contains(gridIndex)) return;

    final selected = List<int>.from(state.selectedIndices);

    // Slide-back classique : entrer sur l'avant-dernière retire la dernière.
    if (selected.length >= 2 && selected[selected.length - 2] == gridIndex) {
      selected.removeLast();
      state = state.copyWith(
        selectedIndices: selected,
        validationCorrect: false,
      );
      _audio.hapticDeselect();
      return;
    }

    // Re-tap sur la dernière lettre : on la retire.
    if (selected.isNotEmpty && selected.last == gridIndex) {
      selected.removeLast();
      state = state.copyWith(
        selectedIndices: selected,
        validationCorrect: false,
      );
      _audio.hapticDeselect();
      return;
    }

    // Lettre antérieure (ni avant-dernière ni dernière) : ignorée.
    if (selected.contains(gridIndex)) return;

    selected.add(gridIndex);
    state = state.copyWith(selectedIndices: selected, validationCorrect: false);

    // Audio + haptique couplés (le tick haptique est déclenché par
    // AudioController.playLetterSelect — source unique, synchro garantie).
    unawaited(_audio.playLetterSelect(selected.length - 1));

    // Auto-validate when word is complete.
    if (state.isComplete) {
      validate();
    }
  }

  /// Efface la sélection courante.
  void clearSelection() {
    if (state.phase != GamePhase.playing) return;
    state = state.copyWith(
      selectedIndices: const <int>[],
      validationCorrect: false,
      // Nouveau geste à venir : on repart d'un tracé propre.
      currentTrailSelfIntersecting: false,
    );
  }

  /// Remontée continue de la géométrie du tracé brut du doigt par
  /// `CircularGrid`. Appelée **juste avant** chaque `selectTile`, de sorte que
  /// la valeur soit à jour quand la sélection complète déclenche `validate()`
  /// (synchrone). Détermine l'octroi du bonus « À main levée ».
  // Bool positionnel volontaire : la méthode est passée en tear-off comme
  // `ValueChanged<bool>` (callback de `CircularGrid`), signature imposée.
  // ignore: avoid_positional_boolean_parameters
  void updateTrailSelfIntersecting(bool selfIntersecting) {
    if (state.phase != GamePhase.playing) return;
    if (state.currentTrailSelfIntersecting == selfIntersecting) return;
    state = state.copyWith(currentTrailSelfIntersecting: selfIntersecting);
  }

  /// Coût en cauris du **prochain** indice à utiliser (avec scaling
  /// intra-niveau : 1er = base, 2e = base × multiplier, etc.).
  int get nextHintCost => _economy.hintCostForIndex(
    state.hintRevealedCount,
    tierMultiplier: _args.config.caurisMultiplier,
  );

  /// Place une lettre correcte dans une case **au hasard** parmi celles
  /// encore non révélées, et l'affiche en aperçu dans `AnswerCells` (le
  /// joueur doit toujours la former dans la roue pour valider). Le coût
  /// est progressif intra-niveau (cf. [GameEconomyConfig.hintCostMultiplier])
  /// — 1er indice au prix de base, suivants multipliés.
  void useHint() {
    if (state.phase != GamePhase.playing) return;
    // Cible : premier mot non trouvé qui a encore une case à révéler (en
    // duo, le second mot prend le relais une fois le premier entièrement
    // révélé ou trouvé).
    int? wordIndex;
    for (var i = 0; i < state.wordCount; i++) {
      if (!state.isSolved(i) &&
          state.revealedFor(i).length < state.answerFor(i).length) {
        wordIndex = i;
        break;
      }
    }
    if (wordIndex == null) return;
    final cost = nextHintCost;

    // **Priorité au freebie quotidien** : si un indice gratuit est
    // dispo, on ne décrémente PAS le solde local — le repo le consomme
    // côté `spendOnHint` sans toucher aux cauris. Garde le state UI
    // synchrone avec la persistance.
    final hasFreeHint = _progress.state.freeHintAvailable;
    if (!hasFreeHint && state.cauris < cost) return;

    // Tire une position de la réponse encore non révélée (au hasard).
    final answerLen = state.answerFor(wordIndex).length;
    final revealed = state.revealedFor(wordIndex);
    final candidates = <int>[
      for (var p = 0; p < answerLen; p++)
        if (!revealed.contains(p)) p,
    ];
    if (candidates.isEmpty) return;
    final pos = candidates[_modifierRng.nextInt(candidates.length)];
    final updated = <int>{...revealed, pos};

    state = state.copyWith(
      cauris: hasFreeHint ? state.cauris : state.cauris - cost,
      hintRevealedCount: state.hintRevealedCount + 1,
      revealedPositions: wordIndex == 0 ? updated : null,
      secondRevealedPositions: wordIndex == 1 ? updated : null,
    );

    // Persist deduction (consomme d'abord le freebie, sinon débite).
    unawaited(_progress.spendOnHint(cost));
    // Analytics : taux d'usage des indices par variante A/B (free vs payant).
    unawaited(
      _analytics.logHintUsed(
        tier: _args.config.difficultyTier,
        cost: hasFreeHint ? 0 : cost,
        free: hasFreeHint,
        levelIndex: _args.levelIndex,
      ),
    );
    // Audio: kora 2 notes douces descendantes.
    unawaited(_audio.playHintUsed());
  }

  /// Valide le mot formé par les tuiles sélectionnées.
  ///
  /// - classique : bon mot → victoire ;
  /// - rafale : bon mot → mot suivant ([_advanceRafaleRound]) ou victoire
  ///   sur le dernier ;
  /// - duo : mot égal à un mot restant → marqué trouvé, victoire quand les
  ///   deux le sont ; sinon erreur.
  void validate() {
    if (state.phase != GamePhase.playing) return;
    if (state.selectedIndices.isEmpty) return;

    final formed = state.formedWord;
    if (state.isDuo) {
      final wordIndex = <int>[
        for (var i = 0; i < state.wordCount; i++)
          if (!state.isSolved(i) && state.answerFor(i) == formed) i,
      ];
      if (wordIndex.isEmpty) {
        _rejectWord();
        return;
      }
      final solved = <int>{...state.solvedWordIndices, wordIndex.first};
      if (solved.length == state.wordCount) {
        state = state.copyWith(solvedWordIndices: solved);
        _completeLevel(lastWordLength: formed.length);
        return;
      }
      // Premier mot trouvé : ses cases se figent en doré, les lettres
      // restent disponibles dans la grille pour le second.
      state = state.copyWith(
        solvedWordIndices: solved,
        selectedIndices: const <int>[],
        validationCorrect: false,
        currentTrailSelfIntersecting: false,
      );
      unawaited(_audio.playWordComplete());
      return;
    }

    if (formed != state.expectedAnswer) {
      _rejectWord();
      return;
    }
    if (state.roundIndex < state.roundCount - 1) {
      _advanceRafaleRound();
      return;
    }
    _completeLevel(lastWordLength: formed.length);
  }

  /// Mot erroné : djembé ×2 + impact fort, sélection effacée, tentative
  /// comptée (perd le bonus « Sans faute »).
  void _rejectWord() {
    // Audio + haptique couplés (djembé ×2 + impact fort) puis effacement.
    unawaited(_audio.playWrongAnswer());
    state = state.copyWith(
      selectedIndices: const <int>[],
      validationCorrect: false,
      // Une tentative erronée de plus : perd le bonus « Sans faute ».
      wrongAttempts: state.wrongAttempts + 1,
      // Symétrie avec clearSelection : le prochain geste repart d'un tracé
      // propre (évite qu'un verdict « croisé » obsolète colle au state).
      currentTrailSelfIntersecting: false,
    );
  }

  /// Rafale : mot `k < n` validé — cue audio (accord balafon existant),
  /// devinette suivante chargée dans la même partie (nouveau pool, nouveau
  /// shuffle, sélection et révélations vides, effets transitoires levés),
  /// et [rafaleRoundBonusSeconds] crédités au timer. Aucun overlay : le
  /// timer continue de tourner.
  void _advanceRafaleRound() {
    final nextIndex = state.roundIndex + 1;
    final next = _args.allDevinettes[nextIndex];
    final round = _buildRound(
      config: _args.config,
      devinette: next,
      second: null,
      rng: _modifierRng,
    );
    state = state.copyWith(
      devinette: next,
      roundIndex: nextIndex,
      selectedIndices: const <int>[],
      revealedPositions: const <int>{},
      validationCorrect: false,
      currentTrailSelfIntersecting: false,
      timeLeft: state.timeLeft + rafaleRoundBonusSeconds,
      effectivePool: round.pool,
      shuffledIndices: round.shuffled,
      mirageIndices: round.mirage,
      // La grille change de taille : aucun index masqué ne survit.
      fogHiddenIndices: const <int>{},
      clearSpiritHiddenIndex: true,
      rainBlurActive: false,
    );
    _tempo.updateForTimeLeft(state.timeLeft);
    unawaited(_audio.playWordComplete());
  }

  /// Part de la récompense de base attribuée à **chaque** mot d'un niveau,
  /// selon sa structure : un niveau classique vaut 1 base ; une rafale
  /// vaut base × 3 × 0,6 (= ×1,8 — des mots courts, un timer commun) ; un
  /// duo vaut base × 2 × 0,75 (= ×1,5 — deux mots dans une seule grille).
  /// Chaque devinette déjà récompensée (anti-farm) retire sa part.
  static double _perWordShare(LevelKind kind) {
    switch (kind) {
      case LevelKind.rafale:
        return 0.6;
      case LevelKind.duo:
        return 0.75;
      case LevelKind.classic:
      case LevelKind.blindBoss:
        return 1;
    }
  }

  /// Victoire du niveau (dernier mot validé) : calcul des cauris, étoiles,
  /// persistance, analytics et fanfare.
  void _completeLevel({required int lastWordLength}) {
    _timer?.cancel();
    _stopTempo();
    // Récompense :
    // - **Mode standard** : (base + bonus vitesse × timeLeft) × part par
    //   mot × mots encore récompensables × multiplier de difficulté
    //   (1.0 → 2.5 selon le tier). Base et bonus pilotés par Remote
    //   Config (cf. `GameEconomyConfig`).
    // - **Mode défi du jour** : montant fixe = base daily (100). Le
    //   bonus de palier (3/7/30 jours) est octroyé en plus par le
    //   notifier daily, mais n'est PAS affiché ici (VictoryView reste
    //   sur le montant base — feedback bonus géré côté hub).
    // Série intra-session : incrémentée AVANT le calcul pour que la
    // victoire courante compte dans la longueur comparée au seuil.
    final comboStreak = _comboTracked ? _combo.increment() : 0;
    var comboMultiplier = 1.0;
    var perfectBonus = 0;
    final int caurisAwarded;
    // Anti-farm par devinette : chaque mot du niveau déjà récompensé
    // (gagné une 1re fois, ou réponse révélée) ne rapporte plus rien. La
    // victoire reste valide pour la progression (niveau, étoiles).
    final rewardableWords = _levelDevinettes
        .where((d) => !_progress.state.isDevinetteRewarded(d.id))
        .length;
    if (_args.isDailyChallenge) {
      // Défi du jour : récompense fixe, mais UNE fois par jour. S'il a
      // déjà été joué aujourd'hui, rejouer n'attribue rien — le notifier
      // `recordDailyChallengeResult` est idempotent côté persistance, on
      // aligne ici l'affichage VictoryView pour ne pas annoncer un faux
      // « +100 ».
      final alreadyPlayedToday =
          _args.dailyDate != null &&
          DailyChallengeService.isPlayedOn(
            progress: _progress.state,
            date: _args.dailyDate!,
          );
      caurisAwarded = alreadyPlayedToday
          ? 0
          : DailyChallengeService.rewardCauris;
    } else if (rewardableWords == 0) {
      caurisAwarded = 0;
    } else {
      final raw =
          _economy.winRewardBase +
          state.timeLeft * _economy.speedBonusPerSecond;
      // Multiplicateur de série : seuil atteint ET aucun indice sur ce
      // niveau (une série « assistée » ne vaut pas bonus).
      if (_comboTracked &&
          state.hintRevealedCount == 0 &&
          _economy.comboApplies(comboStreak)) {
        comboMultiplier = _economy.comboMultiplier;
      }
      caurisAwarded =
          (raw *
                  _perWordShare(_args.config.kind) *
                  rewardableWords *
                  _args.config.caurisMultiplier *
                  comboMultiplier)
              .round();
      // « Sans faute » : aucun mot erroné formé sur le niveau. Réservé aux
      // devinettes encore récompensables (sinon farm par rejouabilité).
      if (state.wrongAttempts == 0) perfectBonus = _economy.perfectBonus;
    }
    // Bonus « À main levée » : récompense un mot relié d'un seul geste
    // continu sans que le tracé brut du doigt ne se croise lui-même. Hors
    // périmètre en mode défi du jour (flow de récompense fixe séparé). Sur
    // un niveau multi-mots, il porte sur le dernier mot formé.
    final freehandBonus =
        (!_args.isDailyChallenge && !state.currentTrailSelfIntersecting)
        ? _economy.freehandBonus(lastWordLength)
        : 0;
    // Étoiles : (1) victoire (2) sans indice (3) ≥ 50 % timer restant.
    final stars = LevelStarRating.computeStars(
      won: true,
      hintUsed: state.hintRevealedCount > 0,
      timerSeconds: _args.config.timerSeconds,
      timeLeftAtVictory: state.timeLeft,
    );
    state = state.copyWith(
      phase: GamePhase.won,
      validationCorrect: true,
      cauris: state.cauris + caurisAwarded + freehandBonus + perfectBonus,
      starsEarned: stars,
      caurisAwarded: caurisAwarded,
      freehandBonusAwarded: freehandBonus,
      perfectBonusAwarded: perfectBonus,
      comboStreak: comboStreak,
      comboMultiplierApplied: comboMultiplier,
    );
    // Persiste la victoire — sauf en mode défi du jour qui a son
    // propre flow (cf. `GameView` qui appelle
    // `recordDailyChallengeResult` avec un montant fixe et n'utilise
    // pas le compteur de niveaux montagne).
    if (!_args.isDailyChallenge) {
      unawaited(
        _progress.recordWin(
          mountainId: _args.mountainId,
          caurisAwarded: caurisAwarded + freehandBonus + perfectBonus,
          levelIndex: _args.levelIndex,
          starsEarned: stars,
          devinetteId: state.devinette.id,
        ),
      );
      // Anti-farm sur chaque mot d'un niveau multi-mots : `recordWin` ne
      // marque que la devinette courante, les autres le sont ici.
      for (final d in _levelDevinettes) {
        if (d.id != state.devinette.id) {
          unawaited(_progress.markDevinetteRewarded(d.id));
        }
      }
    }
    // Analytics : métrique de gameplay/économie pour l'experiment A/B.
    unawaited(
      _analytics.logLevelWon(
        tier: _args.config.difficultyTier,
        caurisAwarded: caurisAwarded,
        hintsUsed: state.hintRevealedCount,
        timeLeft: state.timeLeft,
        stars: stars,
        isDaily: _args.isDailyChallenge,
        kind: _args.config.kind.name,
        exposed: _args.isExposed,
        levelIndex: _args.levelIndex,
        mountainId: _args.mountainId,
      ),
    );
    // Audio + haptique couplés (déclenchés par AudioController) : accord
    // balafon + impact moyen immédiats, puis fanfare griot (boss ou
    // standard) + impact fort décalés de 350 ms pour s'aligner avec
    // l'attaque percussive de la fanfare.
    unawaited(_audio.playWordComplete());
    final isBoss = _args.config.isBoss;
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (isBoss) {
        unawaited(_audio.playBossVictory());
      } else {
        unawaited(_audio.playVictory());
      }
    });
  }

  /// Devinettes effectivement jouées sur ce niveau : toutes celles d'une
  /// rafale ou d'un duo, la principale seule sinon (les extras d'une config
  /// classique sont ignorés).
  List<Devinette> get _levelDevinettes => _args.config.kind.isMultiWord
      ? _args.allDevinettes
      : <Devinette>[_args.devinette];

  /// Boss aveugle : réaffiche l'énigme pendant [blindRereadSeconds]. La
  /// première relecture est gratuite, chaque suivante retire
  /// [blindRereadCostSeconds] au timer (plancher 1 s : le tick suivant
  /// termine la partie). No-op hors boss aveugle, hors phase `playing` ou
  /// quand l'énigme est déjà lisible.
  void rereadRiddle() {
    if (state.phase != GamePhase.playing) return;
    if (_args.config.kind != LevelKind.blindBoss) return;
    if (state.riddleVisible) return;
    final count = state.rereadCount + 1;
    final timeLeft = count > 1
        ? max(1, state.timeLeft - blindRereadCostSeconds)
        : state.timeLeft;
    state = state.copyWith(
      riddleVisible: true,
      rereadCount: count,
      rereadTicksLeft: blindRereadSeconds,
      timeLeft: timeLeft,
    );
    _tempo.updateForTimeLeft(timeLeft);
    unawaited(_audio.playHintUsed());
  }

  /// « Mélanger » gratuit, **une fois par niveau** : re-mélange la grille en
  /// préservant la sélection courante (délègue à [_applyShuffle], même
  /// logique que le modifier `shuffle`). No-op hors phase `playing` ou si
  /// déjà utilisé ; [restart] rend le bouton à nouveau disponible. Cue kora
  /// discret (celui de l'indice) — pas de nouveau son.
  void shuffleByPlayer() {
    if (state.phase != GamePhase.playing) return;
    if (state.shuffleUsed) return;
    _applyShuffle();
    state = state.copyWith(shuffleUsed: true);
    unawaited(_audio.playHintUsed());
  }

  /// Suspend le décompte sans changer la phase. Idempotent — no-op si la
  /// partie n'est pas en cours. Appelé quand l'app passe en arrière-plan ou
  /// quand on ouvre un modal bloquant (confirmation, ad, IAP…).
  void pause() {
    if (state.phase != GamePhase.playing) return;
    _timer?.cancel();
    _timer = null;
    _stopTempo();
    _modifierTimer?.cancel();
    _modifierTimer = null;
    // Un modal ne doit pas figer une averse ou une lettre empruntée : les
    // effets à durée (rain / spirit) sont rendus, ils repartiront du tick 0.
    _clearTransientModifierEffects();
  }

  /// Reprend le décompte depuis le `timeLeft` actuel. No-op si la partie n'est
  /// pas en phase playing ou si un timer tourne déjà.
  void resume() {
    if (state.phase != GamePhase.playing) return;
    if (_timer != null && _timer!.isActive) return;
    _startTimer();
    _startModifierTimer();
  }

  /// Re-démarre la même devinette : re-shuffle, timer adaptatif depuis
  /// la config, sélection vide. Génère de nouveaux distracteurs aléatoires
  /// pour éviter la mémorisation d'une grille spécifique entre runs.
  void restart() {
    _timer?.cancel();
    _modifierTimer?.cancel();
    _blindTicks = 0;
    state = _initialState(_args, _progress.state.cauris);
    _startTimer();
    _startModifierTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopTempo();
    _modifierTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _startTimer() {
    _timer?.cancel();
    _startTempo();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.phase != GamePhase.playing) {
        _timer?.cancel();
        _stopTempo();
        return;
      }
      if (state.timeLeft <= 1) {
        _timer?.cancel();
        _stopTempo();
        state = state.copyWith(timeLeft: 0, phase: GamePhase.lost);
        // La défaite casse la série intra-session.
        if (_comboTracked) _combo.reset();
        // Audio + haptique couplés (balafon descendant + tam-tam + impact fort).
        unawaited(_audio.playFailure());
      } else {
        state = state.copyWith(timeLeft: state.timeLeft - 1);
        // Accélère le tic-tac quand le temps s'épuise (60→90→140 BPM).
        _tempo.updateForTimeLeft(state.timeLeft);
        _tickBlindRiddle();
      }
    });
  }

  /// Boss aveugle, une fois par seconde de jeu : compte à rebours de la
  /// relecture en cours, puis effacement initial de l'énigme au bout de
  /// [blindRiddleHideAfterSeconds]. Rien à faire hors boss aveugle.
  void _tickBlindRiddle() {
    if (_args.config.kind != LevelKind.blindBoss) return;
    _blindTicks++;
    if (state.rereadTicksLeft > 0) {
      final left = state.rereadTicksLeft - 1;
      state = state.copyWith(rereadTicksLeft: left, riddleVisible: left > 0);
      return;
    }
    if (state.riddleVisible && _blindTicks >= blindRiddleHideAfterSeconds) {
      state = state.copyWith(riddleVisible: false);
    }
  }

  /// Démarre le tic-tac audio adaptatif et s'abonne aux ticks du scheduler.
  /// Idempotent : repart toujours d'un état propre (le scheduler est partagé).
  void _startTempo() {
    _tempoSub?.cancel();
    _tempo
      ..stop()
      ..updateForTimeLeft(state.timeLeft);
    _tempoSub = _tempo.ticks.listen((_) {
      // Le scheduler peut émettre un dernier tick juste après une
      // victoire/défaite : on ne joue le tic que pendant le jeu actif.
      if (state.phase != GamePhase.playing) return;
      unawaited(_audio.playTimerTick(_tempo.bpm));
    });
    _tempo.start();
  }

  /// Stoppe le tic-tac et libère l'abonnement. NE dispose PAS le scheduler
  /// (propriété du `tempoSchedulerProvider` partagé).
  void _stopTempo() {
    _tempoSub?.cancel();
    _tempoSub = null;
    _tempo.stop();
  }

  /// Modifiers qui ont besoin du tick périodique (les autres — reverse,
  /// thinAir, mirage — sont résolus à l'initialisation).
  static const Set<LevelModifier> _tickedModifiers = <LevelModifier>{
    LevelModifier.wind,
    LevelModifier.earthquake,
    LevelModifier.fog,
    LevelModifier.shuffle,
    LevelModifier.rain,
    LevelModifier.spirit,
  };

  /// Timer séparé pour les effets des modifiers (wind / earthquake / fog /
  /// shuffle / rain / spirit). Tick chaque seconde et déclenche chaque effet
  /// selon sa période propre. Indépendant du timer principal pour pouvoir
  /// être suspendu sans toucher au compte à rebours.
  ///
  /// Rain et spirit sont **dérivés du compteur de ticks** : (re)démarrer le
  /// timer remet le compteur à 0 et efface tout flou / emprunt en cours, donc
  /// aucun état transitoire ne peut rester bloqué après une pause/reprise.
  void _startModifierTimer() {
    final mods = _args.config.modifiers;
    final hasAny = mods.any(_tickedModifiers.contains);
    if (!hasAny) return; // Pas de tic-tac inutile si aucun modifier visuel.
    _modifierTimer?.cancel();
    _modifierTick = 0;
    _clearTransientModifierEffects();
    _modifierTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.phase != GamePhase.playing) {
        _modifierTimer?.cancel();
        return;
      }
      _modifierTick++;
      if (mods.contains(LevelModifier.wind) &&
          _modifierTick % _windPeriodSeconds == 0) {
        _applyWind();
      }
      if (mods.contains(LevelModifier.earthquake) &&
          _modifierTick % _earthquakePeriodSeconds == 0) {
        _applyEarthquake();
      }
      if (mods.contains(LevelModifier.fog) &&
          _modifierTick % _fogPeriodSeconds == 0) {
        _applyFog();
      }
      if (mods.contains(LevelModifier.shuffle) &&
          _modifierTick % _shufflePeriodSeconds == 0) {
        _applyShuffle();
      }
      if (mods.contains(LevelModifier.rain)) _applyRain();
      if (mods.contains(LevelModifier.spirit)) _applySpirit();
    });
  }

  /// Rain : flou actif pendant les [_rainBlurSeconds] premiers ticks de
  /// chaque période, à partir de la première période révolue. Pur calcul sur
  /// le compteur — aucun `Future.delayed` à annuler en pause.
  void _applyRain() {
    final active =
        _modifierTick >= _rainPeriodSeconds &&
        _modifierTick % _rainPeriodSeconds < _rainBlurSeconds;
    if (active == state.rainBlurActive) return;
    state = state.copyWith(rainBlurActive: active);
  }

  /// Spirit : au début de chaque période, emprunte une tuile ni sélectionnée
  /// ni déjà masquée ; la rend [_spiritBorrowSeconds] ticks plus tard.
  void _applySpirit() {
    final phase = _modifierTick % _spiritPeriodSeconds;
    if (phase == 0) {
      _borrowSpiritTile();
    } else if (phase == _spiritBorrowSeconds &&
        state.spiritHiddenIndex != null) {
      state = state.copyWith(clearSpiritHiddenIndex: true);
    }
  }

  void _borrowSpiritTile() {
    final len = state.shuffledIndices.length;
    final hidden = state.hiddenTileIndices;
    final candidates = <int>[
      for (var i = 0; i < len; i++)
        if (!state.selectedIndices.contains(i) && !hidden.contains(i)) i,
    ];
    if (candidates.isEmpty) return; // Tout est pris : l'esprit passe son tour.
    final pick = candidates[_modifierRng.nextInt(candidates.length)];
    state = state.copyWith(spiritHiddenIndex: pick);
  }

  /// Rend la lettre empruntée et lève le flou de pluie, si présents. Appelé à
  /// chaque (re)démarrage du timer des modifiers et à la pause.
  void _clearTransientModifierEffects() {
    if (!state.rainBlurActive && state.spiritHiddenIndex == null) return;
    state = state.copyWith(rainBlurActive: false, clearSpiritHiddenIndex: true);
  }

  /// Wind : choisit une case au hasard et swap avec sa voisine logique
  /// dans le cercle (gridIdx + 1 mod len). Léger drift d'une lettre.
  void _applyWind() {
    final len = state.shuffledIndices.length;
    if (len < 2) return;
    final a = _modifierRng.nextInt(len);
    final b = (a + 1) % len;
    _swapTiles(a, b);
  }

  /// Earthquake : choisit 2 cases distinctes au hasard et les échange.
  /// Mouvement plus brutal que wind (positions arbitraires, pas forcément
  /// voisines).
  void _applyEarthquake() {
    final len = state.shuffledIndices.length;
    if (len < 2) return;
    final a = _modifierRng.nextInt(len);
    var b = _modifierRng.nextInt(len);
    while (b == a) {
      b = _modifierRng.nextInt(len);
    }
    _swapTiles(a, b);
  }

  /// Fog : masque 1 tuile aléatoire (différente de la précédente quand
  /// possible). Le widget `CircularGrid` rend opacity 0 et ignore les
  /// taps sur cet index.
  void _applyFog() {
    final len = state.shuffledIndices.length;
    if (len < 2) return;
    final previous = state.fogHiddenIndices;
    var next = _modifierRng.nextInt(len);
    // Tente d'éviter de re-masquer la même tuile (rotation visible).
    var attempts = 0;
    while (previous.contains(next) && attempts < 5) {
      next = _modifierRng.nextInt(len);
      attempts++;
    }
    state = state.copyWith(fogHiddenIndices: <int>{next});
  }

  /// Shuffle : re-Fisher-Yates complet de `shuffledIndices`. Casse la
  /// mémoire spatiale du joueur. La sélection en cours est préservée :
  /// chaque indice sélectionné est remplacé par sa nouvelle position.
  void _applyShuffle() {
    final len = state.shuffledIndices.length;
    if (len < 2) return;
    final newShuffled = _shuffleIndices(len, _modifierRng);
    // Translate selectedIndices via la permutation. Pour chaque case
    // sélectionnée (gridIdx), on trouve où la lettre originale a atterri
    // après le re-shuffle.
    final newSelected = state.selectedIndices
        .map((oldGridIdx) {
          final letterPoolIdx = state.shuffledIndices[oldGridIdx];
          return newShuffled.indexOf(letterPoolIdx);
        })
        .toList(growable: false);
    // La lettre empruntée par l'esprit suit elle aussi la permutation.
    final spirit = state.spiritHiddenIndex;
    state = state.copyWith(
      shuffledIndices: newShuffled,
      selectedIndices: newSelected,
      spiritHiddenIndex: spirit == null
          ? null
          : newShuffled.indexOf(state.shuffledIndices[spirit]),
    );
  }

  /// Swap atomique entre 2 cases de la grille. La sélection « suit » les
  /// lettres : si une case sélectionnée bouge, son indice est remplacé
  /// par le nouvel emplacement de la même lettre.
  void _swapTiles(int a, int b) {
    final newShuffled = List<int>.from(state.shuffledIndices);
    final tmp = newShuffled[a];
    newShuffled[a] = newShuffled[b];
    newShuffled[b] = tmp;
    int follow(int i) {
      if (i == a) return b;
      if (i == b) return a;
      return i;
    }

    final newSelected = state.selectedIndices
        .map(follow)
        .toList(growable: false);
    final spirit = state.spiritHiddenIndex;
    state = state.copyWith(
      shuffledIndices: newShuffled,
      selectedIndices: newSelected,
      spiritHiddenIndex: spirit == null ? null : follow(spirit),
    );
  }

  /// Fisher-Yates shuffle sur [0..count-1]. `rng` injectable pour que la
  /// même instance Random soit partagée avec [_buildEffectivePool] (tirage
  /// distracteurs + shuffle cohérents sur un même run).
  static List<int> _shuffleIndices(int count, [Random? rng]) {
    final r = rng ?? Random();
    final list = List<int>.generate(count, (i) => i);
    for (var i = list.length - 1; i > 0; i--) {
      final j = r.nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }
}

/// Provider family : un [GameController] par [GameArgs].
final gameControllerProvider = StateNotifierProvider.autoDispose
    .family<GameController, GameState, GameArgs>(
      (ref, args) => GameController(
        args,
        ref.read(audioControllerProvider.notifier),
        ref.read(playerProgressProvider.notifier),
        ref.read(gameEconomyConfigProvider),
        ref.read(analyticsServiceProvider),
        ref.read(tempoSchedulerProvider),
        ref.read(soloComboProvider.notifier),
      ),
    );
