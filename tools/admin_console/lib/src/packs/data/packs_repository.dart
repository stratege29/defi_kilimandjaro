// Repository — les méthodes sont auto-descriptives via leur doc-comment
// quand pertinent ; les providers/getters n'ont rien à dire de plus.
// ignore_for_file: public_member_api_docs

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kilimandjaro_admin/src/packs/domain/pack.dart';
import 'package:kilimandjaro_admin/src/packs/domain/question.dart';

/// Repository Firestore — packs + questions.
///
/// Toutes les écritures passent par cette classe pour isoler les
/// `serverTimestamp` et la conversion modèles<->maps. Pas de cache local —
/// on s'appuie sur les listeners Firestore pour le live-reload.
class PacksRepository {
  PacksRepository(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _packsCol =>
      _db.collection('content_packs');

  CollectionReference<Map<String, dynamic>> _questionsCol(String packId) =>
      _packsCol.doc(packId).collection('questions');

  // ---------------------------------------------------------------------------
  // Packs (metadata)
  // ---------------------------------------------------------------------------

  Stream<List<Pack>> watchPacks() {
    return _packsCol.orderBy(FieldPath.documentId).snapshots().map(
          (snap) => snap.docs.map(Pack.fromDoc).toList(),
        );
  }

  Stream<Pack> watchPack(String packId) {
    return _packsCol.doc(packId).snapshots().map((doc) {
      if (!doc.exists) {
        // Doc vide — on retourne un Pack par défaut pour permettre
        // l'édition initiale, mais l'écran de saisie devra appeler
        // upsertPack pour persister.
        throw StateError('Pack $packId introuvable.');
      }
      return Pack.fromDoc(doc);
    });
  }

  Future<Pack?> getPack(String packId) async {
    final snap = await _packsCol.doc(packId).get();
    if (!snap.exists) return null;
    return Pack.fromDoc(snap);
  }

  /// Crée ou met à jour les *métadonnées* d'un pack. Les champs maintenus
  /// par la Cloud Function (current_version, hash, etc.) ne sont JAMAIS
  /// écrits ici — ils sont préservés via merge.
  Future<void> upsertPack(Pack pack) async {
    await _packsCol.doc(pack.id).set(
      <String, dynamic>{
        ...pack.toEditableMap(),
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ---------------------------------------------------------------------------
  // Questions
  // ---------------------------------------------------------------------------

  /// Stream paginé des questions d'un pack. Le filtrage par difficulté/tag
  /// est appliqué côté client après fetch — pour scaler à plus de quelques
  /// milliers de questions par pack, il faudra introduire des index
  /// composites Firestore.
  Stream<List<Question>> watchQuestions(
    String packId, {
    int limit = 500,
  }) {
    return _questionsCol(packId)
        .orderBy('id')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Question.fromDoc).toList());
  }

  Future<Question?> getQuestion(String packId, String questionId) async {
    final snap = await _questionsCol(packId).doc(questionId).get();
    if (!snap.exists) return null;
    return Question.fromDoc(snap);
  }

  /// Upsert d'une question. L'id du doc Firestore est égal à `question.id`
  /// pour faciliter le mapping et garantir l'unicité.
  Future<void> upsertQuestion(
    Question question, {
    required bool isCreate,
  }) async {
    final ref = _questionsCol(question.pack).doc(question.id);
    final data = <String, dynamic>{
      ...question.toFirestoreMap(),
      'updated_at': FieldValue.serverTimestamp(),
      if (isCreate) 'created_at': FieldValue.serverTimestamp(),
    };
    // merge:false (création) ou merge:true (édition) — la valeur
    // dépend du flag, on garde l'argument explicite pour la lisibilité.
    // ignore: avoid_redundant_argument_values
    await ref.set(data, SetOptions(merge: !isCreate));
  }

  Future<void> deleteQuestion(String packId, String questionId) async {
    await _questionsCol(packId).doc(questionId).delete();
  }

  // ---------------------------------------------------------------------------
  // Publish — déclenche la Cloud Function `publishPack`
  // ---------------------------------------------------------------------------

  Future<PublishResult> publishPack(String packId) async {
    final callable = _functions.httpsCallable('publishPack');
    final res =
        await callable.call<Map<String, dynamic>>({'packId': packId});
    final data = res.data;
    return PublishResult(
      success: (data['success'] as bool?) ?? false,
      version: (data['version'] as num?)?.toInt() ?? 0,
      count: (data['count'] as num?)?.toInt() ?? 0,
      hash: (data['hash'] as String?) ?? '',
      sizeBytes: (data['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Résultat d'un appel `publishPack`.
class PublishResult {
  const PublishResult({
    required this.success,
    required this.version,
    required this.count,
    required this.hash,
    required this.sizeBytes,
  });

  final bool success;
  final int version;
  final int count;
  final String hash;
  final int sizeBytes;
}

// -----------------------------------------------------------------------------
// Providers
// -----------------------------------------------------------------------------

final firestoreProvider = Provider<FirebaseFirestore>(
  (_) => FirebaseFirestore.instance,
);

final functionsProvider = Provider<FirebaseFunctions>(
  (_) => FirebaseFunctions.instanceFor(region: 'europe-west1'),
);

final packsRepositoryProvider = Provider<PacksRepository>((ref) {
  return PacksRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
  );
});

final packsListProvider = StreamProvider<List<Pack>>((ref) {
  return ref.watch(packsRepositoryProvider).watchPacks();
});

final packProvider = StreamProvider.family<Pack, String>((ref, packId) {
  return ref.watch(packsRepositoryProvider).watchPack(packId);
});

final questionsProvider =
    StreamProvider.family<List<Question>, String>((ref, packId) {
  return ref.watch(packsRepositoryProvider).watchQuestions(packId);
});
