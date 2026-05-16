import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette_submission.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Payload envoyé à la Cloud Function `submitDevinette`.
///
/// `lettersPool` n'est PAS envoyé : il est recalculé serveur (sécurité).
class SubmissionDraft {
  const SubmissionDraft({
    required this.world,
    required this.country,
    required this.lang,
    required this.answer,
    required this.riddle,
    required this.explanation,
    required this.difficulty,
    required this.tags,
    this.proverb = '',
    this.authorDisplayName,
  });

  final String world;
  final String country;
  final String lang;
  final String answer;
  final String riddle;
  final String explanation;

  /// Proverbe — optionnel (champ retiré du formulaire de soumission, mais
  /// conservé dans le DTO pour la rétro-compat des drafts en queue locale
  /// + tolérance future si on réintroduit le champ).
  final String proverb;
  final int difficulty;
  final List<String> tags;
  final String? authorDisplayName;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'world': world,
    'country': country,
    'lang': lang,
    'answer': answer,
    'riddle': riddle,
    'explanation': explanation,
    if (proverb.isNotEmpty) 'proverb': proverb,
    'difficulty': difficulty,
    'tags': tags,
    if (authorDisplayName != null && authorDisplayName!.isNotEmpty)
      'authorDisplayName': authorDisplayName,
  };
}

/// Erreurs métier remontées par la Cloud Function `submitDevinette`.
class SubmissionException implements Exception {
  const SubmissionException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'SubmissionException($code): $message';
}

class SubmissionRepository {
  SubmissionRepository({
    required FirebaseFunctions functions,
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  }) : _functions = functions,
       _auth = auth,
       _firestore = firestore;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// Soumet une devinette via la Cloud Function. Lève [SubmissionException]
  /// sur erreur métier (quota, profanité, doublon...).
  Future<({String submissionId, int remainingQuota})> submit(
    SubmissionDraft draft,
  ) async {
    try {
      final callable = _functions.httpsCallable('submitDevinette');
      final result = await callable.call<Map<String, dynamic>>(draft.toJson());
      final data = result.data;
      return (
        submissionId: data['submissionId'] as String,
        remainingQuota: (data['remainingQuota'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseFunctionsException catch (e) {
      throw SubmissionException(e.code, e.message ?? e.code);
    }
  }

  /// Stream des soumissions de l'utilisateur courant — alimente l'écran
  /// "Mes soumissions".
  Stream<List<DevinetteSubmission>> watchMine() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream<List<DevinetteSubmission>>.empty();
    return _firestore
        .collection('submissions')
        .where('authorUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (d) => DevinetteSubmission.fromJson({...d.data(), 'id': d.id}),
              )
              .toList(growable: false),
        );
  }
}

// Riverpod wiring -------------------------------------------------------------

final firebaseFunctionsProvider = Provider<FirebaseFunctions>((ref) {
  return FirebaseFunctions.instanceFor(region: 'europe-west1');
});

final submissionRepositoryProvider = Provider<SubmissionRepository>((ref) {
  return SubmissionRepository(
    functions: ref.watch(firebaseFunctionsProvider),
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
  );
});

final mySubmissionsProvider =
    StreamProvider.autoDispose<List<DevinetteSubmission>>((ref) {
      return ref.watch(submissionRepositoryProvider).watchMine();
    });
