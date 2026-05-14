import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran de transition affiché quand l'app s'ouvre depuis un deep link
/// `kilimandjaro://duel/<matchId>`.
///
/// Étapes :
/// 1. Attend que Firebase Auth ait un utilisateur (cold start).
/// 2. Appelle [DuelRepository.joinOpen] pour rejoindre le match.
/// 3. Si succès → navigue vers [AppRoutes.duelPlay].
/// 4. Si erreur → affiche un message et propose de retourner au hub.
class DuelDeepLinkView extends ConsumerStatefulWidget {
  const DuelDeepLinkView({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<DuelDeepLinkView> createState() => _DuelDeepLinkViewState();
}

class _DuelDeepLinkViewState extends ConsumerState<DuelDeepLinkView> {
  _JoinState _state = const _Joining();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _join());
  }

  Future<void> _join() async {
    // Attend l'auth si nécessaire (cold start sans session active).
    final auth = ref.read(firebaseAuthProvider);
    if (auth.currentUser == null) {
      try {
        await auth
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 12));
      } on Exception {
        if (!mounted) return;
        setState(() => _state = _Error(_errorLabel('auth_timeout')));
        return;
      }
    }

    if (!mounted) return;

    try {
      final session = await ref
          .read(duelRepositoryProvider)
          .joinOpen(widget.matchId);
      if (!mounted) return;
      context.go(AppRoutes.duelPlay, extra: session);
    } on Exception catch (e) {
      if (!mounted) return;
      // joinOpen wraps error codes in the exception message.
      setState(() => _state = _Error(_errorLabel('$e')));
    }
  }

  String _errorLabel(String rawMessage) {
    if (rawMessage.contains('duel_not_found')) {
      return 'Ce défi est introuvable.';
    }
    if (rawMessage.contains('duel_expired')) {
      return 'Ce défi est déjà terminé.';
    }
    if (rawMessage.contains('duel_full')) {
      return 'Ce défi est complet (2/2 joueurs).';
    }
    if (rawMessage.contains('auth_timeout')) {
      return 'Connexion trop lente. Réessaie.';
    }
    return 'Impossible de rejoindre le défi.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: switch (_state) {
              _Joining() => _buildLoading(),
              _Error(:final message) => _buildError(message),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            color: AppColors.orSoleil,
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Connexion au défi...',
          style: AppTypography.bebas(size: 20, color: AppColors.orSoleil),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          widget.matchId,
          style: AppTypography.crimson(
            size: 13,
            color: AppColors.texteTertiaire,
          ),
        ),
      ],
    );
  }

  Widget _buildError(String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: AppColors.rouge, size: 56),
        const SizedBox(height: 20),
        Text(
          'Défi indisponible',
          style: AppTypography.bebas(size: 24, color: AppColors.rouge),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          message,
          style: AppTypography.crimson(
            size: 14,
            color: AppColors.textePrimaire,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => context.go(AppRoutes.hub),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.vertClair,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              'RETOUR AU HUB',
              style: AppTypography.bebas(size: 18, color: AppColors.vertForet),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// État interne
// ---------------------------------------------------------------------------

sealed class _JoinState {
  const _JoinState();
}

final class _Joining extends _JoinState {
  const _Joining();
}

final class _Error extends _JoinState {
  const _Error(this.message);
  final String message;
}
