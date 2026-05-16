import 'dart:async';
import 'dart:math';

import 'package:defi_kilimandjaro/data/repositories/devinette_repository_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/domain/repositories/devinette_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Repository des duels temps réel via Firebase Realtime Database.
///
/// Schéma `/matches/{matchId}` documenté dans [DuelSession].
class DuelRepository {
  DuelRepository({
    required this.database,
    required this.auth,
    required this.devinetteRepo,
  });

  final FirebaseDatabase database;
  final FirebaseAuth auth;
  final DevinetteRepository devinetteRepo;
  final Logger _log = Logger();
  final Random _rng = Random.secure();

  DatabaseReference _matchRef(String matchId) =>
      database.ref('matches/$matchId');

  String _generateMatchId() {
    // 6 caractères alphanumeric uppercase, lisible.
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    return List<String>.generate(
      6,
      (_) => chars[_rng.nextInt(chars.length)],
    ).join();
  }

  String _generateSecret() {
    final bytes = List<int>.generate(12, (_) => _rng.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String get currentUid {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Aucun utilisateur connecté (auth anonymous requise)');
    }
    return uid;
  }

  /// Crée un duel et retourne ses identifiants. La devinette est tirée au
  /// hasard du pack [packId] (par défaut "culture_ci").
  ///
  /// NB : le schema RTDB conserve la clé `proverb` (vide) pour la rétro-compat
  /// du parsing [DuelSession.fromJson] tant que l'UI du duel n'a pas été
  /// rebatie en Phase 3.
  Future<({String matchId, String secret})> createDuel({
    String packId = 'culture_ci',
  }) async {
    final devinette = await devinetteRepo.randomFromPack(packId);
    final shuffled = _shuffle(devinette.lettersPool);

    final matchId = _generateMatchId();
    final secret = _generateSecret();
    final uid = currentUid;
    final now = DateTime.now().millisecondsSinceEpoch;

    await _matchRef(matchId).set(<String, dynamic>{
      'secret': secret,
      'created_by': uid,
      'created_at': now,
      'phase': DuelPhase.waiting.name,
      'answer': devinette.answer,
      'letters_pool': shuffled,
      'riddle': devinette.riddle,
      'explanation': devinette.explanation,
      'proverb': '',
      'players': <String, dynamic>{
        uid: const DuelPlayer(uid: 'self', progress: 0).toJson()
          ..remove('finished_at'),
      },
    });
    _log.i('Duel créé: $matchId by $uid');
    return (matchId: matchId, secret: secret);
  }

  /// Rejoint un duel existant. Vérifie le secret.
  /// Démarre la phase `active` quand le 2e joueur arrive.
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
      // Le créateur revient à sa propre session — no-op.
      return;
    }
    final players =
        (data['players'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    if (players.length >= 2 && !players.containsKey(uid)) {
      throw StateError('Duel complet');
    }

    await ref.update(<String, Object?>{
      'players/$uid':
          const DuelPlayer(uid: 'self', progress: 0).toJson()..remove('finished_at'),
      'phase': DuelPhase.active.name,
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

  /// Met à jour la progression du joueur courant.
  Future<void> updateMyProgress(String matchId, double progress) async {
    final uid = currentUid;
    await _matchRef(matchId).child('players/$uid/progress').set(
          progress.clamp(0.0, 1.0),
        );
  }

  /// Marque le joueur courant comme ayant trouvé le mot. Premier arrivé
  /// devient le winner si la phase est encore active.
  Future<void> submitWin(String matchId) async {
    final uid = currentUid;
    final ref = _matchRef(matchId);
    final now = DateTime.now().millisecondsSinceEpoch;

    final snapshot = await ref.get();
    if (!snapshot.exists) return;
    final data = (snapshot.value! as Map).cast<String, dynamic>();
    final phase = data['phase'] as String? ?? 'waiting';
    if (phase == DuelPhase.finished.name) return;

    // Atomic-ish update: marquer joueur + phase + winner.
    await ref.update(<String, Object?>{
      'players/$uid/found': true,
      'players/$uid/finished_at': now,
      'players/$uid/progress': 1.0,
      'phase': DuelPhase.finished.name,
      'winner': uid,
    });
  }

  /// Abandon — déclare l'autre joueur gagnant si présent.
  Future<void> forfeit(String matchId) async {
    final uid = currentUid;
    final ref = _matchRef(matchId);
    final snapshot = await ref.get();
    if (!snapshot.exists) return;
    final data = (snapshot.value! as Map).cast<String, dynamic>();
    if ((data['phase'] as String?) == DuelPhase.finished.name) return;

    final players =
        (data['players'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    final otherUid =
        players.keys.firstWhere((k) => k != uid, orElse: () => '');
    await ref.update(<String, Object?>{
      'phase': DuelPhase.finished.name,
      if (otherUid.isNotEmpty) 'winner': otherUid,
    });
  }

  /// Rejoint un match ouvert (deep link / share) sans vérification de secret.
  ///
  /// Vérifie que le match :
  /// - existe
  /// - est en phase [DuelPhase.waiting]
  /// - n'a qu'un seul joueur (le créateur), ou que l'uid courant est déjà
  ///   dedans (retour tolérant).
  ///
  /// Lance un [StateError] en cas d'erreur (match introuvable, plein,
  /// ou déjà terminé).
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
        'players/$uid':
            const DuelPlayer(uid: 'self', progress: 0).toJson()
              ..remove('finished_at'),
        'phase': DuelPhase.active.name,
      });
    }
    _log.i('joinOpen: $matchId par $uid');

    // Relis la session mise à jour.
    final updated = await ref.get();
    return DuelSession.fromJson(
      matchId,
      (updated.value! as Map).cast<String, dynamic>(),
    );
  }

  /// Supprime la session (créateur seulement).
  Future<void> deleteIfOwner(String matchId) async {
    final uid = currentUid;
    final snapshot = await _matchRef(matchId).get();
    if (!snapshot.exists) return;
    final data = (snapshot.value! as Map).cast<String, dynamic>();
    if (data['created_by'] == uid) {
      await _matchRef(matchId).remove();
    }
  }

  static List<String> _shuffle(List<String> letters) {
    final list = List<String>.from(letters);
    final rng = Random.secure();
    for (var i = list.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }
}

final firebaseDatabaseProvider = Provider<FirebaseDatabase>((ref) {
  return FirebaseDatabase.instance;
});

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final duelRepositoryProvider = Provider<DuelRepository>((ref) {
  return DuelRepository(
    database: ref.watch(firebaseDatabaseProvider),
    auth: ref.watch(firebaseAuthProvider),
    devinetteRepo: ref.watch(devinetteRepositoryProvider),
  );
});

/// Stream typé d'une session de duel.
final duelSessionStreamProvider =
    StreamProvider.family<DuelSession?, String>((ref, matchId) {
  return ref.watch(duelRepositoryProvider).watch(matchId);
});

/// Devinette mock pour conversion entre DuelSession et entité de jeu si
/// jamais on veut réutiliser des widgets existants. Pour l'instant le
/// duel game widget consomme directement DuelSession.
Devinette devinetteFromDuel(DuelSession session) {
  return Devinette(
    id: 'duel_${session.matchId}',
    pack: 'duel',
    country: 'ci',
    answer: session.answer,
    lettersPool: session.lettersPool,
    // v3 schema: monolingual duel payload wrapped under active locale.
    riddleByLang: <String, String>{
      DevinetteLocale.activeLang: session.riddle,
    },
    explanationByLang: <String, String>{
      DevinetteLocale.activeLang: session.explanation,
    },
    difficulty: 1,
    estimatedTimeS: 30,
    tags: const ['duel'],
  );
}
