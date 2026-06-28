import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:easy_localization/easy_localization.dart';

/// Affichage résilient des libellés de pack.
///
/// Les packs venant **uniquement du catalogue distant** (publiés via le
/// backoffice, absents du bundle `starter/`) n'ont pas forcément de traduction
/// embarquée : `nameKey`/`descriptionKey` valent alors `pack.<id>.name` /
/// `pack.<id>.description`, et `.tr()` renvoie la clé brute à l'écran.
///
/// Ces getters retombent proprement sur un libellé lisible (id humanisé pour le
/// nom, description générique localisée) au lieu d'afficher la clé. À utiliser
/// partout où l'on affiche un nom/description de pack à l'utilisateur, en lieu
/// et place de `pack.nameKey.tr()` / `pack.descriptionKey.tr()`.
extension PackDisplay on Pack {
  /// Nom affichable : traduction bundlée si elle existe, sinon id humanisé.
  String get displayName {
    final translated = nameKey.tr();
    if (translated != nameKey) return translated;
    return _humanizePackId(id);
  }

  /// Description affichable : traduction bundlée si elle existe, sinon une
  /// description générique localisée.
  String get displayDescription {
    final translated = descriptionKey.tr();
    if (translated != descriptionKey) return translated;
    return 'pack_notifications.generic_pack_description'.tr();
  }
}

/// `la_ville_d_abidjan` → `La Ville D Abidjan`. Fallback de dernier recours
/// quand aucune traduction n'est disponible pour un pack distant.
String _humanizePackId(String id) {
  final words = id
      .split(RegExp(r'[_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .toList(growable: false);
  return words.isEmpty ? id : words.join(' ');
}
