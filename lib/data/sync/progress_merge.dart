import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';

/// Fusionne deux instantanés de progression selon une stratégie
/// **non destructive « best-of-both »**.
///
/// Utilisé à la restauration multi-appareil : [local] est l'état du device
/// courant (potentiellement frais après réinstallation), [cloud] est la
/// sauvegarde Firestore de l'utilisateur reconnecté. Le résultat ne perd
/// jamais une progression : on prend toujours la meilleure des deux valeurs.
///
/// Règles par champ :
/// - **compteurs** (niveaux, étoiles, streaks, freeze tokens) → `max` ;
/// - **maps niveau→valeur** (levels, stars) → `max` clé par clé ;
/// - **sets** (packs possédés, modifiers rencontrés) → union ;
/// - **dates de dernière activité** → la plus récente ;
/// - **installDate** → la plus ancienne (vraie date d'install) ;
/// - **flags d'achat** (no-ads, starter pack) → `OU` logique ;
/// - **cauris** → conservés **locaux** : le solde est autorité serveur
///   (wallet Cloud Functions), jamais restauré depuis ce doc client ;
/// - **compteurs transients** (échecs consécutifs, anti-tilt, indice
///   gratuit du jour, anti-répétition) → conservés **locaux**, propres au
///   device et à la session.
PlayerProgress mergeProgress(PlayerProgress local, PlayerProgress cloud) {
  final ownedPacks = <String>{...local.ownedPacks, ...cloud.ownedPacks};

  return local.copyWith(
    // cauris : NON fusionné — autorité serveur (wallet CF).
    completedLevelsByMountain: _maxByKey(
      local.completedLevelsByMountain,
      cloud.completedLevelsByMountain,
    ),
    totalLevelsCompleted: _max(
      local.totalLevelsCompleted,
      cloud.totalLevelsCompleted,
    ),
    dailyStreak: _max(local.dailyStreak, cloud.dailyStreak),
    lastPlayDate: _latest(local.lastPlayDate, cloud.lastPlayDate),
    lastStreakClaimDate: _latest(
      local.lastStreakClaimDate,
      cloud.lastStreakClaimDate,
    ),
    installDate: _earliest(local.installDate, cloud.installDate),
    noAdsPurchased: local.noAdsPurchased || cloud.noAdsPurchased,
    starterPackPurchased:
        local.starterPackPurchased || cloud.starterPackPurchased,
    ownedPacks: ownedPacks,
    // freePackChosen est immuable une fois défini : on adopte le cloud
    // seulement si le device courant n'a pas encore tranché.
    freePackChosen: local.freePackChosen ?? cloud.freePackChosen,
    activePackMix: _pickMix(local, cloud, ownedPacks),
    starsByLevel: _maxByKey(local.starsByLevel, cloud.starsByLevel),
    dailyChallengeStreak: _max(
      local.dailyChallengeStreak,
      cloud.dailyChallengeStreak,
    ),
    lastDailyChallengeDate: _latest(
      local.lastDailyChallengeDate,
      cloud.lastDailyChallengeDate,
    ),
    freezeTokens: _max(local.freezeTokens, cloud.freezeTokens),
    lastFreezeUsedDate: _latest(
      local.lastFreezeUsedDate,
      cloud.lastFreezeUsedDate,
    ),
    lastFreeHintGrantedDate: _latest(
      local.lastFreeHintGrantedDate,
      cloud.lastFreeHintGrantedDate,
    ),
    encounteredModifiers: <LevelModifier>{
      ...local.encounteredModifiers,
      ...cloud.encounteredModifiers,
    },
  );
}

/// Préfère le mix local s'il est valable (packs possédés, pas sentinelle),
/// sinon le mix cloud s'il l'est, sinon retombe sur le local tel quel.
PackMix _pickMix(
  PlayerProgress local,
  PlayerProgress cloud,
  Set<String> ownedPacks,
) {
  bool isValid(PackMix mix) =>
      mix.packIds.isNotEmpty &&
      !mix.packIds.contains(PlayerProgress.packPendingSentinel) &&
      mix.packIds.difference(ownedPacks).isEmpty;

  if (isValid(local.activePackMix)) return local.activePackMix;
  if (isValid(cloud.activePackMix)) return cloud.activePackMix;
  return local.activePackMix;
}

int _max(int a, int b) => a > b ? a : b;

Map<String, int> _maxByKey(Map<String, int> a, Map<String, int> b) {
  final out = Map<String, int>.from(a);
  b.forEach((key, value) {
    final current = out[key];
    if (current == null || value > current) out[key] = value;
  });
  return out;
}

DateTime? _latest(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}

DateTime? _earliest(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isBefore(b) ? a : b;
}
