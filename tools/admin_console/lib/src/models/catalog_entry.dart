import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Une entrée du catalogue (un pack tel qu'exposé à l'UI admin et aux
/// clients via `catalog/index.packs[]`).
///
/// Schéma source : voir `docs/backoffice_schema.md` §3.2.
class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.visible,
    required this.ordering,
    required this.bundled,
    required this.freeChoiceEligible,
    required this.unlockCostCauris,
    required this.minAppVersion,
    required this.themeColorHex,
    required this.iconUrl,
    required this.tags,
    required this.count,
    required this.currentVersion,
  });

  final String id;
  final bool visible;
  final int ordering;
  final bool bundled;
  final bool freeChoiceEligible;
  final int unlockCostCauris;
  final String minAppVersion;
  final String themeColorHex;
  final String? iconUrl;
  final List<String> tags;
  final int count;
  final int currentVersion;

  /// Parse depuis un sous-objet `packs[]` du doc `catalog/index`.
  factory CatalogEntry.fromMap(Map<String, dynamic> raw) {
    return CatalogEntry(
      id: raw['id'] as String? ?? '',
      visible: raw['visible'] as bool? ?? true,
      ordering: (raw['ordering'] as num?)?.toInt() ?? 100,
      bundled: raw['bundled'] as bool? ?? false,
      freeChoiceEligible: raw['free_choice_eligible'] as bool? ?? false,
      unlockCostCauris: (raw['unlock_cost_cauris'] as num?)?.toInt() ?? 0,
      minAppVersion: raw['min_app_version'] as String? ?? '0.1.0',
      themeColorHex: raw['theme_color_hex'] as String? ?? '#888888',
      iconUrl: raw['icon_url'] as String?,
      tags: (raw['tags'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          const [],
      count: (raw['count'] as num?)?.toInt() ?? 0,
      currentVersion: (raw['current_version'] as num?)?.toInt() ?? 1,
    );
  }

  /// Parse le doc Firestore complet `catalog/index` (qui contient `packs[]`).
  static List<CatalogEntry> listFromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return const [];
    final list = data['packs'] as List<dynamic>?;
    if (list == null) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(CatalogEntry.fromMap)
        .toList()
      ..sort((a, b) => a.ordering.compareTo(b.ordering));
  }

  /// Couleur parsée depuis le hex (`#RRGGBB`).
  Color get themeColor {
    var hex = themeColorHex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.tryParse(hex, radix: 16) ?? 0xFF888888);
  }
}
