import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:defi_kilimandjaro/core/constants/duel_protocol.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart'
    show firebaseFunctionsProvider;
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart'
    show firestoreProvider;
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/domain/entities/tournament.dart';
import 'package:defi_kilimandjaro/domain/entities/tournament_participant.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Résultat d'un appel [TournamentRepository.requestArenaMatch].
sealed class ArenaMatchResult {
  const ArenaMatchResult();
}

/// Un adversaire a été trouvé : la session de duel de tournoi à démarrer.
final class ArenaMatched extends ArenaMatchResult {
  const ArenaMatched({required this.session});
  final DuelSession session;
}

/// Aucun adversaire pour l'instant — le joueur reste en file.
final class ArenaWaiting extends ArenaMatchResult {
  const ArenaWaiting();
}

/// Repository des tournois « arène » : lectures Firestore (liste, détail,
/// classement live) + Cloud Functions callable (rejoindre, demander un match).
///
/// Toutes les écritures (création, points, récompenses) sont serveur-only.
class TournamentRepository {
  TournamentRepository({required this.firestore, required this.functions});

  static const int kStandingsLimit = 100;

  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;
  final Logger _log = Logger();

  CollectionReference<Map<String, dynamic>> get _tournaments =>
      firestore.collection('tournaments');

  HttpsCallable _fn(String name) => functions.httpsCallable(
        name,
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );

  // ---------------------------------------------------------------------------
  // Lectures temps réel
  // ---------------------------------------------------------------------------

  /// Stream des tournois ouverts (programmés + en cours), triés par date de
  /// début croissante. Les tournois terminés/annulés sont exclus de la liste
  /// de découverte.
  ///
  /// Le tri se fait côté client : combiner `whereIn(status)` avec
  /// `orderBy(start_at)` exigerait un index composite Firestore. Le volume
  /// (tournois ouverts) est faible, le tri local est négligeable.
  Stream<List<Tournament>> watchOpenTournaments() {
    return _tournaments
        .where('status', whereIn: ['scheduled', 'live'])
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => Tournament.fromFirestore(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
      return list;
    });
  }

  /// Stream d'un tournoi précis (détail/lobby + suivi du statut).
  Stream<Tournament?> watchTournament(String tid) {
    return _tournaments.doc(tid).snapshots().map(
          (d) => d.exists ? Tournament.fromFirestore(d.id, d.data()!) : null,
        );
  }

  /// Stream du classement live (participants triés par points desc, puis
  /// victoires desc).
  ///
  /// Tri serveur sur `points` uniquement (index simple auto) + limite ; le
  /// départage par victoires se fait côté client pour éviter un index composite.
  Stream<List<TournamentParticipant>> watchStandings(String tid) {
    return _tournaments
        .doc(tid)
        .collection('participants')
        .orderBy('points', descending: true)
        .limit(kStandingsLimit)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => TournamentParticipant.fromFirestore(d.id, d.data()))
          .toList()
        ..sort((a, b) =>
            b.points != a.points ? b.points.compareTo(a.points) : b.wins.compareTo(a.wins));
      return list;
    });
  }

  /// Stream de la fiche du participant courant (points, rang, récompense).
  Stream<TournamentParticipant?> watchMyParticipant(String tid, String uid) {
    return _tournaments
        .doc(tid)
        .collection('participants')
        .doc(uid)
        .snapshots()
        .map(
          (d) => d.exists
              ? TournamentParticipant.fromFirestore(d.id, d.data()!)
              : null,
        );
  }

  // ---------------------------------------------------------------------------
  // Actions (Cloud Functions)
  // ---------------------------------------------------------------------------

  /// Inscrit le joueur courant au tournoi. Idempotent côté serveur.
  Future<void> joinTournament(String tid) async {
    try {
      await _fn('joinTournament')
          .call<dynamic>(<String, dynamic>{'tournament_id': tid});
      _log.i('joinTournament: $tid');
    } on FirebaseFunctionsException catch (e) {
      _log.e('joinTournament error: ${e.code} ${e.message}');
      rethrow;
    }
  }

  /// Demande un match d'arène (cœur de la boucle d'enchaînement).
  Future<ArenaMatchResult> requestArenaMatch({
    required String tid,
    required String requestId,
    int expansionStep = 0,
  }) async {
    try {
      final result =
          await _fn('requestArenaMatch').call<dynamic>(<String, dynamic>{
        'tournament_id': tid,
        'request_id': requestId,
        'expansion_step': expansionStep,
        'protocol_version': kDuelProtocolVersion,
      });
      final data = (result.data as Map).cast<String, dynamic>();
      if (data['status'] == 'matched') {
        final matchId = data['matchId'] as String;
        final matchData = (data['matchData'] as Map).cast<String, dynamic>();
        return ArenaMatched(session: DuelSession.fromJson(matchId, matchData));
      }
      return const ArenaWaiting();
    } on FirebaseFunctionsException catch (e) {
      _log.e('requestArenaMatch error: ${e.code} ${e.message}');
      rethrow;
    }
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final tournamentRepositoryProvider = Provider<TournamentRepository>((ref) {
  return TournamentRepository(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
  );
});

/// Liste des tournois ouverts (programmés + en cours).
final openTournamentsProvider = StreamProvider<List<Tournament>>((ref) {
  return ref.watch(tournamentRepositoryProvider).watchOpenTournaments();
});

/// Détail d'un tournoi.
final tournamentProvider =
    StreamProvider.family<Tournament?, String>((ref, tid) {
  return ref.watch(tournamentRepositoryProvider).watchTournament(tid);
});

/// Classement live d'un tournoi.
final tournamentStandingsProvider =
    StreamProvider.family<List<TournamentParticipant>, String>((ref, tid) {
  return ref.watch(tournamentRepositoryProvider).watchStandings(tid);
});
