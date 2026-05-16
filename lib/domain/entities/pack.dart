import 'package:equatable/equatable.dart';

/// Métadonnées d'un pack thématique de devinettes.
///
/// Chargé depuis `assets/data/devinettes/starter/_index.json` (format v3).
/// Un pack regroupe une famille de devinettes culturelles (`culture_ci`,
/// `crack_nouchi`, ...). Le joueur en possède un gratuitement (choisi au
/// 1er lancement) et peut acheter les autres via IAP (`priceEur`) ou
/// cauris (`priceCauris`).
///
/// Pas de logique IAP ici — seule la métadonnée prix est exposée pour le
/// catalogue (l'écran Boutique en Phase 3 lira ces valeurs).
class Pack extends Equatable {
  const Pack({
    required this.id,
    required this.nameKey,
    required this.descriptionKey,
    required this.questionCount,
    required this.freeChoiceEligible,
    required this.priceEur,
    required this.priceCauris,
  });

  /// Parse une entrée du `_index.json` (clé = packId, valeur = body).
  factory Pack.fromIndexEntry(String id, Map<String, dynamic> json) {
    return Pack(
      id: id,
      nameKey: json['name_key'] as String,
      descriptionKey: json['description_key'] as String,
      questionCount: (json['count'] as num?)?.toInt() ?? 0,
      freeChoiceEligible: (json['free_choice_eligible'] as bool?) ?? false,
      priceEur: (json['price_eur'] as num?)?.toDouble() ?? 0.0,
      priceCauris: (json['price_cauris'] as num?)?.toInt() ?? 0,
    );
  }

  /// Identifiant stable (snake_case, ex. `culture_ci`).
  /// Sert de clé partout : repo, JSON, mix de poids, persistance.
  final String id;

  /// Clé `easy_localization` pour le nom du pack (ex. `pack.culture_ci.name`).
  final String nameKey;

  /// Clé `easy_localization` pour la description du pack.
  final String descriptionKey;

  /// Nombre de devinettes contenues dans le pack (champ `count` du manifest).
  /// Source de vérité pour l'UI catalogue ; le vrai compte effectif vient
  /// de `DevinetteRepository.loadPack` au runtime.
  final int questionCount;

  /// True si ce pack peut être choisi comme **pack gratuit initial** au
  /// premier lancement. Au moins un pack doit avoir ce flag = true côté
  /// catalogue, sinon l'onboarding plante.
  final bool freeChoiceEligible;

  /// Prix IAP en EUR (référence — le vrai prix vient du store).
  final double priceEur;

  /// Prix en cauris (monnaie in-game).
  final int priceCauris;

  @override
  List<Object?> get props => [
    id,
    nameKey,
    descriptionKey,
    questionCount,
    freeChoiceEligible,
    priceEur,
    priceCauris,
  ];
}
