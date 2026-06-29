import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:equatable/equatable.dart';

/// Snapshot persistant de la progression du joueur.
///
/// Persisté via shared_preferences (Phase 2.3, v1).
/// Évolution v2 : sync Firestore quand authentifié (Phase 4 + multijoueur).
class PlayerProgress extends Equatable {
  const PlayerProgress({
    required this.cauris,
    required this.completedLevelsByMountain,
    required this.totalLevelsCompleted,
    required this.dailyStreak,
    required this.ownedPacks,
    this.activePackId,
    this.lastPlayDate,
    this.lastStreakClaimDate,
    this.installDate,
    this.consecutiveFailures = 0,
    this.noAdsPurchased = false,
    this.starterPackPurchased = false,
    this.recentDevinetteIds = const <String>[],
    this.freePackChosen,
    this.starsByLevel = const <String, int>{},
    this.failsByLevel = const <String, int>{},
    this.dailyChallengeStreak = 0,
    this.lastDailyChallengeDate,
    this.freezeTokens = 0,
    this.lastFreezeUsedDate,
    this.freeHintAvailable = false,
    this.lastFreeHintGrantedDate,
    this.encounteredModifiers = const <LevelModifier>{},
    this.consecutiveLossesByDevinetteId = const <String, int>{},
    this.rewardedDevinetteIds = const <String>{},
  });

  /// État initial pour un nouveau joueur.
  ///
  /// [cauris] : solde de bienvenue. Default 120 (= `GameEconomyConfig
  /// .defaults.initialCauris`) ; le `PlayerProgressNotifier` override avec
  /// la valeur Remote Config `eco_initial_cauris` quand il instancie un
  /// profil "neuf".
  ///
  /// Aucun pack possédé tant que l'onboarding n'a pas tranché : c'est le
  /// flow "choisir mon pack gratuit" qui appelle [PlayerProgressNotifier
  /// .chooseFreePack] et initialise `ownedPacks + freePackChosen` de
  /// façon atomique.
  factory PlayerProgress.initial({int cauris = 120}) => PlayerProgress(
    cauris: cauris,
    completedLevelsByMountain: const <String, int>{},
    totalLevelsCompleted: 0,
    dailyStreak: 0,
    ownedPacks: const <String>{},
  );

  factory PlayerProgress.fromJson(Map<String, dynamic> json) {
    final ownedPacks =
        ((json['owned_packs'] as List<dynamic>?) ?? const <dynamic>[])
            .map((e) => e.toString())
            .toSet();
    final freePack = json['free_pack_chosen'] as String?;
    final parsedMix = PackMix.tryFromJson(json['pack_mix']);

    // Pack actif : champ explicite v2, sinon dérivé du mix (pack dominant)
    // ou du pack gratuit — rétrocompat des profils v1.
    final activePackId = (json['active_pack_id'] as String?) ??
        _dominantPackOf(parsedMix) ??
        freePack;

    // Migration v1 → v2 : avant la progression par pack, les clés de
    // progression étaient globales (`mountainId`, `mountainId#levelIndex`).
    // En v2 elles sont préfixées par le pack (`packId::…`). On rattache la
    // progression existante au pack actif/gratuit (décision produit).
    final schemaVersion = (json['schema_version'] as int?) ?? 1;
    final migrationPack = (activePackId != null &&
            activePackId.isNotEmpty &&
            activePackId != packPendingSentinel)
        ? activePackId
        : null;

    Map<String, int> readMap(String key) =>
        ((json[key] as Map<String, dynamic>?) ?? <String, dynamic>{})
            .map((k, v) => MapEntry(k, v as int));

    Map<String, int> migrateKeys(Map<String, int> m) {
      if (schemaVersion >= 2 || migrationPack == null || m.isEmpty) return m;
      return m.map((k, v) => MapEntry('$migrationPack::$k', v));
    }

    return PlayerProgress(
      // Tolère l'ancienne clé `coins` pour ne pas perdre le solde des
      // joueurs existants après le rebranding Cauris.
      cauris: (json['cauris'] as int?) ?? (json['coins'] as int?) ?? 120,
      completedLevelsByMountain: migrateKeys(readMap('levels')),
      totalLevelsCompleted: (json['total'] as int?) ?? 0,
      dailyStreak: (json['streak'] as int?) ?? 0,
      lastPlayDate: json['last_play'] == null
          ? null
          : DateTime.tryParse(json['last_play'] as String),
      lastStreakClaimDate: json['last_streak_claim'] == null
          ? null
          : DateTime.tryParse(json['last_streak_claim'] as String),
      installDate: json['install_date'] == null
          ? null
          : DateTime.tryParse(json['install_date'] as String),
      consecutiveFailures: (json['consecutive_failures'] as int?) ?? 0,
      noAdsPurchased: (json['no_ads'] as bool?) ?? false,
      starterPackPurchased: (json['starter_pack'] as bool?) ?? false,
      recentDevinetteIds:
          ((json['recent_devinettes'] as List<dynamic>?) ?? <dynamic>[])
              .map((e) => e as String)
              .toList(growable: false),
      ownedPacks: ownedPacks,
      freePackChosen: freePack,
      activePackId: activePackId,
      starsByLevel: migrateKeys(readMap('stars_by_level')),
      failsByLevel: migrateKeys(readMap('fails_by_level')),
      dailyChallengeStreak: (json['daily_challenge_streak'] as int?) ?? 0,
      lastDailyChallengeDate: json['last_daily_challenge_date'] == null
          ? null
          : DateTime.tryParse(json['last_daily_challenge_date'] as String),
      freezeTokens: (json['freeze_tokens'] as int?) ?? 0,
      lastFreezeUsedDate: json['last_freeze_used_date'] == null
          ? null
          : DateTime.tryParse(json['last_freeze_used_date'] as String),
      freeHintAvailable: (json['free_hint_available'] as bool?) ?? false,
      lastFreeHintGrantedDate: json['last_free_hint_granted_date'] == null
          ? null
          : DateTime.tryParse(json['last_free_hint_granted_date'] as String),
      encounteredModifiers: _parseEncounteredModifiers(
        json['encountered_modifiers'],
      ),
      consecutiveLossesByDevinetteId:
          ((json['consecutive_losses_by_devinette']
                      as Map<String, dynamic>?) ??
                  <String, dynamic>{})
              .map((k, v) => MapEntry(k, v as int)),
      rewardedDevinetteIds:
          ((json['rewarded_devinettes'] as List<dynamic>?) ?? <dynamic>[])
              .map((e) => e.toString())
              .toSet(),
    );
  }

  /// Parse la liste persistée d'enum modifiers (en `name` String) vers le
  /// Set typé. Tolère les noms inconnus (ex. retrait/renommage futur d'un
  /// modifier dans l'enum) en les ignorant — la persistance ne doit pas
  /// crasher si le schéma évolue.
  static Set<LevelModifier> _parseEncounteredModifiers(dynamic raw) {
    if (raw is! List) return const <LevelModifier>{};
    final result = <LevelModifier>{};
    for (final entry in raw) {
      final name = entry?.toString();
      if (name == null || name.isEmpty) continue;
      for (final m in LevelModifier.values) {
        if (m.name == name) {
          result.add(m);
          break;
        }
      }
    }
    return result;
  }

  /// Sentinelle utilisée par le mix par défaut avant choix du pack gratuit.
  /// Le tirage doit refuser ce token : l'app ne doit pas démarrer une partie
  /// avant que l'utilisateur ait choisi son pack gratuit. Ne doit jamais
  /// être passée à un repository de devinettes.
  static const String packPendingSentinel = '_pending_';

  /// Extrait le pack dominant (poids max) d'un ancien `pack_mix` persisté —
  /// sert à dériver le `activePackId` v2 depuis un profil v1 qui ne stockait
  /// qu'un mix pondéré. `null` si le mix est absent, vide ou sentinelle.
  static String? _dominantPackOf(PackMix? mix) {
    if (mix == null || mix.packIds.isEmpty) return null;
    final weights = mix.weights;
    String? best;
    var bestWeight = -1.0;
    weights.forEach((packId, weight) {
      if (packId == packPendingSentinel) return;
      if (weight > bestWeight) {
        bestWeight = weight;
        best = packId;
      }
    });
    return best;
  }

  /// Solde de Cauris de Sagesse (cauris = monnaie shell d'Afrique de l'Ouest).
  final int cauris;

  /// Niveaux complétés par montagne (mountainId → count).
  final Map<String, int> completedLevelsByMountain;

  /// Total cumul de niveaux gagnés (utile pour titres honorifiques).
  final int totalLevelsCompleted;

  /// Streak quotidienne (jours consécutifs où le joueur a réclamé son
  /// bonus quotidien). Reset à 1 quand le joueur saute un jour, capé par
  /// la longueur de `GameEconomyConfig.streakRewards` côté UI.
  final int dailyStreak;

  /// Dernière date de jeu (jour calendaire, sans heure).
  final DateTime? lastPlayDate;

  /// Date du **dernier claim** du bonus streak quotidien. `null` tant que
  /// l'utilisateur n'a jamais réclamé. Différent de [lastPlayDate] : un
  /// joueur peut jouer plusieurs fois dans la journée mais ne réclame son
  /// bonus qu'une fois. Garde-fou anti double-claim.
  final DateTime? lastStreakClaimDate;

  /// Compteur d'échecs consécutifs (reset à chaque victoire).
  /// Sert de trigger pour l'interstitielle (cf. plan.md §4 — 1 sur 3 échecs).
  final int consecutiveFailures;

  /// Achat non-consumable "Supprimer les pubs" (4,99 €).
  final bool noAdsPurchased;

  /// Achat one-time du **Starter Pack** (2,99 € — 350 cauris boost).
  /// Visible dans la boutique uniquement les 48h qui suivent
  /// [installDate]. Une fois acheté ou expiré, la carte disparaît.
  final bool starterPackPurchased;

  /// Date d'installation (= 1er lancement détecté). `null` pour les
  /// profils existants au moment du déploiement de Phase 4 — ils
  /// n'auront pas de starter pack puisque la fenêtre H+48 ne peut
  /// plus s'appliquer (pas de point de référence).
  final DateTime? installDate;

  /// Ids des dernières devinettes jouées (les plus récentes en tête).
  /// Limité à 5 entrées dans le notifier. Utilisé pour exclure ces ids
  /// du tirage `randomFromWorldExcluding` → évite la frustration de
  /// retomber sur la même devinette deux fois de suite.
  final List<String> recentDevinetteIds;

  /// Packs thématiques possédés par le joueur (inclut systématiquement
  /// le pack gratuit choisi à l'onboarding).
  ///
  /// Set immuable par contrat — mutations via `copyWith` + persistance.
  final Set<String> ownedPacks;

  /// Pack gratuit choisi au 1er lancement. **Immuable une fois défini**
  /// (règle produit verrouillée par le PO). `null` tant que l'onboarding
  /// n'a pas tranché.
  final String? freePackChosen;

  /// Pack **actif** (modèle « pack actif unique ») : c'est lui qui alimente
  /// le tirage des devinettes ET la grimpe de montagnes courante. Changer de
  /// pack actif = changer de grimpe (progression par pack). `null` tant que
  /// l'onboarding n'a pas tranché → on retombe sur [freePackChosen].
  final String? activePackId;

  /// Pack actif résolu pour la construction des clés de progression. Vide
  /// (`''`) tant qu'aucun pack n'est choisi — aucune partie ne devrait avoir
  /// lieu dans cet état, mais les clés restent inoffensives.
  String get _activePackForKeys {
    final a = activePackId;
    if (a != null && a.isNotEmpty && a != packPendingSentinel) return a;
    final f = freePackChosen;
    if (f != null && f.isNotEmpty) return f;
    if (ownedPacks.isNotEmpty) return ownedPacks.first;
    return '';
  }

  /// Pondération active dérivée pour le tirage des devinettes — toujours
  /// mono-pack (modèle « pack actif unique »). Retombe sur le sentinelle
  /// `_pending_` tant qu'aucun pack n'est choisi, ce que le tirage refuse.
  PackMix get activePackMix {
    final resolved = _activePackForKeys;
    return PackMix.single(resolved.isEmpty ? packPendingSentinel : resolved);
  }

  /// Clé de progression « niveaux complétés » du pack actif sur [mountainId].
  String mountainProgressKey(String mountainId) =>
      '$_activePackForKeys::$mountainId';

  /// Clé de progression niveau (étoiles / échecs) du pack actif.
  String levelKey(String mountainId, int levelIndex) =>
      '$_activePackForKeys::$mountainId#$levelIndex';

  /// Étoiles obtenues par niveau (clé = `"$packId::$mountainId#$levelIndex"`,
  /// 1-3). Garde toujours le meilleur score d'un re-run (cf. `mergeStars`
  /// dans `PlayerProgressNotifier.recordWin`). Niveaux non joués absents de
  /// la map.
  final Map<String, int> starsByLevel;

  /// Compteur d'échecs **consécutifs sur le même niveau** (clé =
  /// `"$packId::$mountainId#$levelIndex"`).
  ///
  /// Distinct de [consecutiveFailures] (qui est global et sert au
  /// trigger des interstitielles). Ici on suit niveau par niveau pour :
  /// - décider si la réponse doit être révélée gratuitement (≥ 3 échecs
  ///   consécutifs sur le même niveau, anti-blocage en zone T2+) ;
  /// - reset à la victoire de **ce** niveau précis.
  ///
  /// Niveaux jamais ratés absents de la map.
  final Map<String, int> failsByLevel;

  /// Compteur de jours consécutifs où le joueur a réussi le défi du jour.
  /// Distinct de [dailyStreak] (qui suit l'ouverture d'app, gérée par
  /// `DailyStreakService`). Reset à 0 sur échec ou skip d'un jour.
  final int dailyChallengeStreak;

  /// Jour calendaire local (heures à 0) du dernier daily challenge joué.
  /// Sert à :
  /// - détecter si le défi du jour a déjà été tenté aujourd'hui
  ///   (1 essai/jour) ;
  /// - détecter un day-skip (lastDate < today - 1 jour ⇒ streak cassé).
  /// Null tant que le joueur n'a jamais joué de daily.
  final DateTime? lastDailyChallengeDate;

  /// Nombre de **freeze tokens** en stock — chaque token consomme
  /// automatiquement un day-skip détecté (cf. `DailyChallengeService.
  /// maxFreezeTokens` pour le plafond). Achetable contre cauris
  /// (`DailyChallengeService.freezeTokenCost`). Sink économique majeur
  /// + valeur perçue très forte pour les joueurs assidus.
  final int freezeTokens;

  /// Jour calendaire local du dernier freeze token consommé. Sert au
  /// badge UI « ❄️ Série sauvée par freeze ». Null tant qu'aucun freeze
  /// n'a été appliqué.
  final DateTime? lastFreezeUsedDate;

  /// True quand un **indice gratuit** est dispo (octroyé au 1er accès
  /// du jour calendaire local). Stack max 1 — un free hint non utilisé
  /// est perdu au lendemain quand le nouveau cycle d'octroi tourne. Le
  /// `PlayerProgressNotifier.spendOnHint` le consomme en priorité avant
  /// de débiter les cauris.
  final bool freeHintAvailable;

  /// Jour calendaire local du dernier octroi d'indice gratuit. Sert au
  /// gating idempotent du daily grant (cf. `claimFreeHintIfDue`). Null
  /// tant qu'aucun octroi n'a eu lieu.
  final DateTime? lastFreeHintGrantedDate;

  /// Set des modifiers déjà rencontrés au moins une fois par le joueur.
  /// Utilisé par l'overlay « Le Griot t'avertit » pour n'afficher la
  /// description longue qu'à la première rencontre d'un modifier ; aux
  /// rencontres suivantes seul le nom apparaît (friction maîtrisée).
  ///
  /// Persisté en JSON sous forme de liste de `name` enum. Mots inconnus
  /// (modifier retiré ou renommé dans une future version) sont silencieusement
  /// ignorés au load — cf. [_parseEncounteredModifiers].
  final Set<LevelModifier> encounteredModifiers;

  /// Nombre de défaites consécutives par devinette en mode **solo**.
  ///
  /// Clé : `devinetteId`. Reset à zéro :
  /// - après une victoire sur cette devinette (cf.
  ///   `PlayerProgressNotifier.recordWin` — étendu à passer un
  ///   `devinetteId`) ;
  /// - après un skip gratuit anti-tilt (cf.
  ///   `PlayerProgressNotifier.recordSoloSkipFree`) ;
  /// - lors d'un reset complet.
  ///
  /// Sert exclusivement le mécanisme d'anti-tilt : au seuil
  /// `kFreeSkipLossThreshold` (3), l'UI d'échec propose un bouton
  /// "Passer (gratuit)" qui débloque la frustration sans pénalité
  /// supplémentaire.
  ///
  /// **Solo uniquement** — le duel 1v1 a sa propre logique de fin de
  /// manche sans cauris ni pub (cf. CLAUDE.md).
  final Map<String, int> consecutiveLossesByDevinetteId;

  /// Devinettes dont la **récompense en cauris a déjà été consommée** : soit
  /// gagnées une première fois, soit dont la réponse a été révélée (reveal
  /// payant / auto-reveal anti-blocage). Rejouer une devinette de cet
  /// ensemble ne crédite plus aucun cauri (anti-farm). La progression
  /// (niveau conquis, étoiles) reste possible — seul le gain monétaire est
  /// bloqué. Union au merge cloud (historique best-of-both, jamais perdu).
  final Set<String> rewardedDevinetteIds;

  /// True quand l'utilisateur a déjà choisi son pack gratuit (gating
  /// d'onboarding).
  bool get hasChosenFreePack => freePackChosen != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    // v2 : progression par pack (clés `packId::…`). L'absence de ce champ
    // au load signale un profil v1 à migrer (cf. [PlayerProgress.fromJson]).
    'schema_version': 2,
    'cauris': cauris,
    'levels': completedLevelsByMountain,
    'total': totalLevelsCompleted,
    'streak': dailyStreak,
    'last_play': lastPlayDate?.toIso8601String(),
    if (lastStreakClaimDate != null)
      'last_streak_claim': lastStreakClaimDate!.toIso8601String(),
    if (installDate != null) 'install_date': installDate!.toIso8601String(),
    if (starterPackPurchased) 'starter_pack': starterPackPurchased,
    'consecutive_failures': consecutiveFailures,
    'no_ads': noAdsPurchased,
    'recent_devinettes': recentDevinetteIds,
    'owned_packs': ownedPacks.toList(growable: false),
    if (freePackChosen != null) 'free_pack_chosen': freePackChosen,
    if (activePackId != null) 'active_pack_id': activePackId,
    // Conservé pour rétrocompat : une ancienne version de l'app (ou le merge
    // cloud d'un appareil v1) lit encore `pack_mix`. Toujours mono-pack.
    'pack_mix': activePackMix.toJson(),
    if (starsByLevel.isNotEmpty) 'stars_by_level': starsByLevel,
    if (failsByLevel.isNotEmpty) 'fails_by_level': failsByLevel,
    if (dailyChallengeStreak > 0)
      'daily_challenge_streak': dailyChallengeStreak,
    if (lastDailyChallengeDate != null)
      'last_daily_challenge_date': lastDailyChallengeDate!.toIso8601String(),
    if (freezeTokens > 0) 'freeze_tokens': freezeTokens,
    if (lastFreezeUsedDate != null)
      'last_freeze_used_date': lastFreezeUsedDate!.toIso8601String(),
    if (freeHintAvailable) 'free_hint_available': freeHintAvailable,
    if (lastFreeHintGrantedDate != null)
      'last_free_hint_granted_date':
          lastFreeHintGrantedDate!.toIso8601String(),
    if (encounteredModifiers.isNotEmpty)
      'encountered_modifiers':
          encounteredModifiers.map((m) => m.name).toList(growable: false),
    if (consecutiveLossesByDevinetteId.isNotEmpty)
      'consecutive_losses_by_devinette': consecutiveLossesByDevinetteId,
    if (rewardedDevinetteIds.isNotEmpty)
      'rewarded_devinettes': rewardedDevinetteIds.toList(growable: false),
  };

  /// Combien de niveaux complétés sur cette montagne **pour le pack actif**.
  int levelsOn(String mountainId) =>
      completedLevelsByMountain[mountainProgressKey(mountainId)] ?? 0;

  /// Nombre d'étoiles obtenues sur un niveau précis (0 si jamais joué),
  /// **pour le pack actif**.
  int starsOnLevel({required String mountainId, required int levelIndex}) {
    return starsByLevel[levelKey(mountainId, levelIndex)] ?? 0;
  }

  /// Compteur d'échecs consécutifs sur ce niveau précis (0 si jamais raté
  /// ou si déjà gagné depuis le dernier échec), **pour le pack actif**.
  /// Reset à 0 dans `PlayerProgressNotifier.recordWin`.
  int failsOnLevel({required String mountainId, required int levelIndex}) {
    return failsByLevel[levelKey(mountainId, levelIndex)] ?? 0;
  }

  /// Somme des étoiles obtenues sur tous les niveaux joués **du pack actif**.
  /// Dérivé à la volée depuis [starsByLevel] en ne retenant que les clés
  /// préfixées par le pack actif (pas de persistance dédiée — évite la
  /// désynchro avec le détail). Sert au star-gate **par pack** (cf.
  /// `StarGate.computeUnlockedTier`).
  int get totalStars {
    final prefix = '$_activePackForKeys::';
    if (_activePackForKeys.isEmpty) return 0;
    return starsByLevel.entries
        .where((e) => e.key.startsWith(prefix))
        .fold<int>(0, (sum, e) => sum + e.value);
  }

  /// Nombre de défaites consécutives en cours sur une devinette donnée
  /// (0 si jamais perdu ou si reset suite à victoire/skip). Sert au
  /// déclenchement du skip gratuit anti-tilt au seuil
  /// `kFreeSkipLossThreshold`.
  int consecutiveLossesOn(String devinetteId) =>
      consecutiveLossesByDevinetteId[devinetteId] ?? 0;

  /// True si la récompense cauris de cette devinette a déjà été consommée
  /// (gagnée une fois, ou réponse révélée). Sert au gating anti-farm du
  /// reward solo : une devinette déjà récompensée ne re-crédite plus.
  bool isDevinetteRewarded(String devinetteId) =>
      rewardedDevinetteIds.contains(devinetteId);

  PlayerProgress copyWith({
    int? cauris,
    Map<String, int>? completedLevelsByMountain,
    int? totalLevelsCompleted,
    int? dailyStreak,
    DateTime? lastPlayDate,
    DateTime? lastStreakClaimDate,
    DateTime? installDate,
    int? consecutiveFailures,
    bool? noAdsPurchased,
    bool? starterPackPurchased,
    List<String>? recentDevinetteIds,
    Set<String>? ownedPacks,
    String? freePackChosen,
    String? activePackId,
    Map<String, int>? starsByLevel,
    int? dailyChallengeStreak,
    DateTime? lastDailyChallengeDate,
    Map<String, int>? failsByLevel,
    int? freezeTokens,
    DateTime? lastFreezeUsedDate,
    bool? freeHintAvailable,
    DateTime? lastFreeHintGrantedDate,
    Set<LevelModifier>? encounteredModifiers,
    Map<String, int>? consecutiveLossesByDevinetteId,
    Set<String>? rewardedDevinetteIds,
  }) {
    return PlayerProgress(
      cauris: cauris ?? this.cauris,
      completedLevelsByMountain:
          completedLevelsByMountain ?? this.completedLevelsByMountain,
      totalLevelsCompleted: totalLevelsCompleted ?? this.totalLevelsCompleted,
      dailyStreak: dailyStreak ?? this.dailyStreak,
      lastPlayDate: lastPlayDate ?? this.lastPlayDate,
      lastStreakClaimDate: lastStreakClaimDate ?? this.lastStreakClaimDate,
      installDate: installDate ?? this.installDate,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      noAdsPurchased: noAdsPurchased ?? this.noAdsPurchased,
      starterPackPurchased:
          starterPackPurchased ?? this.starterPackPurchased,
      recentDevinetteIds: recentDevinetteIds ?? this.recentDevinetteIds,
      ownedPacks: ownedPacks ?? this.ownedPacks,
      freePackChosen: freePackChosen ?? this.freePackChosen,
      activePackId: activePackId ?? this.activePackId,
      starsByLevel: starsByLevel ?? this.starsByLevel,
      failsByLevel: failsByLevel ?? this.failsByLevel,
      dailyChallengeStreak:
          dailyChallengeStreak ?? this.dailyChallengeStreak,
      lastDailyChallengeDate:
          lastDailyChallengeDate ?? this.lastDailyChallengeDate,
      freezeTokens: freezeTokens ?? this.freezeTokens,
      lastFreezeUsedDate:
          lastFreezeUsedDate ?? this.lastFreezeUsedDate,
      freeHintAvailable: freeHintAvailable ?? this.freeHintAvailable,
      lastFreeHintGrantedDate:
          lastFreeHintGrantedDate ?? this.lastFreeHintGrantedDate,
      encounteredModifiers:
          encounteredModifiers ?? this.encounteredModifiers,
      consecutiveLossesByDevinetteId: consecutiveLossesByDevinetteId ??
          this.consecutiveLossesByDevinetteId,
      rewardedDevinetteIds:
          rewardedDevinetteIds ?? this.rewardedDevinetteIds,
    );
  }

  @override
  List<Object?> get props => [
    cauris,
    completedLevelsByMountain,
    totalLevelsCompleted,
    dailyStreak,
    lastPlayDate,
    lastStreakClaimDate,
    installDate,
    consecutiveFailures,
    noAdsPurchased,
    starterPackPurchased,
    recentDevinetteIds,
    ownedPacks,
    freePackChosen,
    activePackId,
    starsByLevel,
    failsByLevel,
    dailyChallengeStreak,
    lastDailyChallengeDate,
    freezeTokens,
    lastFreezeUsedDate,
    freeHintAvailable,
    lastFreeHintGrantedDate,
    encounteredModifiers,
    consecutiveLossesByDevinetteId,
    rewardedDevinetteIds,
  ];
}
