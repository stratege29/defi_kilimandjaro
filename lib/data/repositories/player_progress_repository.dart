import 'dart:convert';

import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/domain/entities/game_economy_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';
import 'package:defi_kilimandjaro/domain/services/daily_challenge_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repository de la progression du joueur.
///
/// Stockage en JSON sous une seule clé `player_progress` pour éviter les
/// race conditions multi-clés et faciliter la migration v2 (Firestore).
class PlayerProgressRepository {
  PlayerProgressRepository(this._prefs);

  static const String _key = 'player_progress';

  final SharedPreferences _prefs;

  /// Lit l'état actuel ou retourne l'état initial.
  ///
  /// [initialCauris] : solde de bienvenue appliqué uniquement aux **nouveaux
  /// joueurs** (aucun JSON persisté). Les profils existants conservent leur
  /// solde — un override Remote Config ne re-crédite pas rétroactivement.
  PlayerProgress load({int initialCauris = 120}) {
    final raw = _prefs.getString(_key);
    if (raw == null) return PlayerProgress.initial(cauris: initialCauris);
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PlayerProgress.fromJson(json);
    } on FormatException {
      return PlayerProgress.initial(cauris: initialCauris);
    }
  }

  /// Persiste un nouvel état.
  Future<void> save(PlayerProgress progress) async {
    await _prefs.setString(_key, jsonEncode(progress.toJson()));
  }

  /// Reset complet (utilisé par le bouton réinitialisation Profil Phase 3).
  Future<void> reset() async {
    await _prefs.remove(_key);
  }
}

/// Initialisé async au boot via override dans `main.dart`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main.dart with the '
    'resolved SharedPreferences instance.',
  ),
);

final playerProgressRepositoryProvider = Provider<PlayerProgressRepository>((
  ref,
) {
  return PlayerProgressRepository(ref.watch(sharedPreferencesProvider));
});

/// État courant de la progression — lu une fois au boot puis muté via
/// [PlayerProgressNotifier].
class PlayerProgressNotifier extends StateNotifier<PlayerProgress> {
  PlayerProgressNotifier(this._repo, {int initialCaurisIfNew = 120})
      : _initialCauris = initialCaurisIfNew,
        super(_repo.load(initialCauris: initialCaurisIfNew));

  final PlayerProgressRepository _repo;
  final int _initialCauris;

  /// Vrai si le joueur a acheté le pack "Supprimer les pubs". Lecture
  /// publique pour les services qui ont besoin du flag sans avoir besoin
  /// d'accéder à l'intégralité de l'état (cf. `AdsService`).
  bool get isNoAdsPurchased => state.noAdsPurchased;

  /// Récompense après une victoire sur une montagne donnée.
  ///
  /// `caurisAwarded` = base 30 + bonus vitesse (timeLeft × 2), multiplié
  /// par `caurisMultiplier` du tier.
  ///
  /// Quand `levelIndex` et `starsEarned` sont fournis, persiste aussi le
  /// score étoile du niveau en gardant **le meilleur** entre la valeur
  /// existante et la nouvelle (un re-run avec un meilleur perf up le
  /// score ; un re-run moins bon n'écrase pas).
  ///
  /// Reset le compteur d'échecs consécutifs.
  Future<void> recordWin({
    required String? mountainId,
    required int caurisAwarded,
    int? levelIndex,
    int? starsEarned,
    String? devinetteId,
  }) async {
    final levels = Map<String, int>.from(state.completedLevelsByMountain);
    if (mountainId != null) {
      // On n'incrémente le compteur de niveaux complétés que si le joueur
      // pousse le front d'avancement (1er run d'un niveau). Les re-runs
      // de niveaux déjà complétés mettent à jour les étoiles uniquement.
      final currentCompleted = levels[mountainId] ?? 0;
      if (levelIndex == null || levelIndex > currentCompleted) {
        levels[mountainId] = currentCompleted + 1;
      }
    }

    // Merge max sur le score étoile du niveau (rejouabilité).
    final stars = Map<String, int>.from(state.starsByLevel);
    if (mountainId != null && levelIndex != null && starsEarned != null) {
      final key = '$mountainId#$levelIndex';
      final previous = stars[key] ?? 0;
      if (starsEarned > previous) {
        stars[key] = starsEarned;
      }
    }

    final isFirstRun = mountainId == null ||
        levelIndex == null ||
        levelIndex > (state.completedLevelsByMountain[mountainId] ?? 0);

    // Reset du compteur d'échecs consécutifs **sur ce niveau** : on a
    // gagné, donc on efface l'historique de blocage. La map n'est
    // recopiée que si une entrée existait pour cette clé — évite des
    // copies inutiles à chaque victoire.
    var fails = state.failsByLevel;
    if (mountainId != null && levelIndex != null) {
      final key = '$mountainId#$levelIndex';
      if (fails.containsKey(key)) {
        fails = Map<String, int>.from(fails)..remove(key);
      }
    }

    // Reset du compteur anti-tilt **sur cette devinette** : on l'a
    // résolue, l'historique de blocage est effacé. Copie conditionnelle
    // pour éviter une allocation à chaque victoire sans blocage antérieur.
    var soloLosses = state.consecutiveLossesByDevinetteId;
    if (devinetteId != null && soloLosses.containsKey(devinetteId)) {
      soloLosses = Map<String, int>.from(soloLosses)..remove(devinetteId);
    }

    final newState = state.copyWith(
      cauris: state.cauris + caurisAwarded,
      completedLevelsByMountain: levels,
      totalLevelsCompleted:
          state.totalLevelsCompleted + (isFirstRun ? 1 : 0),
      lastPlayDate: DateTime.now(),
      consecutiveFailures: 0,
      starsByLevel: stars,
      failsByLevel: fails,
      consecutiveLossesByDevinetteId: soloLosses,
    );
    state = newState;
    await _repo.save(newState);
  }

  /// Anti-tilt — incrémente le compteur de défaites consécutives sur
  /// **cette devinette** (solo). Aucune pénalité en cauris : décision
  /// produit « ne pas punir l'échec » (cf. `kFreeSkipLossThreshold` et
  /// `game_view`). Au seuil `kFreeSkipLossThreshold`, l'écran d'échec
  /// propose un skip gratuit via [recordSoloSkipFree].
  Future<void> recordSoloLoss({required String devinetteId}) async {
    if (devinetteId.isEmpty) return;
    final losses =
        Map<String, int>.from(state.consecutiveLossesByDevinetteId);
    losses[devinetteId] = (losses[devinetteId] ?? 0) + 1;
    final newState =
        state.copyWith(consecutiveLossesByDevinetteId: losses);
    state = newState;
    await _repo.save(newState);
  }

  /// Anti-tilt — reset du compteur de défaites consécutives sur cette
  /// devinette suite à un skip gratuit, sans pénalité. No-op si aucun
  /// compteur n'existe (évite une allocation inutile).
  Future<void> recordSoloSkipFree({required String devinetteId}) async {
    if (!state.consecutiveLossesByDevinetteId.containsKey(devinetteId)) {
      return;
    }
    final losses =
        Map<String, int>.from(state.consecutiveLossesByDevinetteId)
          ..remove(devinetteId);
    final newState =
        state.copyWith(consecutiveLossesByDevinetteId: losses);
    state = newState;
    await _repo.save(newState);
  }

  /// Incrémente le compteur d'échecs consécutifs (utilisé pour
  /// déclencher l'interstitielle toutes les 3 défaites).
  Future<int> recordFailure() async {
    final newCount = state.consecutiveFailures + 1;
    final newState = state.copyWith(consecutiveFailures: newCount);
    state = newState;
    await _repo.save(newState);
    return newCount;
  }

  /// Incrémente le compteur d'échecs consécutifs **sur ce niveau précis**
  /// et retourne le nouveau total.
  ///
  /// Distinct de [recordFailure] (compteur global pour les interstitielles).
  /// Sert au filet anti-blocage du reveal : quand ce compteur atteint 3,
  /// `GameView` révèle la réponse gratuitement même en zone T3+.
  ///
  /// Reset à 0 dans [recordWin] dès que ce niveau précis est gagné.
  Future<int> recordLevelFailure({
    required String mountainId,
    required int levelIndex,
  }) async {
    final key = '$mountainId#$levelIndex';
    final current = state.failsByLevel[key] ?? 0;
    final newCount = current + 1;
    final fails = Map<String, int>.from(state.failsByLevel)
      ..[key] = newCount;
    final newState = state.copyWith(failsByLevel: fails);
    state = newState;
    await _repo.save(newState);
    return newCount;
  }

  /// Déduit le coût d'un reveal payant et retourne true si la dépense a
  /// eu lieu. Retourne false (sans toucher au solde) si solde insuffisant.
  ///
  /// Sémantique alignée sur [spendOnHint] — les deux opérations sont des
  /// "spend cauris" mais préservées séparément pour faciliter le tracking
  /// analytique distinct (Phase 4) : hint vs reveal n'ont pas la même
  /// valeur économique ni la même intention joueur.
  Future<bool> purchaseReveal(int cost) async {
    if (cost <= 0) return true;
    if (state.cauris < cost) return false;
    final newState = state.copyWith(cauris: state.cauris - cost);
    state = newState;
    await _repo.save(newState);
    return true;
  }

  /// Marque l'achat "No-Ads" comme accordé. Idempotent.
  Future<void> grantNoAds() async {
    if (state.noAdsPurchased) return;
    final newState = state.copyWith(noAdsPurchased: true);
    state = newState;
    await _repo.save(newState);
  }

  /// Marque l'achat Starter Pack — flip le flag + crédite immédiatement
  /// les cauris bonus. Idempotent (un second appel retourne sans
  /// modifier l'état).
  Future<void> grantStarterPack({required int caurisBonus}) async {
    if (state.starterPackPurchased) return;
    final newState = state.copyWith(
      starterPackPurchased: true,
      cauris: state.cauris + caurisBonus,
    );
    state = newState;
    await _repo.save(newState);
  }

  /// Initialise [PlayerProgress.installDate] si encore null. Appelé une
  /// fois au boot (cf. `_BootGate`). Pas de risque de back-dater :
  /// l'app n'a plus jamais accès au point d'install initial après ça.
  Future<void> ensureInstallDate(DateTime now) async {
    if (state.installDate != null) return;
    final newState = state.copyWith(installDate: now);
    state = newState;
    await _repo.save(newState);
  }

  /// Déduit le coût d'un indice. Retourne `false` si solde insuffisant.
  ///
  /// **Priorité freebie** : si [PlayerProgress.freeHintAvailable] est
  /// `true`, l'indice est consommé du freebie quotidien (cauris
  /// inchangés) et le drapeau passe à `false`. C'est la mécanique
  /// « indice gratuit au 1er accès du jour » — la moindre dépense
  /// d'indice de la session le consomme avant de toucher au solde.
  Future<bool> spendOnHint(int cost) async {
    if (state.freeHintAvailable) {
      final newState = state.copyWith(freeHintAvailable: false);
      state = newState;
      await _repo.save(newState);
      return true;
    }
    if (state.cauris < cost) return false;
    final newState = state.copyWith(cauris: state.cauris - cost);
    state = newState;
    await _repo.save(newState);
    return true;
  }

  /// Octroie un **indice gratuit** si la dernière distribution remonte à
  /// un jour calendaire antérieur à `date` (idempotent par jour). Aucun
  /// effet si déjà accordé aujourd'hui — sûr à appeler à chaque boot du
  /// home / chaque tick de session.
  ///
  /// Retourne `true` si un nouvel indice a été crédité, `false` si no-op.
  /// Le drapeau `freeHintAvailable` peut rester `true` d'un jour à
  /// l'autre si le joueur ne l'a pas consommé — l'octroi est idempotent
  /// mais le freebie ne stack pas (un seul en réserve à tout moment).
  Future<bool> claimFreeHintIfDue({required DateTime date}) async {
    final last = state.lastFreeHintGrantedDate;
    if (last != null) {
      final lastDay = DateTime(last.year, last.month, last.day);
      final today = DateTime(date.year, date.month, date.day);
      if (!today.isAfter(lastDay)) return false; // déjà octroyé aujourd'hui
    }
    final newState = state.copyWith(
      freeHintAvailable: true,
      lastFreeHintGrantedDate: date,
    );
    state = newState;
    await _repo.save(newState);
    return true;
  }

  /// Enregistre le résultat du défi du jour (daily challenge).
  ///
  /// Logique :
  /// - **Succès** : streak += 1 (ou +1 depuis 0 si premier défi),
  ///   octroi `DailyChallengeService.rewardCauris` (100) + éventuel
  ///   bonus de palier (cf. `DailyChallengeService.bonusForStreak`).
  /// - **Échec** : streak reset à 0, aucun cauris.
  /// - **Day-skip détecté** (gap ≥ 2 jours avec le dernier daily) :
  ///   - Si le joueur a au moins un **freeze token** ET le résultat du
  ///     jour est un succès → on **préserve** le streak (gain +1 comme
  ///     une continuité), décrémente le compteur de tokens, marque
  ///     `lastFreezeUsedDate = date`.
  ///   - Sinon (pas de token, ou résultat = échec) : streak reset à 0
  ///     puis on applique la logique normale.
  ///
  /// Le freeze est **automatique conditionnel** : il ne se consomme
  /// jamais sur un échec du jour (sinon le streak partirait à 0 quand
  /// même, gaspillage). Validation PO mai 2026.
  ///
  /// `date` est le jour calendaire local du défi (heures à 0 idéalement
  /// mais on tolère une DateTime quelconque — la comparaison se fait au
  /// jour). Retourne le **total** de cauris octroyés (base + bonus
  /// éventuel, 0 si échec).
  Future<int> recordDailyChallengeResult({
    required DateTime date,
    required bool success,
  }) async {
    final last = state.lastDailyChallengeDate;
    var baseStreak = state.dailyChallengeStreak;
    var freezeTokens = state.freezeTokens;
    var lastFreezeUsedDate = state.lastFreezeUsedDate;

    if (last != null) {
      final lastDay = DateTime(last.year, last.month, last.day);
      final today = DateTime(date.year, date.month, date.day);
      final delta = today.difference(lastDay).inDays;
      if (delta >= 2) {
        // Day-skip détecté. On tente un freeze automatique :
        // seulement si success ET tokens disponibles.
        if (success && freezeTokens > 0) {
          freezeTokens -= 1;
          lastFreezeUsedDate = date;
          // baseStreak inchangé → continuité préservée.
        } else {
          baseStreak = 0; // skip ⇒ streak perdu avant calcul
        }
      }
    }

    final newStreak = success ? baseStreak + 1 : 0;
    // Bonus de palier — octroyé **une seule fois** quand le streak
    // bascule sur 3, 7 ou 30 jours exactement (cf. service domain).
    // Zéro en cas d'échec puisque newStreak = 0.
    final bonus =
        success ? DailyChallengeService.bonusForStreak(newStreak) : 0;
    final awarded = success ? DailyChallengeService.rewardCauris + bonus : 0;

    final newState = state.copyWith(
      cauris: state.cauris + awarded,
      dailyChallengeStreak: newStreak,
      lastDailyChallengeDate: date,
      freezeTokens: freezeTokens,
      lastFreezeUsedDate: lastFreezeUsedDate,
    );
    state = newState;
    await _repo.save(newState);
    return awarded;
  }

  /// Achète un **freeze token** au prix `DailyChallengeService.
  /// freezeTokenCost` (150 🐚). Refuse l'achat si :
  /// - le solde est insuffisant ;
  /// - le stock max (`DailyChallengeService.maxFreezeTokens` = 3) est
  ///   déjà atteint (évite le farming abusif).
  ///
  /// Retourne `true` si l'achat a réussi.
  Future<bool> purchaseFreezeToken() async {
    if (state.freezeTokens >= DailyChallengeService.maxFreezeTokens) {
      return false;
    }
    const cost = DailyChallengeService.freezeTokenCost;
    if (state.cauris < cost) return false;
    final newState = state.copyWith(
      cauris: state.cauris - cost,
      freezeTokens: state.freezeTokens + 1,
    );
    state = newState;
    await _repo.save(newState);
    return true;
  }

  /// Ajoute des cauris au solde (utilisé par les achats IAP et les pubs
  /// rewarded vidéo en Phase 4.2).
  Future<void> addCauris(int amount) async {
    if (amount <= 0) return;
    final newState = state.copyWith(cauris: state.cauris + amount);
    state = newState;
    await _repo.save(newState);
  }

  // ---------------------------------------------------------------------
  // Streak quotidien (Phase 4 — Étape C)
  // ---------------------------------------------------------------------

  /// Snapshot non-mutant de l'état du streak du jour. Retourne `null` si
  /// le joueur a déjà claim aujourd'hui (rien à montrer). Sinon retourne
  /// le `streakDay` qui sera atteint et le `bonus` qui sera crédité au
  /// claim — l'UI s'en sert pour préparer le popup avant que le joueur
  /// confirme.
  ///
  /// Logique calendrier :
  /// - Jamais réclamé OU dernier claim > la veille → reset à `streakDay = 1`.
  /// - Dernier claim hier → `streakDay = dailyStreak + 1`.
  /// - Dernier claim aujourd'hui → null (déjà fait).
  ({int streakDay, int bonus})? peekClaimableStreak({
    required GameEconomyConfig config,
    DateTime? now,
  }) {
    final today = _calendarDay(now ?? DateTime.now());
    final last = state.lastStreakClaimDate == null
        ? null
        : _calendarDay(state.lastStreakClaimDate!);

    if (last != null && last == today) {
      return null; // Déjà claimé aujourd'hui — rien à montrer.
    }

    final isYesterday = last != null &&
        today.difference(last).inDays == 1;
    final nextStreak = isYesterday ? state.dailyStreak + 1 : 1;
    final bonus = config.streakRewardForDay(nextStreak);
    return (streakDay: nextStreak, bonus: bonus);
  }

  /// Crédite le bonus streak et persiste l'état. Idempotent : un second
  /// claim le même jour est un no-op qui retourne `false`.
  ///
  /// Retourne le bonus effectivement crédité (0 si non claimé).
  Future<int> claimDailyStreak({
    required GameEconomyConfig config,
    DateTime? now,
  }) async {
    final claimable = peekClaimableStreak(config: config, now: now);
    if (claimable == null) return 0;
    final today = now ?? DateTime.now();
    final newState = state.copyWith(
      cauris: state.cauris + claimable.bonus,
      dailyStreak: claimable.streakDay,
      lastStreakClaimDate: today,
    );
    state = newState;
    await _repo.save(newState);
    return claimable.bonus;
  }

  /// Tronque une date au jour calendaire (00:00 local). Sert à comparer
  /// "même jour" sans se faire piéger par les heures.
  static DateTime _calendarDay(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  /// Réinitialisation depuis l'écran Profil.
  Future<void> reset() async {
    await _repo.reset();
    state = PlayerProgress.initial(cauris: _initialCauris);
  }

  /// **Outil de debug uniquement** — marque toutes les montagnes données
  /// comme intégralement terminées pour permettre de tester rapidement
  /// les niveaux haute altitude (reverse, thinAir, boss tier 5).
  ///
  /// Doit être gardé derrière `kDebugMode` côté UI ; le repository accepte
  /// inconditionnellement pour rester sans dépendance Flutter.
  /// Idempotent : ré-appel = no-op.
  Future<void> unlockAllForDebug(Iterable<Mountain> mountains) async {
    final levels = Map<String, int>.from(state.completedLevelsByMountain);
    var changed = false;
    for (final m in mountains) {
      if ((levels[m.id] ?? 0) < m.totalLevels) {
        levels[m.id] = m.totalLevels;
        changed = true;
      }
    }
    if (!changed) return;
    final newState = state.copyWith(completedLevelsByMountain: levels);
    state = newState;
    await _repo.save(newState);
  }

  /// Mémorise l'id d'une devinette qui vient d'être servie au joueur, en
  /// tête de la liste `recentDevinetteIds` (limitée à 5 entrées).
  /// Sert l'anti-répétition : ces ids sont exclus du prochain
  /// `randomFromPackExcluding`.
  Future<void> recordRecentDevinette(String devinetteId) async {
    final list = <String>[devinetteId];
    for (final id in state.recentDevinetteIds) {
      if (id == devinetteId) continue; // dédup si déjà en tête plus loin
      list.add(id);
      if (list.length >= _recentDevinetteCacheSize) break;
    }
    final newState = state.copyWith(recentDevinetteIds: list);
    state = newState;
    await _repo.save(newState);
  }

  /// Taille de la mémoire anti-répétition. 5 suffit en pratique : le pool
  /// `culture_ci` actuel contient bien plus que 5 devinettes, donc la
  /// branche fallback de `randomFromPackExcluding` ne sera quasi-jamais
  /// déclenchée.
  static const int _recentDevinetteCacheSize = 5;

  /// Marque ces modifiers comme « déjà rencontrés » par le joueur. Appelé
  /// après le dismiss de l'overlay « Le Griot t'avertit » : aux prochaines
  /// rencontres, le briefing affichera uniquement le nom du modifier
  /// (pas la description longue).
  ///
  /// No-op si tous les modifiers passés sont déjà connus — pas de persist
  /// inutile.
  Future<void> recordModifiersEncounter(Set<LevelModifier> modifiers) async {
    if (modifiers.isEmpty) return;
    final current = state.encounteredModifiers;
    final additions = modifiers.difference(current);
    if (additions.isEmpty) return;
    final updated = <LevelModifier>{...current, ...additions};
    final newState = state.copyWith(encounteredModifiers: updated);
    state = newState;
    await _repo.save(newState);
  }

  // ---------------------------------------------------------------------
  // Packs thématiques (Phase 2 — sprint contenu)
  // ---------------------------------------------------------------------

  /// Sélectionne le pack gratuit initial — **opération à usage unique**.
  ///
  /// Règle produit verrouillée par le PO : le pack gratuit est définitif.
  /// Appel ultérieur ignoré silencieusement (retourne `false`) pour ne pas
  /// casser un re-tap accidentel sur l'écran d'onboarding.
  ///
  /// Effets de bord :
  /// - ajoute `packId` à [PlayerProgress.ownedPacks] ;
  /// - définit [PlayerProgress.freePackChosen] = `packId` ;
  /// - bascule [PlayerProgress.activePackMix] sur `PackMix.single(packId)`.
  Future<bool> chooseFreePack(String packId) async {
    if (state.hasChosenFreePack) return false;
    if (packId.isEmpty) {
      throw ArgumentError.value(packId, 'packId', 'must not be empty');
    }
    final owned = <String>{...state.ownedPacks, packId};
    final newState = state.copyWith(
      ownedPacks: owned,
      freePackChosen: packId,
      activePackMix: PackMix.single(packId),
    );
    state = newState;
    await _repo.save(newState);
    return true;
  }

  /// Marque un pack comme acquis (post-achat IAP ou cauris).
  ///
  /// N'affecte PAS [PlayerProgress.activePackMix] — l'utilisateur devra
  /// explicitement ajouter le nouveau pack à son mix via [setPackMix]
  /// (écran "Mes packs" de la Phase 3). Idempotent.
  Future<void> grantPack(String packId) async {
    if (packId.isEmpty) {
      throw ArgumentError.value(packId, 'packId', 'must not be empty');
    }
    if (state.ownedPacks.contains(packId)) return;
    final newState = state.copyWith(
      ownedPacks: <String>{...state.ownedPacks, packId},
    );
    state = newState;
    await _repo.save(newState);
  }

  /// Met à jour la pondération active. Valide que tous les `packId` du mix
  /// sont possédés — lève [ArgumentError] sinon (l'UI doit pré-valider avant
  /// d'appeler ce setter).
  Future<void> setPackMix(PackMix mix) async {
    final unknown = mix.packIds.difference(state.ownedPacks);
    if (unknown.isNotEmpty) {
      throw ArgumentError.value(
        mix,
        'mix',
        'PackMix references packs not owned by the player: $unknown',
      );
    }
    if (mix == state.activePackMix) return;
    final newState = state.copyWith(activePackMix: mix);
    state = newState;
    await _repo.save(newState);
  }
}

final playerProgressProvider =
    StateNotifierProvider<PlayerProgressNotifier, PlayerProgress>((ref) {
      // Solde de bienvenue piloté par Remote Config (`eco_initial_cauris`).
      // Le snapshot est lu une fois ici : si la valeur change après que le
      // joueur a déjà créé son profil, ça n'affecte pas son solde existant.
      final econ = ref.read(gameEconomyConfigProvider);
      return PlayerProgressNotifier(
        ref.watch(playerProgressRepositoryProvider),
        initialCaurisIfNew: econ.initialCauris,
      );
    });

// ---------------------------------------------------------------------------
// Providers dérivés — packs thématiques.
//
// Pourquoi des providers dérivés plutôt qu'un nouveau StateNotifier dédié :
// la source unique de persistance est [PlayerProgressNotifier]. Dériver
// évite les race conditions multi-stores et reste cohérent avec le reste
// du projet (cauris, achats no-ads, streaks vivent déjà dans
// [PlayerProgress]). L'API en lecture reste granulaire pour ne pas
// re-rendre toute l'UI à chaque mutation non-pack.
// ---------------------------------------------------------------------------

/// Set des packs possédés par le joueur (inclut le pack gratuit initial).
final ownedPacksProvider = Provider<Set<String>>((ref) {
  return ref.watch(playerProgressProvider.select((p) => p.ownedPacks));
});

/// ID du pack gratuit choisi à l'onboarding (immuable une fois défini).
/// `null` tant que l'utilisateur n'a pas choisi.
final freePackChosenProvider = Provider<String?>((ref) {
  return ref.watch(playerProgressProvider.select((p) => p.freePackChosen));
});

/// Drapeau d'onboarding : true quand l'utilisateur a fait son choix.
final hasChosenFreePackProvider = Provider<bool>((ref) {
  return ref.watch(playerProgressProvider.select((p) => p.hasChosenFreePack));
});

/// Pondération active pour le tirage des devinettes.
/// Setter via `ref.read(playerProgressProvider.notifier).setPackMix(mix)`.
final packMixProvider = Provider<PackMix>((ref) {
  return ref.watch(playerProgressProvider.select((p) => p.activePackMix));
});
