import 'dart:async';

import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/matchmaking_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';

/// Listener global RTDB sur `pending_challenges/{currentUid}`.
///
/// Affiche un dialog modal in-app quand un challenge async arrive (rematch
/// envoye par un autre joueur). Pattern Discord game invite — l'utilisateur
/// voit immediatement la demande au lieu d'esperer voir la notif FCM dans
/// le system tray.
///
/// A monter une seule fois dans l'arbre, au-dessus du MaterialApp.router
/// (typiquement dans `_BootGate`).
///
/// Le widget retourne uniquement [child] — il n'a pas de rendu visuel propre.
/// Le dialog est affiche via le Navigator global (via `appRouterNavigatorKey`).
class IncomingChallengeListener extends ConsumerStatefulWidget {
  const IncomingChallengeListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<IncomingChallengeListener> createState() =>
      _IncomingChallengeListenerState();
}

class _IncomingChallengeListenerState
    extends ConsumerState<IncomingChallengeListener> {
  final Logger _log = Logger();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DatabaseEvent>? _challengeSub;

  /// MatchId du challenge actuellement affiche dans le dialog.
  /// Sert d'anti-doublon (le listener peut re-fire avec la meme valeur).
  String? _shownMatchId;

  @override
  void initState() {
    super.initState();
    // L'uid peut ne pas etre present au boot (anonymous sign-in async).
    // On observe authStateChanges et on (re-)attache le listener RTDB
    // quand un user devient disponible.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _attachChallengeListener(user?.uid);
    });
  }

  void _attachChallengeListener(String? uid) {
    unawaited(_challengeSub?.cancel());
    _challengeSub = null;
    if (uid == null) return;

    _challengeSub = FirebaseDatabase.instance
        .ref('pending_challenges/$uid')
        .onValue
        .listen((event) async {
      final value = event.snapshot.value;
      if (value is! Map) {
        // Node supprime (challenge accepte/refuse/expire) → reset.
        _shownMatchId = null;
        return;
      }
      final data = Map<String, dynamic>.from(value);
      final matchId = data['matchId'] as String?;
      if (matchId == null || matchId == _shownMatchId) return;

      _shownMatchId = matchId;
      final fromName = (data['fromName'] as String?) ?? 'Un grimpeur';
      _log.i('[Challenge] Recu: matchId=$matchId from=$fromName');

      await _showChallengeDialog(matchId: matchId, fromName: fromName);
    });
  }

  Future<void> _showChallengeDialog({
    required String matchId,
    required String fromName,
  }) async {
    final navContext = appRouterNavigatorKey.currentContext;
    if (navContext == null) return;

    final accepted = await showDialog<bool>(
      context: navContext,
      barrierDismissible: false,
      builder: (dialogContext) => _ChallengeDialog(fromName: fromName),
    );

    if (!mounted) return;

    final matchmakingRepo = ref.read(matchmakingRepositoryProvider);
    final duelRepo = ref.read(duelRepositoryProvider);

    if (accepted ?? false) {
      try {
        // 1. Reponse serveur — cleanup pending_challenges.
        await matchmakingRepo.respondToChallenge(
          matchId: matchId,
          accept: true,
        );
        // 2. Rejoindre le match (ecrit players + phase=countdown).
        final session = await duelRepo.joinOpen(matchId);
        if (!mounted) return;
        // 3. Naviguer vers le duel.
        // Context global via GlobalKey (pas un State.context) — pas
        // d'API mounted dispo dessus, le check `mounted` au-dessus
        // garantit que le State (et donc l'arbre) est encore valide.
        final goCtx = appRouterNavigatorKey.currentContext;
        if (goCtx == null) return;
        // ignore: use_build_context_synchronously
        GoRouter.of(goCtx).go(AppRoutes.duelPlay, extra: session);
      } on Exception catch (e) {
        _log.e('[Challenge] Accept failed', error: e);
        if (!mounted) return;
        _showError('Impossible de rejoindre : $e');
      }
    } else {
      // Refus ou dialog dismiss (bouton refuser).
      try {
        await matchmakingRepo.respondToChallenge(
          matchId: matchId,
          accept: false,
        );
      } on Exception catch (e) {
        _log.e('[Challenge] Decline failed', error: e);
      }
    }
    // Le _shownMatchId sera reset au prochain onValue (node supprime cote
    // serveur dans les 2 cas).
  }

  void _showError(String msg) {
    final ctx = appRouterNavigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppTypography.bebas()),
        backgroundColor: AppColors.rouge,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_authSub?.cancel());
    unawaited(_challengeSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ---------------------------------------------------------------------------
// Dialog modal — affiche le challenge recu avec Accepter / Refuser.
// ---------------------------------------------------------------------------

class _ChallengeDialog extends StatelessWidget {
  const _ChallengeDialog({required this.fromName});

  final String fromName;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.vertForet,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: AppColors.orSoleil.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.flash_on,
              color: AppColors.orSoleil,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              'TU AS UN DÉFI !',
              style: AppTypography.bebas(size: 24, color: AppColors.orSoleil),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              '$fromName te lance un duel.\nTu acceptes le combat ?',
              style: AppTypography.crimson(
                size: 15,
                color: AppColors.textePrimaire,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.rouge),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'REFUSER',
                      style: AppTypography.bebas(color: AppColors.rouge),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.vertClair,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'ACCEPTER',
                      style: AppTypography.bebas(color: AppColors.vertForet),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
