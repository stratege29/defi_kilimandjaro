import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';
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
/// Modèle :
/// - Le **tier** (1–5) vient de l'altitude (palier validé PO option B).
/// - Le **bucket de longueur** s'aligne sur le tier (préférence) — la
///   sélection de devinette gère le fallback si le pool est trop maigre.
/// - Le **timer** est adaptatif : `15 + 3·wordLen + 2·tier`, multiplié par
///   0,8 si `thinAir` est actif. On utilise la longueur attendue dérivée
///   du bucket pour pré-calculer un timer cohérent.
/// - Le **multiplicateur cauris** scale en cinq paliers (1.0, 1.3, 1.6,
///   2.0, 2.5) pour récompenser la difficulté.
/// - Les **modifiers** sont attribués algorithmiquement par règles
///   thématiques (altitude, géologie via [Mountain.shape], etc.).
/// - Le flag **isBoss** marque la dernière énigme d'une montagne
///   (préparation S4).
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
    final bucket = _wordLengthBucketForTier(tier);
    final isBoss = clampedLevel == mountain.totalLevels;
    final modifiers = _attributeModifiers(
      mountain: mountain,
      levelIndex: clampedLevel,
      tier: tier,
      isBoss: isBoss,
    );

    // Longueur de mot attendue pour calibrer le timer. On prend la borne
    // basse du bucket — c'est conservateur (plus de temps), évite les
    // niveaux étouffants si la sélection finit par tomber sur un mot
    // plus court que le bucket cible.
    final expectedWordLen = _expectedWordLengthForBucket(bucket);
    var timer = 15 + 3 * expectedWordLen + 2 * tier;
    if (modifiers.contains(LevelModifier.thinAir)) {
      timer = (timer * 0.8).round();
    }

    return LevelDifficultyConfig(
      difficultyTier: tier,
      wordLengthBucket: bucket,
      timerSeconds: timer,
      caurisMultiplier: _caurisMultiplierForTier(tier),
      distractorCount: _distractorCountForTier(tier),
      modifiers: modifiers,
      isBoss: isBoss,
    );
  }

  /// Config pour mode Hub (sans contexte montagne). Ne devrait normalement
  /// pas exister mais le routeur peut atterrir sur `/game` sans `mountainId`
  /// — on tombe sur la config fallback la plus douce.
  static LevelDifficultyConfig fallback() => LevelDifficultyConfig.fallback;

  // ---------------------------------------------------------------------------
  // Mapping primitives
  // ---------------------------------------------------------------------------

  static int _tierForAltitude(int altitudeMeters) {
    if (altitudeMeters < 500) return 1;
    if (altitudeMeters < 1500) return 2;
    if (altitudeMeters < 3000) return 3;
    if (altitudeMeters < 4500) return 4;
    return 5;
  }

  static int _wordLengthBucketForTier(int tier) {
    // Mapping 1:1 simple — la sélection de devinette gère le fallback
    // ±1 / ±2 si le pool de cette taille est trop maigre.
    return tier;
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

  /// Nombre de lettres parasites ajoutées à la grille selon le tier.
  /// Courbe douce : 0 en zone tutoriel (tier 1-2), puis +1 par palier.
  /// Au tier 5, un mot de 6 lettres affiche 9 cases (6 + 3 distracteurs).
  static int _distractorCountForTier(int tier) {
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

  static double _caurisMultiplierForTier(int tier) {
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

  static Set<LevelModifier> _attributeModifiers({
    required Mountain mountain,
    required int levelIndex,
    required int tier,
    required bool isBoss,
  }) {
    final modifiers = <LevelModifier>{};

    // thinAir : timer accéléré au-dessus de 4000 m (effet hypoxie).
    // Passif (pas de modifier visuel) — cohabite avec tout.
    if (mountain.altitude >= 4000) {
      modifiers.add(LevelModifier.thinAir);
    }

    // Règles **exclusives** pour les modifiers de mouvement/masquage :
    // un niveau ne reçoit qu'un seul d'entre eux pour éviter la surcharge
    // visuelle (4 modifiers simultanés = grille illisible).
    //
    // Priorité :
    // 1. earthquake — montagnes en pays tectonique (Rift, volcans actifs).
    //    Match thématique fort, on l'attribue dès qu'éligible.
    // 2. wind — altitude ≥ 3000 m sur sommets non-tectoniques.
    //    Les vents catabatiques dominent à cette altitude.
    // 3. fog — zone des nuages (2000–3000 m) sur sommets non-tectoniques.
    //    Calme atmosphérique, brouillard plus que tremblement.
    final isTectonic = _isTectonic(mountain.countryCode);
    if (isTectonic && tier >= 3) {
      modifiers.add(LevelModifier.earthquake);
    } else if (mountain.altitude >= 3000) {
      modifiers.add(LevelModifier.wind);
    } else if (mountain.altitude >= 2000) {
      modifiers.add(LevelModifier.fog);
    }

    // reverse : à partir du tier 3, attribué de façon déterministe à
    // certains niveaux. Hash stable sur (mountainId, levelIndex) pour
    // que l'attribution ne varie pas d'un boot à l'autre. ~1 niveau sur
    // 3 au tier 3, ~1 sur 2 au tier 4+.
    if (tier >= 3) {
      final salt = _stableHash('${mountain.id}:$levelIndex');
      final modulus = tier >= 4 ? 2 : 3;
      if (salt % modulus == 0) {
        modifiers.add(LevelModifier.reverse);
      }
    }

    // shuffle : signature des boss tier ≥ 3. Re-mélange complet de la
    // grille toutes les 15 s pour casser la mémoire spatiale du joueur.
    if (isBoss && tier >= 3) {
      modifiers.add(LevelModifier.shuffle);
    }

    // Boss tier ≥ 3 : on garantit qu'au moins UN modifier sortant est
    // présent pour donner du sel à la finale (au minimum reverse si rien
    // d'autre attribué par les règles ci-dessus). En S3+ on enrichira
    // (drumbeat, ice, etc.).
    //
    // Pourquoi pas tier 1-2 : ces paliers servent de zone tutoriel
    // implicite (apprentissage du gameplay de base). Le 2e niveau du
    // jeu — boss Red Rocks — doit rester un boss "soft" sans inversion
    // cognitive pour ne pas effrayer le joueur dès la sortie du splash.
    if (isBoss && tier >= 3 && modifiers.length <= 1) {
      // Si on n'a que `shuffle` (ajouté juste au-dessus), on ajoute reverse
      // pour le double-pic boss. La condition `length <= 1` couvre les
      // boss tier 3 avec uniquement shuffle (zones non-tectoniques,
      // < 2000 m donc pas fog/wind/earthquake/thinAir).
      modifiers.add(LevelModifier.reverse);
    }

    return modifiers;
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
