import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/domain/avatars/avatar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Catalogue fermé des avatars disponibles dans l'app.
///
/// **Règle de migration** : ne JAMAIS supprimer un `id` du catalogue après
/// release — un profil existant pourrait pointer dessus. Pour retirer un
/// avatar de la sélection, soit le déprécier (le sortir de [all]) tout en
/// laissant l'asset, soit le marquer comme premium pour le grise out.
abstract final class AvatarCatalog {
  // ---------------------------------------------------------------------------
  // GRIOTS & SAGES
  // ---------------------------------------------------------------------------

  static const griotClassique = Avatar(
    id: 'griot_classique',
    assetPath: '${AppAssets.avatarsDir}/griot_classique.svg',
    nameKey: 'avatar.griot_classique',
    category: AvatarCategory.griot,
  );

  static const griotModerne = Avatar(
    id: 'griot_moderne',
    assetPath: '${AppAssets.avatarsDir}/griot_moderne.svg',
    nameKey: 'avatar.griot_moderne',
    category: AvatarCategory.griot,
    unlockMinElo: 2000,
  );

  static const vieuxSage = Avatar(
    id: 'vieux_sage',
    assetPath: '${AppAssets.avatarsDir}/vieux_sage.svg',
    nameKey: 'avatar.vieux_sage',
    category: AvatarCategory.griot,
  );

  static const tortueSavante = Avatar(
    id: 'tortue_savante',
    assetPath: '${AppAssets.avatarsDir}/tortue_savante.svg',
    nameKey: 'avatar.tortue_savante',
    category: AvatarCategory.griot,
  );

  // ---------------------------------------------------------------------------
  // MASQUES TRADITIONNELS
  // ---------------------------------------------------------------------------

  static const masqueBaouleLune = Avatar(
    id: 'masque_baoule_lune',
    assetPath: '${AppAssets.avatarsDir}/masque_baoule_lune.svg',
    nameKey: 'avatar.masque_baoule_lune',
    category: AvatarCategory.masque,
  );

  static const masqueDan = Avatar(
    id: 'masque_dan',
    assetPath: '${AppAssets.avatarsDir}/masque_dan.svg',
    nameKey: 'avatar.masque_dan',
    category: AvatarCategory.masque,
  );

  static const masqueSenoufoKpelie = Avatar(
    id: 'masque_senoufo_kpelie',
    assetPath: '${AppAssets.avatarsDir}/masque_senoufo_kpelie.svg',
    nameKey: 'avatar.masque_senoufo_kpelie',
    category: AvatarCategory.masque,
    unlockMinElo: 1500,
  );

  // ---------------------------------------------------------------------------
  // VIE QUOTIDIENNE
  // ---------------------------------------------------------------------------

  static const gbakaConducteur = Avatar(
    id: 'gbaka_conducteur',
    assetPath: '${AppAssets.avatarsDir}/gbaka_conducteur.svg',
    nameKey: 'avatar.gbaka_conducteur',
    category: AvatarCategory.vieQuotidienne,
  );

  static const vendeuseAttieke = Avatar(
    id: 'vendeuse_attieke',
    assetPath: '${AppAssets.avatarsDir}/vendeuse_attieke.svg',
    nameKey: 'avatar.vendeuse_attieke',
    category: AvatarCategory.vieQuotidienne,
  );

  static const mamanBebe = Avatar(
    id: 'maman_bebe',
    assetPath: '${AppAssets.avatarsDir}/maman_bebe.svg',
    nameKey: 'avatar.maman_bebe',
    category: AvatarCategory.vieQuotidienne,
  );

  static const caseKawai = Avatar(
    id: 'case_kawai',
    assetPath: '${AppAssets.avatarsDir}/case_kawai.svg',
    nameKey: 'avatar.case_kawai',
    category: AvatarCategory.vieQuotidienne,
  );

  static const grandMarche = Avatar(
    id: 'grand_marche',
    assetPath: '${AppAssets.avatarsDir}/grand_marche.svg',
    nameKey: 'avatar.grand_marche',
    category: AvatarCategory.vieQuotidienne,
  );

  // ---------------------------------------------------------------------------
  // ALIMENTS ANTHROPOMORPHES
  // ---------------------------------------------------------------------------

  static const cabosseCacao = Avatar(
    id: 'cabosse_cacao',
    assetPath: '${AppAssets.avatarsDir}/cabosse_cacao.svg',
    nameKey: 'avatar.cabosse_cacao',
    category: AvatarCategory.aliment,
  );

  static const mangueSouriante = Avatar(
    id: 'mangue_souriante',
    assetPath: '${AppAssets.avatarsDir}/mangue_souriante.svg',
    nameKey: 'avatar.mangue_souriante',
    category: AvatarCategory.aliment,
  );

  static const ignameDansante = Avatar(
    id: 'igname_dansante',
    assetPath: '${AppAssets.avatarsDir}/igname_dansante.svg',
    nameKey: 'avatar.igname_dansante',
    category: AvatarCategory.aliment,
  );

  static const pimentFurieux = Avatar(
    id: 'piment_furieux',
    assetPath: '${AppAssets.avatarsDir}/piment_furieux.svg',
    nameKey: 'avatar.piment_furieux',
    category: AvatarCategory.aliment,
  );

  // ---------------------------------------------------------------------------
  // INSTRUMENTS & OBJETS
  // ---------------------------------------------------------------------------

  static const tamtamTete = Avatar(
    id: 'tamtam_tete',
    assetPath: '${AppAssets.avatarsDir}/tamtam_tete.svg',
    nameKey: 'avatar.tamtam_tete',
    category: AvatarCategory.instrument,
  );

  static const balafonBaby = Avatar(
    id: 'balafon_baby',
    assetPath: '${AppAssets.avatarsDir}/balafon_baby.svg',
    nameKey: 'avatar.balafon_baby',
    category: AvatarCategory.instrument,
  );

  static const calebasseTete = Avatar(
    id: 'calebasse_tete',
    assetPath: '${AppAssets.avatarsDir}/calebasse_tete.svg',
    nameKey: 'avatar.calebasse_tete',
    category: AvatarCategory.instrument,
  );

  // ---------------------------------------------------------------------------
  // FAUNE
  // ---------------------------------------------------------------------------

  static const elephantIvoire = Avatar(
    id: 'elephant_ivoire',
    assetPath: '${AppAssets.avatarsDir}/elephant_ivoire.svg',
    nameKey: 'avatar.elephant_ivoire',
    category: AvatarCategory.faune,
  );

  static const panthereRoyale = Avatar(
    id: 'panthere_royale',
    assetPath: '${AppAssets.avatarsDir}/panthere_royale.svg',
    nameKey: 'avatar.panthere_royale',
    category: AvatarCategory.faune,
    unlockMinElo: 3000,
  );

  static const hippoJovial = Avatar(
    id: 'hippo_jovial',
    assetPath: '${AppAssets.avatarsDir}/hippo_jovial.svg',
    nameKey: 'avatar.hippo_jovial',
    category: AvatarCategory.faune,
  );

  static const toucanBavard = Avatar(
    id: 'toucan_bavard',
    assetPath: '${AppAssets.avatarsDir}/toucan_bavard.svg',
    nameKey: 'avatar.toucan_bavard',
    category: AvatarCategory.faune,
  );

  // ---------------------------------------------------------------------------
  // WILDCARD DRÔLE
  // ---------------------------------------------------------------------------

  static const squeletteAncetre = Avatar(
    id: 'squelette_ancetre',
    assetPath: '${AppAssets.avatarsDir}/squelette_ancetre.svg',
    nameKey: 'avatar.squelette_ancetre',
    category: AvatarCategory.wildcard,
    unlockMinElo: 2500,
  );

  // ---------------------------------------------------------------------------
  // CATALOGUE COMPLET (ordre = ordre d'affichage dans le picker)
  // ---------------------------------------------------------------------------

  static const List<Avatar> all = <Avatar>[
    // Griots & sages
    griotClassique, vieuxSage, tortueSavante, griotModerne,
    // Masques
    masqueBaouleLune, masqueDan, masqueSenoufoKpelie,
    // Vie quotidienne
    gbakaConducteur, vendeuseAttieke, mamanBebe, caseKawai, grandMarche,
    // Aliments
    cabosseCacao, mangueSouriante, ignameDansante, pimentFurieux,
    // Instruments
    tamtamTete, balafonBaby, calebasseTete,
    // Faune
    elephantIvoire, hippoJovial, toucanBavard, panthereRoyale,
    // Wildcard
    squeletteAncetre,
  ];

  /// Avatar par défaut quand aucun n'est sélectionné — utilisé en fallback
  /// par les widgets qui rendent un avatar.
  static const Avatar fallback = griotClassique;

  /// Lookup par id — null si l'id n'existe plus dans le catalogue (legacy).
  static Avatar? byId(String? id) {
    if (id == null) return null;
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Groupe le catalogue par catégorie (ordre stable = ordre d'insertion).
  static Map<AvatarCategory, List<Avatar>> groupedByCategory() {
    final map = <AvatarCategory, List<Avatar>>{};
    for (final a in all) {
      map.putIfAbsent(a.category, () => <Avatar>[]).add(a);
    }
    return map;
  }
}

/// Provider exposant le catalogue (constant — utile pour overrides en test).
final avatarCatalogProvider = Provider<List<Avatar>>((ref) {
  return AvatarCatalog.all;
});
