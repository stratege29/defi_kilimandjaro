import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_kind.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';

/// Résout la configuration de difficulté d'un niveau à partir de
/// `(montagne, levelIndex)`. Fonction pure et déterministe — même entrée
/// produit toujours la même config (critique pour les tests et la
/// reproductibilité).
///
/// Remplace l'ancienne `difficultyForAltitude` (supprimée). Le contrat
/// unique est désormais [LevelDifficultyConfig].
///
/// Modèle en deux couches :
///
/// 1. **Le tier** (1–5) vient de l'altitude (palier validé PO option B) et
///    fixe la *base* de chaque paramètre.
/// 2. **La rampe intra-sommet** fait ensuite varier ces bases avec le
///    `levelIndex` (1-based) pour qu'un sommet à 4 ou 8 niveaux ne soit pas
///    une suite de niveaux identiques :
///    - **bucket de longueur** = tier, +1 sur le boss dès le tier 2
///      (plafond 5) ;
///    - **distracteurs** = base(tier) + (levelIndex − 1) ÷ 2, plafonné à
///      [maxDistractorCount] ;
///    - **timer** = base(tier) − 2 s par niveau, plancher à 60 % de la
///      base, puis ×0,8 si `thinAir` ;
///    - **multiplicateur cauris** = mult(tier) × (1 + 0,1 × (levelIndex − 1)),
///      +0,25 sur le boss, arrondi à 2 décimales ;
///    - **modifiers** : rotation déterministe niveau par niveau (jamais deux
///      niveaux consécutifs avec le même modificateur actif), signature
///      boss (`shuffle`) et signature tectonique (`earthquake` garanti),
///      voir [_attributeModifiers] ;
///    - **structure du tour** ([LevelKind]) : classique aux niveaux 1-2,
///      boss aveugle sur le boss des tiers ≥ 3, sinon tirage par hachage
///      d'une rafale ou d'un duo sans deux rafale/duo consécutifs, voir
///      [_kindChain].
///
/// Le flag **isBoss** marque la dernière énigme d'une montagne.
abstract final class LevelDifficultyResolver {
  /// Construit la config pour `mountain` et son `levelIndex` 1-based.
  /// `levelIndex` est borné dans `1..mountain.totalLevels` ; les valeurs
  /// hors plage sont clampées sans planter (UX > strictness).
  static LevelDifficultyConfig resolve({
    required Mountain mountain,
    required int levelIndex,
  }) {
    final clampedLevel = levelIndex.clamp(1, mountain.totalLevels);
    final tier = _tierForAltitude(mountain.altitude);
    final isBoss = clampedLevel == mountain.totalLevels;
    final bucket = _wordLengthBucketFor(tier: tier, isBoss: isBoss);
    final modifiers = _attributeModifiers(
      mountain: mountain,
      levelIndex: clampedLevel,
      tier: tier,
      isBoss: isBoss,
    );
    final timer = _timerSecondsFor(
      tier: tier,
      levelIndex: clampedLevel,
      thinAir: modifiers.contains(LevelModifier.thinAir),
    );

    return LevelDifficultyConfig(
      difficultyTier: tier,
      wordLengthBucket: bucket,
      timerSeconds: timer,
      caurisMultiplier: _caurisMultiplierFor(
        tier: tier,
        levelIndex: clampedLevel,
        isBoss: isBoss,
      ),
      distractorCount: _distractorCountFor(
        tier: tier,
        levelIndex: clampedLevel,
      ),
      modifiers: modifiers,
      isBoss: isBoss,
      kind: _kindChain(mountain: mountain, tier: tier)[clampedLevel - 1],
    );
  }

  /// Vrai quand le niveau propose l'embranchement « voie exposée » avant de
  /// se lancer : niveau [_branchingLevel] exactement, sur les sommets d'au
  /// moins [_branchingMinTotalLevels] niveaux. Déterministe, sans hachage.
  static bool isBranchingLevel({
    required Mountain mountain,
    required int levelIndex,
  }) {
    return mountain.totalLevels >= _branchingMinTotalLevels &&
        levelIndex == _branchingLevel;
  }

  /// Variante « voie exposée » d'une config : une lettre parasite de plus
  /// (plafond [maxDistractorCount]), timer × [_exposedTimerFactor], cauris
  /// × [_exposedCaurisFactor] (arrondi à 2 décimales). Le reste (tier,
  /// modificateurs, structure du tour) est inchangé.
  static LevelDifficultyConfig exposedVariant(LevelDifficultyConfig config) {
    return config.copyWith(
      distractorCount: (config.distractorCount + 1).clamp(
        0,
        maxDistractorCount,
      ),
      timerSeconds: (config.timerSeconds * _exposedTimerFactor).round(),
      caurisMultiplier:
          (config.caurisMultiplier * _exposedCaurisFactor * 100).round() / 100,
    );
  }

  /// Config pour mode Hub (sans contexte montagne). Ne devrait normalement
  /// pas exister mais le routeur peut atterrir sur `/game` sans `mountainId`
  /// — on tombe sur la config fallback la plus douce.
  static LevelDifficultyConfig fallback() => LevelDifficultyConfig.fallback;

  /// Renvoie le tier de difficulté (1–5) pour une altitude donnée. Exposé
  /// pour les services qui doivent raisonner sur le tier sans passer par
  /// la config complète (ex. `StarGate` pour gating l'accès aux mondes).
  ///
  /// Source de vérité unique pour les seuils — toute modification ici se
  /// propage à `resolve()`, `StarGate.computeUnlockedTier()`, et aux tests.
  static int tierForAltitude(int altitudeMeters) =>
      _tierForAltitude(altitudeMeters);

  /// Ensemble **trié** (ordre de déclaration de l'enum) des modificateurs
  /// « actifs » éligibles pour ce niveau — c'est dans cette liste que
  /// [resolve] tire le modificateur du niveau. Vide sur les niveaux 1-2.
  ///
  /// Exposé pour les tests et l'outillage (overlay debug) : il permet de
  /// vérifier les règles d'éligibilité (tectonique, altitude, tier) sans
  /// dépendre du tirage par hachage.
  static List<LevelModifier> candidateModifiers({
    required Mountain mountain,
    required int levelIndex,
  }) {
    final clampedLevel = levelIndex.clamp(1, mountain.totalLevels);
    final tier = _tierForAltitude(mountain.altitude);
    if (clampedLevel <= _tutorialMaxLevel) return const <LevelModifier>[];
    if (clampedLevel <= _gentleRampMaxLevel) {
      // Zone douce : palette de base, élargie dès le tier 3 à `mirage` et
      // `spirit` (effets doux eux aussi). Sans cet élargissement, les 28
      // sommets tier ≥ 3 à 4 niveaux ne verraient jamais que wind/shuffle/
      // rain. `reverse` et `fog` restent hors zone douce.
      return _sorted(tier >= 3 ? _gentleModifiersExtended : _gentleModifiers);
    }

    final candidates = <LevelModifier>{};
    // earthquake : signature des pays tectoniques (Rift, volcans actifs),
    // réservé au tier ≥ 3 pour ne pas brutaliser la rampe basse.
    if (_isTectonic(mountain.countryCode) && tier >= 3) {
      candidates.add(LevelModifier.earthquake);
    }
    // wind : vents catabatiques dès 3000 m.
    if (mountain.altitude >= _windAltitudeMeters) {
      candidates.add(LevelModifier.wind);
    }
    // fog : zone des nuages dès 2000 m.
    if (mountain.altitude >= _fogAltitudeMeters) {
      candidates.add(LevelModifier.fog);
    }
    // Modificateurs cognitifs / de masquage : tier ≥ 3 uniquement.
    if (tier >= 3) {
      candidates.addAll(const <LevelModifier>{
        LevelModifier.reverse,
        LevelModifier.mirage,
        LevelModifier.spirit,
        LevelModifier.rain,
        LevelModifier.shuffle,
      });
    }
    // rain : le plus doux des modificateurs, ouvert dès le tier 2.
    if (tier >= 2) {
      candidates.add(LevelModifier.rain);
    }
    // Garde-fou : la rotation exige au moins deux candidats pour garantir
    // que deux niveaux consécutifs diffèrent. Ne concerne que les sommets
    // tier 1-2 à ≥ 5 niveaux (absents de `mountains.json`, mais possibles
    // en test ou dans un futur pack) — on retombe sur la palette douce.
    if (candidates.length < 2) {
      candidates.addAll(_gentleModifiers);
    }
    return _sorted(candidates);
  }

  // ---------------------------------------------------------------------------
  // Mapping primitives
  // ---------------------------------------------------------------------------

  static int _tierForAltitude(int altitudeMeters) {
    // Tier 1 étendu à < 700 m (vs < 500 m initial) pour donner une vraie
    // zone d'onboarding : 3 premières montagnes (Red Rocks, Sambadougou,
    // Sokbaro) = 10 niveaux à 4 lettres avant le premier saut de
    // difficulté. Tena Kourou (749 m) bascule en Tier 2 pour amorcer la
    // rampe. La borne haute (700 m) reste **strictement** exclusive :
    // 700 m exact = Tier 2 (cf. tests).
    if (altitudeMeters < 700) return 1;
    if (altitudeMeters < 1500) return 2;
    if (altitudeMeters < 3000) return 3;
    if (altitudeMeters < 4500) return 4;
    return 5;
  }

  /// Bucket de longueur de mot : mapping 1:1 avec le tier, +1 sur le boss
  /// (plafond 5) pour que la finale d'un sommet demande un mot plus long.
  /// Le tier 1 est exempté : Red Rocks niveau 2 est le 2ᵉ niveau du jeu,
  /// il reste sur des mots de 4 lettres (le boss y garde son bonus cauris).
  /// La sélection de devinette gère le fallback ±1 / ±2 si le pool de
  /// cette taille est trop maigre.
  static int _wordLengthBucketFor({required int tier, required bool isBoss}) {
    if (!isBoss || tier == 1) return tier;
    return (tier + 1).clamp(1, 5);
  }

  static int _expectedWordLengthForBucket(int bucket) {
    // Borne basse du bucket (cf. doc bucket dans LevelDifficultyConfig).
    switch (bucket) {
      case 1:
        return 4;
      case 2:
        return 5;
      case 3:
        return 7;
      case 4:
        return 8;
      case 5:
        return 9;
      default:
        return 5;
    }
  }

  // ---------------------------------------------------------------------------
  // Rampe intra-sommet
  // ---------------------------------------------------------------------------

  /// Un distracteur supplémentaire tous les [_distractorRampStepLevels]
  /// niveaux : niveaux 1-2 → +0, 3-4 → +1, 5-6 → +2, 7-8 → +3.
  static const int _distractorRampStepLevels = 2;

  /// Plafond absolu de lettres parasites.
  ///
  /// Calcul : les patterns de grille curés (`compatiblePatterns` dans
  /// `letter_grid_pattern.dart`) sont validés par tests jusqu'à **10
  /// tuiles** ; au-delà, seuls les patterns 2D universels (circle, scatter,
  /// jittered, spiral, clusters, grid) restent éligibles et acceptent
  /// n'importe quel count. Longueur haute des buckets : 4 / 6 / 7 / 8 / 9+
  /// (12 max dans les packs). Avec un plafond de 4 :
  /// - buckets 1-4 : ≤ 8 + 4 = 12 tuiles, dont ≤ 10 tuiles (patterns curés)
  ///   pour tout mot ≤ 6 lettres ;
  /// - bucket 5 (mot de 9 à 12 lettres) : ≤ 16 tuiles, soit +1 par rapport
  ///   aux 15 tuiles déjà possibles avant la rampe (12 + 3 au tier 5).
  /// Un plafond plus haut ferait basculer les buckets 3-4 hors des patterns
  /// curés sur la majorité des niveaux ; plus bas, la rampe des tiers 1-2
  /// (0 → 2 distracteurs) perdrait son dernier palier.
  static const int maxDistractorCount = 4;

  /// Nombre de lettres parasites : base(tier) + rampe intra-sommet.
  /// Base : 0 en zone tutoriel (tier 1-2), puis +1 par palier.
  /// Effet sur tiers 1-2 : 0 aux niveaux 1-2, 1 aux niveaux 3-4, 2 au 5+.
  static int _distractorCountFor({required int tier, required int levelIndex}) {
    final ramp = (levelIndex - 1) ~/ _distractorRampStepLevels;
    final count = _baseDistractorCountForTier(tier) + ramp;
    return count.clamp(0, maxDistractorCount);
  }

  static int _baseDistractorCountForTier(int tier) {
    switch (tier) {
      case 1:
      case 2:
        return 0;
      case 3:
        return 1;
      case 4:
        return 2;
      case 5:
        return 3;
      default:
        return 0;
    }
  }

  /// Secondes retirées au timer à chaque niveau supplémentaire.
  static const int _timerRampSecondsPerLevel = 2;

  /// Plancher du timer rampé, en proportion de la base du tier.
  static const double _timerFloorRatio = 0.6;

  /// Facteur appliqué au timer quand `thinAir` est actif (hypoxie).
  static const double _thinAirTimerFactor = 0.8;

  /// Timer de base du tier : `15 + 3·wordLen + 2·tier`, avec la longueur
  /// attendue dérivée du bucket du tier (borne basse — conservateur, évite
  /// les niveaux étouffants si la sélection tombe sur un mot plus court).
  /// Le boss garde la base de son tier : son mot plus long est compensé
  /// par le multiplicateur cauris majoré, pas par du temps en plus.
  static int _baseTimerSecondsForTier(int tier) {
    final expectedWordLen = _expectedWordLengthForBucket(tier);
    return 15 + 3 * expectedWordLen + 2 * tier;
  }

  /// Timer rampé : base(tier) − 2 s par niveau, plancher à 60 % de la base
  /// (arrondi), puis ×0,8 si `thinAir`.
  static int _timerSecondsFor({
    required int tier,
    required int levelIndex,
    required bool thinAir,
  }) {
    final base = _baseTimerSecondsForTier(tier);
    final floor = (base * _timerFloorRatio).round();
    final ramped = base - _timerRampSecondsPerLevel * (levelIndex - 1);
    var timer = ramped < floor ? floor : ramped;
    if (thinAir) {
      timer = (timer * _thinAirTimerFactor).round();
    }
    return timer;
  }

  /// Bonus relatif du multiplicateur cauris par niveau supplémentaire.
  static const double _caurisRampPerLevel = 0.1;

  /// Bonus absolu ajouté au multiplicateur du boss.
  static const double _bossCaurisBonus = 0.25;

  /// Multiplicateur cauris : mult(tier) × (1 + 0,1 × (levelIndex − 1)),
  /// +0,25 sur le boss, arrondi à 2 décimales pour un affichage stable.
  static double _caurisMultiplierFor({
    required int tier,
    required int levelIndex,
    required bool isBoss,
  }) {
    final ramp = 1 + _caurisRampPerLevel * (levelIndex - 1);
    var multiplier = _baseCaurisMultiplierForTier(tier) * ramp;
    if (isBoss) multiplier += _bossCaurisBonus;
    return (multiplier * 100).round() / 100;
  }

  static double _baseCaurisMultiplierForTier(int tier) {
    switch (tier) {
      case 1:
        return 1;
      case 2:
        return 1.3;
      case 3:
        return 1.6;
      case 4:
        return 2;
      case 5:
        return 2.5;
      default:
        return 1;
    }
  }

  // ---------------------------------------------------------------------------
  // Attribution des modifiers (algorithmique, déterministe)
  // ---------------------------------------------------------------------------

  /// Garde le tutoriel des deux premiers niveaux **totalement pur** : aucun
  /// modifier, même environnemental, pour que le joueur intériorise la
  /// boucle de gameplay sans friction.
  static const int _tutorialMaxLevel = 2;

  /// Borne supérieure de la zone « ramp-up doux » : niveaux 3 et 4. Sur
  /// cette plage on garantit **exactement un** modifier doux pour casser
  /// la monotonie sans surprendre brutalement le joueur (jamais de fog
  /// occultant, jamais d'earthquake déstabilisant, jamais de double boss).
  static const int _gentleRampMaxLevel = 4;

  /// Altitude à partir de laquelle `thinAir` (hypoxie) s'applique.
  static const int _thinAirAltitudeMeters = 4000;

  /// Altitude à partir de laquelle `wind` devient candidat.
  static const int _windAltitudeMeters = 3000;

  /// Altitude à partir de laquelle `fog` devient candidat.
  static const int _fogAltitudeMeters = 2000;

  /// Modifiers considérés « doux » pour le ramp-up — pas de masquage
  /// durable, pas de mouvement brutal, pas d'inversion cognitive imposée.
  /// Palette des niveaux 3–4 et filet de sécurité des candidats trop rares.
  static const Set<LevelModifier> _gentleModifiers = <LevelModifier>{
    LevelModifier.wind,
    LevelModifier.shuffle,
    LevelModifier.rain,
  };

  /// Palette douce des niveaux 3–4 à partir du tier 3 : `mirage` (une
  /// lettre fausse de plus) et `spirit` (une lettre empruntée 3 s) sont des
  /// effets doux, contrairement à `reverse` (cognitif) et `fog` (masquage).
  static const Set<LevelModifier> _gentleModifiersExtended = <LevelModifier>{
    ..._gentleModifiers,
    LevelModifier.mirage,
    LevelModifier.spirit,
  };

  /// Règles :
  /// - niveaux 1-2 : aucun modifier (tutoriel strict) ;
  /// - `thinAir` : passif, additif au-dessus de 4000 m dès le niveau 3 ;
  /// - **un seul** modifier « actif » (mouvement/masquage/cognitif) par
  ///   niveau, tiré par hachage dans [candidateModifiers] et garanti
  ///   différent du modifier actif du niveau précédent (rotation) ;
  /// - boss tier ≥ 3 (même au niveau 3-4) : `shuffle` garanti **en plus**
  ///   du modifier tiré — dans la zone douce, le tirage se fait parmi
  ///   la palette douce élargie hors shuffle ;
  /// - signatures de palier (`earthquake` tectonique, `reverse`, `fog`) :
  ///   apparaissent au moins une fois sur les niveaux ≥ 5 quand le sommet
  ///   en a (voir [_activeChain] et [_signaturesFor]).
  static Set<LevelModifier> _attributeModifiers({
    required Mountain mountain,
    required int levelIndex,
    required int tier,
    required bool isBoss,
  }) {
    if (levelIndex <= _tutorialMaxLevel) {
      return const <LevelModifier>{};
    }

    final modifiers = <LevelModifier>{};
    if (mountain.altitude >= _thinAirAltitudeMeters) {
      modifiers.add(LevelModifier.thinAir);
    }

    final chain = _activeChain(mountain: mountain, tier: tier);
    modifiers.add(chain[levelIndex - _tutorialMaxLevel - 1]);

    if (_hasBossSignature(
      mountain: mountain,
      tier: tier,
      levelIndex: levelIndex,
    )) {
      modifiers.add(LevelModifier.shuffle);
    }

    return modifiers;
  }

  /// Vrai quand le niveau reçoit la signature boss (`shuffle` garanti en
  /// plus du tirage) : dernier niveau d'un sommet tier ≥ 3, y compris dans
  /// la zone douce — un sommet à 4 niveaux a droit à un vrai boss.
  static bool _hasBossSignature({
    required Mountain mountain,
    required int tier,
    required int levelIndex,
  }) {
    return tier >= 3 && levelIndex == mountain.totalLevels;
  }

  /// Chaîne des modifiers actifs des niveaux `3..totalLevels` (index 0 =
  /// niveau 3). Comme chaque tirage dépend du précédent, on rejoue toute la
  /// chaîne — au plus `totalLevels` tirages, négligeable (8 niveaux max) et
  /// parfaitement déterministe.
  ///
  /// **Signatures de palier** (voir [_signaturesFor]) : après le tirage, si
  /// une signature n'apparaît sur aucun niveau ≥ 5, on l'impose sur le
  /// premier niveau ≥ 5 encore libre (ni imposé, ni occupé par un tirage
  /// qui satisfait une signature plus prioritaire) puis on retire les
  /// niveaux suivants non verrouillés en
  /// excluant leurs voisins — l'alternance reste garantie. S'il ne reste
  /// aucun emplacement libre (sommet à 5 niveaux), la signature est
  /// abandonnée. Plusieurs passes car un retirage peut faire disparaître
  /// une signature satisfaite par tirage ; chaque imposition verrouille un
  /// emplacement, donc `signatures.length` passes suffisent.
  ///
  /// Cas particulier : sans niveau ≥ 5 (sommet à 3-4 niveaux), seule la
  /// signature tectonique s'impose, sur le boss (avec `shuffle`) — les
  /// autres signatures restent hors zone douce.
  static List<LevelModifier> _activeChain({
    required Mountain mountain,
    required int tier,
  }) {
    const firstLevel = _tutorialMaxLevel + 1;
    const firstDeepIndex = _gentleRampMaxLevel + 1 - firstLevel;
    final chain = <LevelModifier>[];
    for (var level = firstLevel; level <= mountain.totalLevels; level++) {
      chain.add(
        _drawActiveModifier(
          mountain: mountain,
          tier: tier,
          levelIndex: level,
          exclude: {if (chain.isNotEmpty) chain.last},
        ),
      );
    }

    final signatures = _signaturesFor(mountain: mountain, tier: tier);
    if (signatures.isEmpty || chain.isEmpty) return chain;

    if (chain.length <= firstDeepIndex) {
      if (signatures.first == LevelModifier.earthquake) {
        chain[chain.length - 1] = LevelModifier.earthquake;
      }
      return chain;
    }

    final locked = <int>{};
    for (var pass = 0; pass < signatures.length; pass++) {
      for (var rank = 0; rank < signatures.length; rank++) {
        final signature = signatures[rank];
        final deep = chain.sublist(firstDeepIndex);
        if (deep.contains(signature)) continue;
        // Emplacement libre : ni imposé, ni occupé par un tirage qui
        // satisfait déjà une signature plus prioritaire (une signature de
        // rang inférieur peut en revanche être écrasée — avec un seul
        // niveau ≥ 5, c'est la plus prioritaire qui entre).
        var slot = firstDeepIndex;
        while (slot < chain.length &&
            (locked.contains(slot) ||
                _isHigherSignature(signatures, chain[slot], rank))) {
          slot++;
        }
        if (slot >= chain.length) continue;
        chain[slot] = signature;
        locked.add(slot);
        _redrawAfter(
          chain: chain,
          locked: locked,
          fromIndex: slot + 1,
          mountain: mountain,
          tier: tier,
        );
      }
    }
    return chain;
  }

  /// Vrai si `value` est une signature de rang strictement plus prioritaire
  /// que `rank` (donc à protéger d'une imposition).
  static bool _isHigherSignature(
    List<LevelModifier> signatures,
    LevelModifier value,
    int rank,
  ) {
    final index = signatures.indexOf(value);
    return index != -1 && index < rank;
  }

  /// Retire les niveaux non verrouillés à partir de `fromIndex`, en excluant
  /// le modifier du niveau précédent et celui du niveau suivant s'il est
  /// verrouillé (pour ne jamais produire deux niveaux consécutifs égaux).
  static void _redrawAfter({
    required List<LevelModifier> chain,
    required Set<int> locked,
    required int fromIndex,
    required Mountain mountain,
    required int tier,
  }) {
    const firstLevel = _tutorialMaxLevel + 1;
    for (var index = fromIndex; index < chain.length; index++) {
      if (locked.contains(index)) continue;
      final nextLocked = index + 1 < chain.length && locked.contains(index + 1);
      chain[index] = _drawActiveModifier(
        mountain: mountain,
        tier: tier,
        levelIndex: index + firstLevel,
        exclude: {chain[index - 1], if (nextLocked) chain[index + 1]},
      );
    }
  }

  /// Signatures que le sommet doit montrer au moins une fois sur ses
  /// niveaux ≥ 5, par ordre de priorité :
  /// - `earthquake` : pays tectonique (tier ≥ 3) ;
  /// - `reverse` : tout sommet tier ≥ 3 (les tirages seuls n'en
  ///   produisaient qu'un sur 224 niveaux, la zone douce l'excluant) ;
  /// - `fog` : altitude ≥ 2000 m (même raison).
  /// Dès le tier 4, `reverse` passe avant `fog` ; au tier 3, `fog` d'abord
  /// (la zone des nuages est le thème du palier). Avec un seul niveau ≥ 5
  /// (sommets à 5 niveaux), seule la première signature manquante entre.
  static List<LevelModifier> _signaturesFor({
    required Mountain mountain,
    required int tier,
  }) {
    if (tier < 3) return const <LevelModifier>[];
    final reverseFirst = tier >= 4;
    final fogEligible = mountain.altitude >= _fogAltitudeMeters;
    return <LevelModifier>[
      if (_isTectonic(mountain.countryCode)) LevelModifier.earthquake,
      if (reverseFirst) LevelModifier.reverse,
      if (fogEligible) LevelModifier.fog,
      if (!reverseFirst) LevelModifier.reverse,
    ];
  }

  /// Tirage par hachage FNV-1a sur `'<mountainId>:<levelIndex>'` dans la
  /// liste triée des candidats. On avance au candidat suivant (modulo) si
  /// le résultat est dans `exclude` (voisins déjà fixés), ou vaut `shuffle`
  /// sur un boss signature (déjà garanti) et sur le niveau qui le précède
  /// (pour que la signature ne répète pas le niveau d'avant).
  static LevelModifier _drawActiveModifier({
    required Mountain mountain,
    required int tier,
    required int levelIndex,
    required Set<LevelModifier> exclude,
  }) {
    final candidates = candidateModifiers(
      mountain: mountain,
      levelIndex: levelIndex,
    );
    final excludeShuffle =
        _hasBossSignature(
          mountain: mountain,
          tier: tier,
          levelIndex: levelIndex,
        ) ||
        _hasBossSignature(
          mountain: mountain,
          tier: tier,
          levelIndex: levelIndex + 1,
        );
    final start = _stableHash('${mountain.id}:$levelIndex') % candidates.length;
    for (var offset = 0; offset < candidates.length; offset++) {
      final pick = candidates[(start + offset) % candidates.length];
      if (exclude.contains(pick)) continue;
      if (excludeShuffle && pick == LevelModifier.shuffle) continue;
      return pick;
    }
    // Inatteignable : au plus 3 exclusions (précédent, suivant verrouillé,
    // shuffle) pour ≥ 5 candidats dès le tier 3, et ≤ 2 exclusions pour
    // les 3 candidats doux des tiers 1-2 (jamais de voisin verrouillé).
    return candidates[start];
  }

  // ---------------------------------------------------------------------------
  // Structure du tour (LevelKind) et embranchement « voie exposée »
  // ---------------------------------------------------------------------------

  /// Premier niveau éligible à une structure non classique (rafale / duo).
  static const int _firstVariedLevel = _tutorialMaxLevel + 1;

  /// Tier minimal pour un boss aveugle (l'énigme s'efface).
  static const int _blindBossMinTier = 3;

  /// Tier minimal pour un duo (deux mots dans une grille) : jamais en zone
  /// d'amorçage, où l'union de deux pools serait déjà trop dense.
  static const int _duoMinTier = 2;

  /// Modulo du tirage par hachage : 0 → rafale, 1 → duo, 2-4 → classique.
  static const int _kindDrawModulo = 5;
  static const int _kindDrawRafale = 0;
  static const int _kindDrawDuo = 1;

  /// Niveau de l'embranchement « voie exposée ».
  static const int _branchingLevel = 3;

  /// Taille minimale d'un sommet pour proposer l'embranchement.
  static const int _branchingMinTotalLevels = 5;

  /// Facteurs de la voie exposée.
  static const double _exposedTimerFactor = 0.8;
  static const double _exposedCaurisFactor = 2;

  /// Structure de chaque niveau `1..totalLevels` (index 0 = niveau 1).
  ///
  /// Règles :
  /// - niveaux 1-2 : [LevelKind.classic] (tutoriel) ;
  /// - boss tier ≥ 3 : [LevelKind.blindBoss] ;
  /// - sinon, dès le niveau 3, hachage FNV-1a de `'<mountainId>:kind:<n>'`
  ///   modulo 5 → 0 = rafale, 1 = duo (tier ≥ 2 seulement), autres =
  ///   classique ;
  /// - jamais deux rafale/duo consécutifs : si le précédent est rafale ou
  ///   duo, on force classique. Le boss aveugle ne compte pas dans cette
  ///   alternance (un niveau rafale/duo peut le précéder).
  static List<LevelKind> _kindChain({
    required Mountain mountain,
    required int tier,
  }) {
    final total = mountain.totalLevels;
    final chain = List<LevelKind>.filled(total, LevelKind.classic);
    final hasBlindBoss = tier >= _blindBossMinTier;
    if (hasBlindBoss) chain[total - 1] = LevelKind.blindBoss;

    for (var level = _firstVariedLevel; level <= total; level++) {
      if (hasBlindBoss && level == total) break;
      if (chain[level - 2].isMultiWord) continue;
      final draw = _stableHash('${mountain.id}:kind:$level') % _kindDrawModulo;
      if (draw == _kindDrawRafale) {
        chain[level - 1] = LevelKind.rafale;
      } else if (draw == _kindDrawDuo && tier >= _duoMinTier) {
        chain[level - 1] = LevelKind.duo;
      }
    }
    return chain;
  }

  static List<LevelModifier> _sorted(Iterable<LevelModifier> modifiers) {
    return modifiers.toList(growable: false)
      ..sort((a, b) => a.index.compareTo(b.index));
  }

  /// Codes pays à géologie tectonique active (Rift Valley est-africain,
  /// volcanisme, chaînes en formation). Liste non exhaustive mais couvre
  /// les sommets signature du jeu : Mt Cameroun, Karthala, Nyiragongo,
  /// Kilimandjaro, Mt Kenya, etc.
  static bool _isTectonic(String countryCode) {
    const tectonicCountries = <String>{
      'CM', // Mont Cameroun (volcan actif)
      'KM', // Karthala (volcan actif)
      'CD', // Nyiragongo / Rwenzori (Rift + volcans)
      'RW', // Karisimbi (Rift)
      'UG', // Rwenzori (Rift)
      'KE', // Mt Kenya (Rift)
      'TZ', // Kilimandjaro, Ol Doinyo Lengai (Rift)
      'ET', // Ras Dashen (Rift)
      'ER', // Dahlak / Rift
      'DJ', // Mousa Ali (Rift)
    };
    return tectonicCountries.contains(countryCode);
  }

  /// Hash stable indépendant de l'implémentation Object.hashCode (qui
  /// varie d'un run à l'autre). FNV-1a 32-bit suffit largement pour notre
  /// usage (équiprobabilité ~uniforme sur quelques milliers de niveaux).
  static int _stableHash(String input) {
    const fnvOffset = 0x811c9dc5;
    const fnvPrime = 0x01000193;
    var hash = fnvOffset;
    for (final code in input.codeUnits) {
      hash ^= code;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash;
  }
}
