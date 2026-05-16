import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';

/// Service de tirage de devinettes pondéré par un [PackMix].
///
/// Pourquoi un service dédié plutôt qu'une méthode sur le repository :
/// - le repo reste pure data (chargement/cache, agnostique au business) ;
/// - le tirage pondéré + fallback difficulté + fallback pack est de la
///   business logic qui mérite ses propres tests unitaires injectables ;
/// - duel 1v1 (Phase 6) réutilisera ce service avec un mix fourni par
///   le lanceur — séparation logique propre.
///
/// Une seule méthode publique aujourd'hui ([nextDevinette]) mais d'autres
/// usages sont prévus (ex. `nextDevinetteForDuel` avec contraintes de
/// timing). L'abstract interface garantit la testabilité (un fake suffit
/// pour les widgets/controllers consommateurs).
///
/// Algorithme :
/// 1. Tirage pondéré du `packId` via cumulative distribution sur
///    [PackMix.weights].
/// 2. Filtre les devinettes du pack par `targetDifficulty`, avec fallback
///    progressif ±1, ±2, ... jusqu'à trouver un pool non vide (hors
///    `excludeIds`).
/// 3. Si le pack tiré est totalement vide après exclusions, on tire un
///    autre pack du mix (sans répéter les packs déjà tentés).
/// 4. Si tous les packs du mix sont vides : [StateError] explicite.
// ignore: one_member_abstracts
abstract interface class DevinetteSelectionService {
  Future<Devinette> nextDevinette({
    required PackMix mix,
    required int targetDifficulty,
    required Set<String> excludeIds,
    int? seed,
  });
}
