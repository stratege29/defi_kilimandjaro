import 'package:defi_kilimandjaro/domain/entities/devinette.dart';

/// Contrat de lecture du contenu **curated** du défi du jour.
///
/// La sélection est cross-joueurs (tous voient le même mot le même jour),
/// indépendante du pack actif du joueur — c'est l'élément de viralité et
/// de conversation sociale autour du daily challenge (cf. Wordle).
///
/// Plusieurs implémentations cohabitent :
/// - **Bundle** : lit `assets/data/daily_challenges_seed.json`, fallback
///   garanti offline. Shuffle annuel déterministe pour éviter que les
///   joueurs anciens revoient les mêmes mots aux mêmes dates.
/// - **Firestore** : lit `daily_challenges/{yyyy-MM-dd}`. Permet à
///   l'éditorial de pousser des mots événementiels sans release app
///   store. Cache local persisté (TTL 1 jour) pour minimiser les reads.
/// - **Composite** : Firestore d'abord, fallback Bundle en cas d'erreur
///   ou de doc absent. C'est le repo branché en production.
///
/// Volontairement une interface plutôt qu'une fonction top-level :
/// l'avantage de 3 impls interchangeables et mockables dépasse le
/// très léger overhead d'avoir une seule méthode.
// ignore: one_member_abstracts
abstract class DailyChallengeRepository {
  /// Retourne la devinette du jour pour `date`.
  ///
  /// Retourne `null` uniquement si **toutes** les sources échouent
  /// (cas pathologique — un bundle vide ou un seed corrompu).
  /// L'UI doit gérer le `null` comme un état d'erreur transitoire et
  /// proposer un retry plutôt qu'un blocage du joueur.
  Future<Devinette?> fetchDevinetteForDate(DateTime date);
}
