import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:defi_kilimandjaro/core/constants/duel_protocol.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Résultat d'un appel [MatchmakingRepository.requestMatch].
sealed class MatchmakingResult {
  const MatchmakingResult();
}

/// L'adversaire a été trouvé. Contient la session de duel à démarrer.
final class MatchmakingMatched extends MatchmakingResult {
  const MatchmakingMatched({required this.session});
  final DuelSession session;
}

/// Le serveur cherche encore — pas d'adversaire dans la bande courante.
final class MatchmakingWaiting extends MatchmakingResult {
  const MatchmakingWaiting();
}

/// Delta ELO retourné par [MatchmakingRepository.endMatch].
class EloDelta {
  const EloDelta({required this.newElo, required this.delta});

  /// Nouvel ELO du joueur appelant (en mètres).
  final int newElo;

  /// Delta appliqué : positif si victoire, négatif si défaite.
  final int delta;
}

/// Repository wrappant les Cloud Functions callable du matchmaking ELO.
///
/// Usage :
/// ```dart
/// final result = await ref.read(matchmakingRepositoryProvider)
///     .requestMatch(requestId: uuid, expansionStep: 0);
/// ```
class MatchmakingRepository {
  MatchmakingRepository({required this.functions});

  final FirebaseFunctions functions;
  final Logger _log = Logger();

  HttpsCallable _fn(String name) =>
      functions.httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));

  /// Demande un match au serveur.
  ///
  /// [requestId] : identifiant unique de la session de recherche (UUID v4
  /// généré côté client au lancement du lobby). Reste identique lors des
  /// appels d'expansion pour que le serveur détecte les retries.
  ///
  /// [expansionStep] : 0 = ±150 m, 1 = ±225 m, 2 = ±300 m, …
  Future<MatchmakingResult> requestMatch({
    required String requestId,
    int expansionStep = 0,
  }) async {
    try {
      final result = await _fn('requestMatch').call<dynamic>(<String, dynamic>{
        'request_id': requestId,
        'expansion_step': expansionStep,
        'protocol_version': kDuelProtocolVersion,
      });

      final data = (result.data as Map).cast<String, dynamic>();
      final status = data['status'] as String?;

      if (status == 'matched') {
        final matchId = data['matchId'] as String;
        final matchData = (data['matchData'] as Map).cast<String, dynamic>();
        final session = DuelSession.fromJson(matchId, matchData);
        _log.i('Match trouvé: $matchId');
        return MatchmakingMatched(session: session);
      }

      return const MatchmakingWaiting();
    } on FirebaseFunctionsException catch (e) {
      _log.e('requestMatch error: ${e.code} ${e.message}');
      rethrow;
    } on Exception catch (e) {
      _log.e('requestMatch unexpected error', error: e);
      rethrow;
    }
  }

  /// Annule la recherche de match (supprime l'entrée lobby).
  Future<void> cancelMatch() async {
    try {
      await _fn('cancelMatch').call<dynamic>();
      _log.i('Match annulé');
    } on FirebaseFunctionsException catch (e) {
      _log.e('cancelMatch error: ${e.code} ${e.message}');
      // Fail-soft : ne pas bloquer l'UI si l'annulation échoue.
    } on Exception catch (e) {
      _log.e('cancelMatch unexpected error', error: e);
    }
  }

  /// Demande un rematch cible contre un adversaire identifie.
  ///
  /// Le serveur verifie que le caller et l'adversaire etaient bien dans
  /// le match [previousMatchId], puis cree un nouveau match avec
  /// l'adversaire [opponentUid] comme cible (champ target_uid RTDB).
  /// La CF sendChallengeNotif envoie automatiquement une notif FCM.
  ///
  /// Retourne le matchId du nouveau match et le secret pour rejoindre.
  /// Le caller doit observer /matches/{matchId} via RTDB stream.
  Future<({String matchId, String secret})> requestRematch({
    required String previousMatchId,
    required String opponentUid,
  }) async {
    try {
      final result = await _fn('requestRematch').call<dynamic>(<String, dynamic>{
        'previousMatchId': previousMatchId,
        'opponentUid': opponentUid,
      });

      final data = (result.data as Map).cast<String, dynamic>();
      final matchId = data['matchId'] as String;
      final secret = data['secret'] as String;
      _log.i('Rematch créé: $matchId contre $opponentUid');
      return (matchId: matchId, secret: secret);
    } on FirebaseFunctionsException catch (e) {
      _log.e('requestRematch error: ${e.code} ${e.message}');
      rethrow;
    } on Exception catch (e) {
      _log.e('requestRematch unexpected error', error: e);
      rethrow;
    }
  }

  /// Repond a un challenge async (rematch).
  ///
  /// Appele par l'opponent depuis le dialog modal in-app.
  /// - [accept] true  : nettoie pending_challenges. Le client doit ensuite
  ///   appeler joinOpen pour rejoindre effectivement le match.
  /// - [accept] false : marque le match `declined=true` + phase=finished.
  ///   Le caller detecte le refus via son stream RTDB et passe en noOpponent.
  Future<void> respondToChallenge({
    required String matchId,
    required bool accept,
  }) async {
    try {
      await _fn('respondToChallenge').call<dynamic>(<String, dynamic>{
        'matchId': matchId,
        'accept': accept,
      });
      _log.i('respondToChallenge: $matchId accept=$accept');
    } on FirebaseFunctionsException catch (e) {
      _log.e('respondToChallenge error: ${e.code} ${e.message}');
      rethrow;
    } on Exception catch (e) {
      _log.e('respondToChallenge unexpected error', error: e);
      rethrow;
    }
  }

  /// Clôture un match ranked et déclenche le calcul ELO côté serveur.
  ///
  /// [matchId] : identifiant du match terminé.
  /// [winnerUid] : UID du gagnant déclaré (cross-check). Vide => match NUL :
  /// le serveur est autoritaire (lit le `winner` enregistré) et applique
  /// l'ELO de nul aux deux joueurs.
  ///
  /// Retourne le nouvel ELO et le delta pour le joueur appelant.
  Future<EloDelta> endMatch({
    required String matchId,
    String winnerUid = '',
  }) async {
    try {
      final result = await _fn('endMatch').call<dynamic>(<String, dynamic>{
        'matchId': matchId,
        'winner_uid': winnerUid,
      });

      final data = (result.data as Map).cast<String, dynamic>();
      return EloDelta(
        newElo: (data['new_elo'] as num).toInt(),
        delta: (data['delta'] as num).toInt(),
      );
    } on FirebaseFunctionsException catch (e) {
      _log.e('endMatch error: ${e.code} ${e.message}');
      rethrow;
    } on Exception catch (e) {
      _log.e('endMatch unexpected error', error: e);
      rethrow;
    }
  }
}

final matchmakingRepositoryProvider = Provider<MatchmakingRepository>((ref) {
  return MatchmakingRepository(
    functions: FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
});
