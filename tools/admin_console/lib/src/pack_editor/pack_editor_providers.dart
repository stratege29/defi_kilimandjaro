import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kilimandjaro_admin/src/models/devinette.dart';
import 'package:kilimandjaro_admin/src/models/pack_meta.dart';
import 'package:kilimandjaro_admin/src/models/pack_version.dart';

/// Stream des devinettes d'un pack (toutes, triées par id croissant).
///
/// À 500 docs ça reste un seul snapshot Firestore (~3 × 10⁻⁵ €/lecture).
/// Pour scaler au-delà, ajouter une pagination cursor ici.
final packDevinettesProvider =
    StreamProvider.family<List<Devinette>, String>((ref, packId) {
  return FirebaseFirestore.instance
      .collection('packs')
      .doc(packId)
      .collection('devinettes')
      .orderBy('id')
      .snapshots()
      .map((snap) => snap.docs.map(Devinette.fromDoc).toList());
});

/// Stream des versions d'un pack (toutes, triées par numéro décroissant).
final packVersionsProvider =
    StreamProvider.family<List<PackVersion>, String>((ref, packId) {
  return FirebaseFirestore.instance
      .collection('packs')
      .doc(packId)
      .collection('versions')
      .orderBy('number', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(PackVersion.fromDoc).toList());
});

/// Stream des métadonnées du pack (1 doc).
final packMetaProvider =
    StreamProvider.family<PackMeta?, String>((ref, packId) {
  return FirebaseFirestore.instance
      .collection('packs')
      .doc(packId)
      .collection('meta')
      .doc('doc')
      .snapshots()
      .map((snap) => snap.exists ? PackMeta.fromDoc(snap) : null);
});

/// Stream des i18n du pack (multi-langues).
final packI18nProvider =
    StreamProvider.family<List<PackI18n>, String>((ref, packId) {
  return FirebaseFirestore.instance
      .collection('packs')
      .doc(packId)
      .collection('i18n')
      .snapshots()
      .map((snap) => snap.docs.map(PackI18n.fromDoc).toList());
});

/// Stream de la whitelist tags (pour autocomplete dans le DevinetteForm).
final tagsWhitelistProvider = StreamProvider<List<String>>((ref) {
  return FirebaseFirestore.instance
      .collection('catalog')
      .doc('tags_whitelist')
      .snapshots()
      .map((snap) {
    if (!snap.exists) return const <String>[];
    final data = snap.data();
    final list = data?['tags'] as List<dynamic>?;
    return list?.map((t) => t.toString()).toList(growable: false) ??
        const <String>[];
  });
});
