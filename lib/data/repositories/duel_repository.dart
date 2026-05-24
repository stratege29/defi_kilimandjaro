import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
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

  /// Rejoint un duel existant. Verifie le secret.
  /// Demarre la phase `countdown` quand le 2e joueur arrive.
  Future<void> joinDuel({
    required String matchId,
    required String secret,
  }) async {
    final uid = currentUid;
    final ref = _matchRef(matchId);
    final snapshot = await ref.get();
    if (!snapshot.exists) {
      throw StateError('Duel introuvable');
    }
    final data = (snapshot.value! as Map).cast<String, dynamic>();
    if (data['secret'] != secret) {
      throw StateError('Secret invalide');
    }
    if (data['created_by'] == uid) {
      return;
    }
    final players =
        (data['players'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    if (players.length >= 2 && !players.containsKey(uid)) {
      throw StateError('Duel complet');
    }

    await ref.update(<String, Object?>{
      'players/$uid': <String, dynamic>{
        'progress': 0,
        'found': false,
        'rounds_won': 0,
        'total_time_ms': 0,
        'rounds': <String, dynamic>{},
      },
      'phase': DuelPhase.countdown.name,
      'phase_started_at': DateTime.now().millisecondsSinceEpoch,
    });
    _log.i('Duel rejoint: $matchId par $uid');
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
  ) async {
    final callable = functions.httpsCallable('submitRoundWin');
    final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
      'match_id': matchId,
      'round': round,
      'winner_uid': winnerUid,
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

  /// Forfait — declare l'autre joueur gagnant si present.
  Future<void> forfeit(String matchId) async {
    final uid = currentUid;
    final ref = _matchRef(matchId);
    final snapshot = await ref.get();
    if (!snapshot.exists) return;
    final data = (snapshot.value! as Map).cast<String, dynamic>();
    final phase = data['phase'] as String? ?? 'waiting';
    if (phase == DuelPhase.finished.name) return;

    final players =
        (data['players'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    final otherUid =
        players.keys.firstWhere((k) => k != uid, orElse: () => '');
    await ref.update(<String, Object?>{
      'phase': DuelPhase.finished.name,
      'phase_started_at': DateTime.now().millisecondsSinceEpoch,
      if (otherUid.isNotEmpty) 'winner': otherUid,
    });
  }

  /// Rejoint un match ouvert (deep link / share) sans verification de secret.
  Future<DuelSession> joinOpen(String matchId) async {
    final uid = currentUid;
    final ref = _matchRef(matchId);
    final snapshot = await ref.get();
    if (!snapshot.exists) {
      throw Exception('duel_not_found');
    }
    final data = (snapshot.value! as Map).cast<String, dynamic>();
    final phase = data['phase'] as String? ?? 'waiting';
    if (phase == DuelPhase.finished.name) {
      throw Exception('duel_expired');
    }
    final players =
        (data['players'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    if (players.length >= 2 && !players.containsKey(uid)) {
      throw Exception('duel_full');
    }

    if (!players.containsKey(uid)) {
      await ref.update(<String, Object?>{
        'players/$uid': <String, dynamic>{
          'progress': 0,
          'found': false,
          'rounds_won': 0,
          'total_time_ms': 0,
          'rounds': <String, dynamic>{},
        },
        'phase': DuelPhase.countdown.name,
        'phase_started_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
    _log.i('joinOpen: $matchId par $uid');

    final updated = await ref.get();
    return DuelSession.fromJson(
      matchId,
      (updated.value! as Map).cast<String, dynamic>(),
    );
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
