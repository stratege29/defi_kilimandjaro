import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kilimandjaro_admin/src/models/catalog_entry.dart';

/// Stream du catalogue : observe `catalog/index` Firestore et retourne la
/// liste triée des `CatalogEntry`.
///
/// Émet à chaque update Firestore (utile quand un publish bump
/// `catalog_version` ou quand un admin ajoute un pack).
final catalogIndexProvider = StreamProvider<List<CatalogEntry>>((ref) {
  return FirebaseFirestore.instance
      .collection('catalog')
      .doc('index')
      .snapshots()
      .map(CatalogEntry.listFromDoc);
});

/// Une seule entrée par id, dérivée du catalogue. Utile pour PackEditorScreen.
final catalogEntryProvider = Provider.family<CatalogEntry?, String>((ref, id) {
  final list = ref.watch(catalogIndexProvider).valueOrNull;
  if (list == null) return null;
  for (final e in list) {
    if (e.id == id) return e;
  }
  return null;
});
