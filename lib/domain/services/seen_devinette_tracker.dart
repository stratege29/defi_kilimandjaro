/// Tracker persistant des devinettes déjà résolues par l'utilisateur,
/// scoping par `packId`.
///
/// Objectif produit : éliminer la sensation de répétition perçue par les
/// joueurs après ~10–20 parties sur un même pack (cas réel observé sur
/// `culture_ci` à 180 entrées). Le `recentDevinetteIds` (taille 5) du
/// `PlayerProgress` est insuffisant car non scopé au pack et trop court.
///
/// Politique :
/// 1. **Exclusion stricte** : tant que le pool non-vu reste ≥ 20 % du
///    total du pack, les devinettes déjà vues ne sont jamais
///    resélectionnées.
/// 2. **Éviction FIFO** : dès que le pool non-vu descend sous 20 % du
///    total, les entrées les plus anciennes du set "seen" sont évincées
///    progressivement (re-éligibles au tirage).
/// 3. Le marquage "seen" n'a lieu qu'à la **résolution réussie** d'une
///    devinette — une défaite garde la devinette ouverte pour un retry.
///
/// Cette interface vit dans `domain/` car la règle "exclusion stricte +
/// FIFO 20 %" est business — l'implémentation (SharedPreferences /
/// éventuel Firestore plus tard) reste cantonnée à `data/`.
abstract interface class SeenDevinetteTracker {
  /// Marque une devinette comme résolue avec succès dans le pack donné.
  ///
  /// Doit être appelée **uniquement** sur victoire effective du joueur.
  /// Idempotente : un id déjà présent est promu en queue (devient le plus
  /// récent) sans dupliquer.
  Future<void> markSolved({
    required String packId,
    required String devinetteId,
  });

  /// Renvoie l'ensemble d'IDs à exclure du prochain tirage pour `packId`,
  /// en appliquant la règle "exclusion stricte + éviction FIFO".
  ///
  /// - `packTotalCount` = nombre total de devinettes effectivement
  ///   disponibles dans le pack (post-merge bundle + cache OTA).
  /// - Si `packTotalCount <= 0`, renvoie un set vide (filet de sécurité).
  ///
  /// Garantit `result.length <= packTotalCount * 0.8` (le pool restant
  /// reste ≥ 20 % du total après éviction).
  Set<String> effectiveExclusions({
    required String packId,
    required int packTotalCount,
  });

  /// Renvoie le journal complet des IDs vus pour `packId` (ordre FIFO :
  /// le premier est le plus ancien). Exposé pour les tests et pour des
  /// statistiques debug ; pas destiné à la logique métier.
  List<String> seenForPack(String packId);

  /// Vide intégralement le journal "seen" pour tous les packs.
  /// Utilisé par le bouton « Réinitialiser » du profil et la suppression
  /// de compte (RGPD).
  Future<void> clearAll();
}
