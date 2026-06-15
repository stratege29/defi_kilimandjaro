import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:defi_kilimandjaro/core/constants/duel_protocol.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Repository des duels temps reel via Firebase Realtime Database.
///
/// Schema `/matches/{matchId}` documente dans [DuelSession].
/// Les 3 rounds sont pre-tires cote serveur (Cloud Function requestMatch) et
/// stockes sous `/matches/{matchId}/rounds/{0,1,2}`.
class DuelRepository {
  DuelRepository({
    required this.database,
    required this.auth,
    required this.functions,
  });

  final FirebaseDatabase database;
  final FirebaseAuth auth;
  final FirebaseFunctions functions;
  final Logger _log = Logger();

  DatabaseReference _matchRef(String matchId) =>
      database.ref('matches/$matchId');

  String get currentUid {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Aucun utilisateur connecte (auth anonymous requise)');
    }
    return uid;
  }

  /// Cree un duel ami (non-ranked) via QR code.
  ///
  /// Cree un duel local (QR code / deep-link, non-ranked).
  ///
  /// Appelle la Cloud Function `createLocalDuel` qui tire les 3 rounds
  /// (easy/medium/hard) cote serveur (anti-cheat) et ecrit le match
  /// dans RTDB. Le client recoit juste matchId + secret pour generer
  /// le QR code.
  Future<({String matchId, String secret})> createDuel() async {
    final callable = functions.httpsCallable('createLocalDuel');
    final result = await callable.call<Map<Object?, Object?>>();
    final data = result.data.cast<String, dynamic>();
    final matchId = data['matchId'] as String?;
    final secret = data['secret'] as String?;
    if (matchId == null || secret == null) {
      throw StateError('Reponse createLocalDuel invalide');
    }
    _log.i('Duel local cree: $matchId');
    return (matchId: matchId, secret: secret);
  }

  /// Rejoint un duel existant.
  /// Demarre la phase `countdown` quand le 2e joueur arrive.
  ///
  /// Le `secret` est optionnel : il est verifie uniquement si fourni (cas
  /// scan QR). Pour la saisie manuelle, on accepte un secret vide — le
  /// matchId a 6 chars (32^6 ≈ 1Md combinaisons) suffit comme protection.
  Future<void> joinDuel({
    required String matchId,
    String secret = '',
  }) async {
    // Anti-cheat (C1) : l'ajout du joueur + bascule phase=countdown passent
    // par la Cloud Function joinDuel (Admin SDK). Le client ne peut plus
    // ecrire `phase` directement en RTDB.
    final callable = functions.httpsCallable('joinDuel');
    await callable.call<Map<Object?, Object?>>(<String, dynamic>{
      'matchId': matchId,
      if (secret.isNotEmpty) 'secret': secret,
      'protocol_version': kDuelProtocolVersion,
    });
    _log.i('Duel rejoint (CF): $matchId');
  }

  /// Stream live de la session.
  Stream<DuelSession?> watch(String matchId) {
    return _matchRef(matchId).onValue.map((event) {
      final value = event.snapshot.value;
      if (value == null) return null;
      return DuelSession.fromJson(
        matchId,
        (value as Map).cast<String, dynamic>(),
      );
    });
  }

  /// Met a jour la progression du joueur courant dans le round actif.
  ///
  /// Ecrit dans `/matches/{matchId}/players/{uid}/rounds/{round}/progress`
  /// ET dans `/matches/{matchId}/players/{uid}/progress` (progression globale
  /// utilisee pour la barre de progression de l'adversaire).
  Future<void> updateProgress(
    String matchId,
    int round,
    double progress,
  ) async {
    final uid = currentUid;
    final clamped = progress.clamp(0.0, 1.0);
    await _matchRef(matchId).update(<String, Object?>{
      'players/$uid/progress': clamped,
      'players/$uid/rounds/$round/progress': clamped,
    });
  }

  /// Appelle la Cloud Function submitRoundWin.
  ///
  /// Le serveur valide l'etat et met a jour rounds_won, total_time_ms, phase.
  /// Retourne la prochaine phase ("countdown" ou "finished").
  Future<String> submitRoundWin(
    String matchId,
    int round,
    String winnerUid,
    String word,
  ) async {
    final callable = functions.httpsCallable('submitRoundWin');
    final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
      'match_id': matchId,
      'round': round,
      'winner_uid': winnerUid,
      // Anti-cheat (C2) : le mot forme est valide cote serveur contre la
      // reponse stockee dans /match_answers (jamais envoyee au client).
      'word': word,
    });
    return result.data['next_phase'] as String? ?? 'finished';
  }

  /// Demande au serveur d'avancer la phase (roundEnd -> countdown ou
  /// countdown -> active). Appele par le client apres son animation de 3s.
  ///
  /// Idempotent : les 2 clients peuvent appeler simultanement, le serveur
  /// gere via verification du delai minimal et de la phase courante.
  Future<void> advancePhase(String matchId) async {
    final callable = functions.httpsCallable('advancePhase');
    await callable.call<Map<String, dynamic>>(<String, dynamic>{
      'match_id': matchId,
    });
  }

  /// Declare au serveur que le timer du round courant a atteint 0 sans
  /// trouvaille. Si l'autre joueur est aussi en timeout :
  ///   - rounds intermediaires : phase passe a roundEnd (personne ne gagne)
  ///   - dernier round : match termine avec calcul du gagnant final
  ///
  /// Idempotent : les 2 clients appellent en parallele, le serveur gere.
  Future<void> submitRoundTimeout(String matchId, int round) async {
    final callable = functions.httpsCallable('submitRoundTimeout');
    await callable.call<Map<String, dynamic>>(<String, dynamic>{
      'match_id': matchId,
      'round': round,
    });
  }

  /// Forfait — declare l'autre joueur gagnant via Cloud Function.
  ///
  /// Anti-cheat (C1) : le client ne peut plus ecrire `winner`/`phase`
  /// directement en RTDB. forfeitMatch (Admin SDK) designe l'adversaire
  /// vainqueur et bascule la phase.
  Future<void> forfeit(String matchId) async {
    final callable = functions.httpsCallable('forfeitMatch');
    await callable.call<Map<Object?, Object?>>(<String, dynamic>{
      'matchId': matchId,
    });
  }

  /// Rejoint un match ouvert (deep link / share) sans verification de secret.
  ///
  /// Anti-cheat (C1) : delegue a la Cloud Function joinDuel (Admin SDK).
  Future<DuelSession> joinOpen(String matchId) async {
    final callable = functions.httpsCallable('joinDuel');
    final result = await callable.call<Map<Object?, Object?>>(<String, dynamic>{
      'matchId': matchId,
      'protocol_version': kDuelProtocolVersion,
    });
    final data = result.data.cast<String, dynamic>();
    final matchData = (data['matchData'] as Map).cast<String, dynamic>();
    _log.i('joinOpen (CF): $matchId');
    return DuelSession.fromJson(matchId, matchData);
  }

  /// Supprime la session (createur seulement).
  Future<void> deleteIfOwner(String matchId) async {
    final uid = currentUid;
    final snapshot = await _matchRef(matchId).get();
    if (!snapshot.exists) return;
    final data = (snapshot.value! as Map).cast<String, dynamic>();
    if (data['created_by'] == uid) {
      await _matchRef(matchId).remove();
    }
  }
}

final firebaseDatabaseProvider = Provider<FirebaseDatabase>((ref) {
  return FirebaseDatabase.instance;
});

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firebaseFunctionsProvider = Provider<FirebaseFunctions>((ref) {
  return FirebaseFunctions.instanceFor(region: 'europe-west1');
});

final duelRepositoryProvider = Provider<DuelRepository>((ref) {
  return DuelRepository(
    database: ref.watch(firebaseDatabaseProvider),
    auth: ref.watch(firebaseAuthProvider),
    functions: ref.watch(firebaseFunctionsProvider),
  );
});

/// Stream type d'une session de duel.
final duelSessionStreamProvider =
    StreamProvider.family<DuelSession?, String>((ref, matchId) {
  return ref.watch(duelRepositoryProvider).watch(matchId);
});
