import 'package:equatable/equatable.dart';

/// Métadonnées d'un pack thématique de devinettes.
///
/// Sources possibles :
///   1. **Bundle** : `assets/data/devinettes/starter/_index.json` (format v3,
///      embarqué, source de vérité offline-first)
///   2. **Remote** : `catalog/index` Firestore (format v4, Phase 3 backoffice)
///
/// Les champs `nameKey` / `descriptionKey` restent toujours bundle (clés i18n).
/// Les autres (`visible`, `ordering`, `freeChoiceEligible`, prix…) peuvent
/// venir du remote pour permettre des changements à chaud sans release.
///
/// Cf `docs/backoffice_schema.md` §3.2.
class Pack extends Equatable {
  const Pack({
    required this.id,
    required this.nameKey,
    required this.descriptionKey,
    required this.questionCount,
    required this.freeChoiceEligible,
    required this.priceEur,
    required this.priceCauris,
    this.visible = true,
    this.ordering = 100,
    this.unlockCostCauris,
    this.themeColorHex,
    this.iconUrl,
    this.minAppVersion,
    this.availableFrom,
    this.availableUntil,
    this.source = PackSource.bundle,
  });

  /// Parse une entrée du `starter/_index.json` (clé = packId, valeur = body).
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

  /// Parse une entrée du document Firestore `catalog/index.packs[]` (Phase 3).
  ///
  /// Le remote ne porte pas `name_key` / `description_key` (qui restent
  /// bundle). Fusionner avec une version bundle via `mergeWithRemote`.
  factory Pack.fromCatalogEntry(
    Map<String, dynamic> json, {
    String? nameKey,
    String? descriptionKey,
  }) {
    final id = json['id'] as String;
    return Pack(
      id: id,
      nameKey: nameKey ?? 'pack.$id.name',
      descriptionKey: descriptionKey ?? 'pack.$id.description',
      questionCount: (json['count'] as num?)?.toInt() ?? 0,
      freeChoiceEligible: (json['free_choice_eligible'] as bool?) ?? false,
      // Champ legacy IAP — non présent dans catalog/index (price_eur supprimé
      // au profit du modèle cauris-only Phase 4). On laisse 0.0 par défaut.
      priceEur: 0.0,
      priceCauris: (json['unlock_cost_cauris'] as num?)?.toInt() ?? 0,
      visible: (json['visible'] as bool?) ?? true,
      ordering: (json['ordering'] as num?)?.toInt() ?? 100,
      unlockCostCauris: (json['unlock_cost_cauris'] as num?)?.toInt(),
      themeColorHex: json['theme_color_hex'] as String?,
      iconUrl: json['icon_url'] as String?,
      minAppVersion: json['min_app_version'] as String?,
      availableFrom: _parseDate(json['available_from']),
      availableUntil: _parseDate(json['available_until']),
      source: PackSource.remote,
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw is String) {
      try {
        return DateTime.parse(raw);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Fusionne ce pack bundle avec une version remote.
  ///
  /// Stratégie : le remote override le bundle pour les champs dynamiques
  /// (visible, ordering, prix, dispo temporelle), mais on conserve les
  /// clés i18n et le questionCount du bundle (qui est la baseline starter).
  Pack mergeWithRemote(Pack remote) {
    return Pack(
      id: id,
      nameKey: nameKey,
      descriptionKey: descriptionKey,
      questionCount: questionCount,
      freeChoiceEligible: remote.freeChoiceEligible,
      priceEur: remote.priceEur > 0 ? remote.priceEur : priceEur,
      priceCauris: remote.priceCauris > 0 ? remote.priceCauris : priceCauris,
      visible: remote.visible,
      ordering: remote.ordering,
      unlockCostCauris: remote.unlockCostCauris ?? unlockCostCauris,
      themeColorHex: remote.themeColorHex ?? themeColorHex,
      iconUrl: remote.iconUrl ?? iconUrl,
      minAppVersion: remote.minAppVersion ?? minAppVersion,
      availableFrom: remote.availableFrom ?? availableFrom,
      availableUntil: remote.availableUntil ?? availableUntil,
      source: PackSource.merged,
    );
  }

  // ---- Champs ------------------------------------------------------------

  /// Identifiant stable (snake_case, ex. `culture_ci`).
  /// Sert de clé partout : repo, JSON, mix de poids, persistance.
  final String id;

  /// Clé `easy_localization` pour le nom du pack (ex. `pack.culture_ci.name`).
  /// Toujours bundle — jamais override par le remote.
  final String nameKey;

  /// Clé `easy_localization` pour la description du pack.
  /// Toujours bundle — jamais override par le remote.
  final String descriptionKey;

  /// Nombre de devinettes annoncé par le manifest.
  /// Le compte effectif (bundle + cache OTA) vient de
  /// `packLiveQuestionCountProvider`.
  final int questionCount;

  /// True si ce pack peut être choisi comme pack gratuit initial.
  /// Géré côté backoffice (Phase 3) — défaut `false` si nouveau pack remote.
  final bool freeChoiceEligible;

  /// Prix IAP en EUR (legacy — sera retiré en Phase 4 au profit du modèle
  /// cauris-only). 0.0 par défaut sur les packs remote.
  final double priceEur;

  /// Prix en cauris (monnaie in-game). Synchronisé avec `unlockCostCauris`
  /// pour rétrocompat.
  final int priceCauris;

  /// True si le pack doit apparaître dans l'UI (default true pour bundle).
  /// Le backoffice peut masquer un pack sans le supprimer (`visible: false`).
  final bool visible;

  /// Ordre d'affichage dans le catalogue (croissant). 100 par défaut.
  final int ordering;

  /// Coût en cauris pour débloquer le pack (Phase 4 monétisation cauris-only).
  /// Null si non spécifié côté remote — fallback sur `priceCauris`.
  final int? unlockCostCauris;

  /// Hex color (#RRGGBB) du theme visuel du pack. Null si non spécifié.
  final String? themeColorHex;

  /// URL Storage de l'icône du pack. Null si pas d'icône custom.
  final String? iconUrl;

  /// Version minimale d'app requise (semver). Si l'app est plus ancienne,
  /// le pack devrait être masqué côté client (à implémenter dans le composite).
  final String? minAppVersion;

  /// Date à partir de laquelle le pack devient disponible (gating temporel).
  final DateTime? availableFrom;

  /// Date après laquelle le pack n'est plus disponible.
  final DateTime? availableUntil;

  /// D'où vient cette instance — utile pour debug et UI badges.
  final PackSource source;

  /// True si le pack est actuellement dans sa fenêtre de disponibilité.
  bool get isWithinAvailability {
    final now = DateTime.now();
    if (availableFrom != null && now.isBefore(availableFrom!)) return false;
    if (availableUntil != null && now.isAfter(availableUntil!)) return false;
    return true;
  }

  @override
  List<Object?> get props => [
    id,
    nameKey,
    descriptionKey,
    questionCount,
    freeChoiceEligible,
    priceEur,
    priceCauris,
    visible,
    ordering,
    unlockCostCauris,
    themeColorHex,
    iconUrl,
    minAppVersion,
    availableFrom,
    availableUntil,
    source,
  ];
}

/// Origine d'une instance `Pack`. Utile pour debug et badges UI.
enum PackSource {
  /// Lu uniquement depuis le bundle (`starter/_index.json`).
  bundle,

  /// Lu uniquement depuis Firestore (`catalog/index`).
  remote,

  /// Fusion bundle + remote (le cas standard quand les 2 sources existent).
  merged,
}
