import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/presentation/duel/lobby_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Affiche l'overlay quickmatch ELO sur le contexte courant.
///
/// Au lieu de pousser `/duel/lobby` (écran plein), cette modale déclenche
/// le même `lobbyControllerProvider` mais l'expose en surimpression de
/// l'écran d'accueil. Quand un adversaire est trouvé, la modale se ferme
/// d'elle-même et navigue vers `/duel/play`. Si aucun adversaire n'est
/// trouvé en 30 s, la modale affiche un fallback retry/cancel.
///
/// Le `lobbyControllerProvider` étant `autoDispose`, son cycle de vie est
/// lié à l'arbre du dialogue — pas de fuite de timer/listener RTDB après
/// la fermeture.
Future<void> showQuickmatchOverlay(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: AppColors.vertForet.withValues(alpha: 0.82),
    builder: (_) => const _QuickmatchDialog(),
  );
}

class _QuickmatchDialog extends ConsumerStatefulWidget {
  const _QuickmatchDialog();

  @override
  ConsumerState<_QuickmatchDialog> createState() => _QuickmatchDialogState();
}

class _QuickmatchDialogState extends ConsumerState<_QuickmatchDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  bool _navigatedAway = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _close([VoidCallback? then]) {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    then?.call();
  }

  Future<void> _cancel() async {
    await ref.read(lobbyControllerProvider.notifier).cancelSearch();
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final lobbyState = ref.watch(lobbyControllerProvider);
    final profileAsync = ref.watch(playerProfileStreamProvider);
    final myElo = profileAsync.value?.elo ?? 1000;

    // Réagit aux changements de phase pour navigation auto.
    ref.listen<LobbyState>(lobbyControllerProvider, (prev, next) {
      if (_navigatedAway) return;
      if (next.phase == LobbyPhase.matched &&
          next.matchedSession != null &&
          prev?.phase != LobbyPhase.matched) {
        _navigatedAway = true;
        final session = next.matchedSession!;
        _close(() => context.go(AppRoutes.duelPlay, extra: session));
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _cancel();
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          decoration: BoxDecoration(
            color: AppColors.vertForet,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.orSoleil.withValues(alpha: 0.55),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.orSoleil.withValues(alpha: 0.18),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: switch (lobbyState.phase) {
            LobbyPhase.searching ||
            LobbyPhase.matched =>
              _SearchingBody(
                state: lobbyState,
                myElo: myElo,
                pulse: _pulseCtrl,
                onCancel: _cancel,
              ),
            LobbyPhase.noOpponent => _NoOpponentBody(
                onRetry: () =>
                    ref.read(lobbyControllerProvider.notifier).retry(),
                onCancel: _close,
              ),
          },
        ),
      ),
    );
  }
}

class _SearchingBody extends StatelessWidget {
  const _SearchingBody({
    required this.state,
    required this.myElo,
    required this.pulse,
    required this.onCancel,
  });

  final LobbyState state;
  final int myElo;
  final AnimationController pulse;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final remaining = (30 - state.secondsElapsed).clamp(0, 30);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "RECHERCHE D'UN GRIMPEUR",
          style: AppTypography.bebas(size: 18, color: AppColors.orSoleil),
        ),
        const SizedBox(height: 4),
        Text(
          'Ton altitude · $myElo m',
          style: AppTypography.crimson(
            size: 12,
            color: AppColors.texteSecondaire,
            style: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 22),
        ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1.08).animate(
            CurvedAnimation(parent: pulse, curve: Curves.easeInOut),
          ),
          child: Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.orSoleil.withValues(alpha: 0.18),
              border: Border.all(
                color: AppColors.orSoleil.withValues(alpha: 0.75),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.bolt,
              size: 44,
              color: AppColors.orSoleil,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.bois.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.orSoleil.withValues(alpha: 0.4)),
          ),
          child: Text(
            'Rayon ±${state.bandRadius} m · $remaining s',
            style: AppTypography.bebas(size: 13, color: AppColors.orSoleil),
          ),
        ),
        const SizedBox(height: 22),
        TextButton(
          onPressed: onCancel,
          child: Text(
            'ANNULER',
            style: AppTypography.bebas(
              size: 14,
              color: AppColors.texteSecondaire,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoOpponentBody extends StatelessWidget {
  const _NoOpponentBody({required this.onRetry, required this.onCancel});

  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.terrain,
          size: 48,
          color: AppColors.texteSecondaire,
        ),
        const SizedBox(height: 12),
        Text(
          'AUCUN GRIMPEUR EN VUE',
          style: AppTypography.bebas(size: 18, color: AppColors.orSoleil),
        ),
        const SizedBox(height: 6),
        Text(
          'Le sommet est calme. Réessaie dans un instant ou défie un ami.',
          textAlign: TextAlign.center,
          style: AppTypography.crimson(
            size: 13,
            color: AppColors.texteSecondaire,
            style: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: onCancel,
                child: Text(
                  'FERMER',
                  style: AppTypography.bebas(
                    size: 14,
                    color: AppColors.texteSecondaire,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.orSoleil.withValues(alpha: 0.18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: AppColors.orSoleil.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                child: Text(
                  'RÉESSAYER',
                  style: AppTypography.bebas(
                    size: 14,
                    color: AppColors.orSoleil,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
