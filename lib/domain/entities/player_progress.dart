import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:equatable/equatable.dart';

/// Snapshot persistant de la progression du joueur.
///
/// Persisté via shared_preferences (Phase 2.3, v1).
/// Évolution v2 : sync Firestore quand authentifié (Phase 4 + multijoueur).
class PlayerProgress extends Equatable {
  PlayerProgress({
    required this.cauris,
    required this.completedLevelsByMountain,
    required this.totalLevelsCompleted,
    required this.dailyStreak,
    required this.ownedPacks,
    PackMix? activePackMix,
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
  }) : activePackMix =
           activePackMix ?? _defaultPackMix(ownedPacks, freePackChosen);

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
    activePackMix: _placeholderMix,
  );

  factory PlayerProgress.fromJson(Map<String, dynamic> json) {
    final ownedPacks =
        ((json['owned_packs'] as List<dynamic>?) ?? const <dynamic>[])
            .map((e) => e.toString())
            .toSet();
    final freePack = json['free_pack_chosen'] as String?;
    final parsedMix = PackMix.tryFromJson(json['pack_mix']);
    return PlayerProgress(
      // Tolère l'ancienne clé `coins` pour ne pas perdre le solde des
      // joueurs existants après le rebranding Cauris.
      cauris: (json['cauris'] as int?) ?? (json['coins'] as int?) ?? 120,
      completedLevelsByMountain:
          ((json['levels'] as Map<String, dynamic>?) ?? <String, dynamic>{})
              .map((k, v) => MapEntry(k, v as int)),
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
      activePackMix:
          parsedMix ?? _defaultPackMix(ownedPacks, freePack),
      starsByLevel: ((json['stars_by_level'] as Map<String, dynamic>?) ??
              <String, dynamic>{})
          .map((k, v) => MapEntry(k, v as int)),
      failsByLevel: ((json['fails_by_level'] as Map<String, dynamic>?) ??
              <String, dynamic>{})
          .map((k, v) => MapEntry(k, v as int)),
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

  /// Mix utilisé tant que l'onboarding n'a pas tranché — pointe sur un
  /// pack-token sentinelle (`_pending_`) pour signaler "non choisi". Le
  /// tirage doit refuser ce mix : l'app ne doit pas démarrer une partie
  /// avant que l'utilisateur ait choisi son pack gratuit.
  ///
  /// Toujours préférer le getter [activePackMix] de l'instance courante
  /// + le drapeau [hasChosenFreePack] dans la couche présentation.
  static final PackMix _placeholderMix = PackMix.single(packPendingSentinel);

  /// Sentinelle utilisée par le mix par défaut avant choix du pack gratuit.
  /// Ne doit jamais être passée à un repository de devinettes.
  static const String packPendingSentinel = '_pending_';

  /// Construit un mix par défaut cohérent à partir de l'état persisté.
  /// Précédence : `freePackChosen` > 1er `ownedPacks` > sentinelle.
  static PackMix _defaultPackMix(
    Set<String> ownedPacks,
    String? freePackChosen,
  ) {
    if (freePackChosen != null && freePackChosen.isNotEmpty) {
      return PackMix.single(freePackChosen);
    }
    if (ownedPacks.isNotEmpty) {
      return PackMix.single(ownedPacks.first);
    }
    return _placeholderMix;
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

  /// Pondération active pour le tirage des devinettes.
  /// Default = `PackMix.single(freePackChosen)` quand un pack est choisi,
  /// sinon mix sentinelle (`_pending_`).
  final PackMix activePackMix;

  /// Étoiles obtenues par niveau (clé = `"$mountainId#$levelIndex"`, 1-3).
  /// Garde toujours le meilleur score d'un re-run (cf. `mergeStars` dans
  /// `PlayerProgressNotifier.recordWin`). Niveaux non joués absents de la
  /// map.
  final Map<String, int> starsByLevel;

  /// Compteur d'échecs **consécutifs sur le même niveau** (clé =
  /// `"$mountainId#$levelIndex"`).
  ///
  /// Distinct de [consecutiveFailures] (qui est global et sert au
  /// trigger des interstitielles). Ici on suit niveau par niveau pour :
  /// - décider si la réponse doit être révélée gratuitement (≥ 3 échecs
  ///   consécutifs sur le même niveau, anti-blocage en zone T3+) ;
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

  /// True quand l'utilisateur a déjà choisi son pack gratuit (gating
  /// d'onboarding).
  bool get hasChosenFreePack => freePackChosen != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
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
  };

  /// Combien de niveaux complétés sur cette montagne.
  int levelsOn(String mountainId) => completedLevelsByMountain[mountainId] ?? 0;

  /// Nombre d'étoiles obtenues sur un niveau précis (0 si jamais joué).
  int starsOnLevel({required String mountainId, required int levelIndex}) {
    return starsByLevel['$mountainId#$levelIndex'] ?? 0;
  }

  /// Compteur d'échecs consécutifs sur ce niveau précis (0 si jamais raté
  /// ou si déjà gagné depuis le dernier échec). Reset à 0 dans
  /// `PlayerProgressNotifier.recordWin`.
  int failsOnLevel({required String mountainId, required int levelIndex}) {
    return failsByLevel['$mountainId#$levelIndex'] ?? 0;
  }

  /// Somme des étoiles obtenues sur **tous** les niveaux joués. Dérivé à
  /// la volée depuis [starsByLevel] (pas de persistance dédiée — évite la
  /// désynchro avec le détail). Sert au système star-gate (cf.
  /// `StarGate.computeUnlockedTier`).
  int get totalStars =>
      starsByLevel.values.fold<int>(0, (sum, s) => sum + s);

  /// Nombre de défaites consécutives en cours sur une devinette donnée
  /// (0 si jamais perdu ou si reset suite à victoire/skip). Sert au
  /// déclenchement du skip gratuit anti-tilt au seuil
  /// `kFreeSkipLossThreshold`.
  int consecutiveLossesOn(String devinetteId) =>
      consecutiveLossesByDevinetteId[devinetteId] ?? 0;

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
    PackMix? activePackMix,
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
      activePackMix: activePackMix ?? this.activePackMix,
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
    activePackMix,
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
  ];
}
