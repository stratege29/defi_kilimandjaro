import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/presentation/duel/lobby_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran lobby du matchmaking ELO (Phase 6).
///
/// Trois états :
/// - [LobbyPhase.searching] : animation pulsante + compteur d'expansion bande.
/// - [LobbyPhase.matched] : transition automatique vers [AppRoutes.duelPlay].
/// - [LobbyPhase.noOpponent] : visuel calme avec CTA "RÉESSAYER" et
///   "GRAVIR UN SOMMET" qui navigue vers [AppRoutes.mountains].
class LobbyView extends ConsumerStatefulWidget {
  const LobbyView({super.key});

  @override
  ConsumerState<LobbyView> createState() => _LobbyViewState();
}

class _LobbyViewState extends ConsumerState<LobbyView> {
  @override
  Widget build(BuildContext context) {
    final lobbyState = ref.watch(lobbyControllerProvider);
    final profileAsync = ref.watch(playerProfileStreamProvider);
    final myElo = profileAsync.value?.elo ?? 1000;

    // Naviguer automatiquement quand le match est trouvé.
    ref.listen<LobbyState>(lobbyControllerProvider, (_, next) {
      final session = next.matchedSession;
      if (next.phase == LobbyPhase.matched && session != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          context.go(AppRoutes.duelPlay, extra: session);
        });
      }
    });

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ref.read(lobbyControllerProvider.notifier).cancelSearch();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.vertForet,
        body: SafeArea(
          child: Column(
            children: [
              _LobbyHeader(myElo: myElo),
              Expanded(
                child: switch (lobbyState.phase) {
                  LobbyPhase.searching ||
                  LobbyPhase.matched =>
                    _SearchingBody(state: lobbyState, myElo: myElo),
                  LobbyPhase.noOpponent => const _NoOpponentBody(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — titre + altitude courante
// ---------------------------------------------------------------------------

class _LobbyHeader extends StatelessWidget {
  const _LobbyHeader({required this.myElo});
  final int myElo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.orSoleil.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.ivoire),
            onPressed: () => context.pop(),
          ),
          Text(
            'DÉFI EN LIGNE',
            style: AppTypography.bebas(size: 20, color: AppColors.orSoleil),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.bois.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.orSoleil.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.terrain, size: 14, color: AppColors.orSoleil),
                const SizedBox(width: 4),
                Text(
                  '$myElo m',
                  style: AppTypography.bebas(size: 14, color: AppColors.orSoleil),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Searching body — animation tam-tam + infos bande ELO
// ---------------------------------------------------------------------------

class _SearchingBody extends ConsumerWidget {
  const _SearchingBody({required this.state, required this.myElo});

  final LobbyState state;
  final int myElo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = (30 - state.secondsElapsed).clamp(0, 30);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _PulsingDrum(),
          const SizedBox(height: 32),
          Text(
            'Altitude actuelle : $myElo m',
            style: AppTypography.bebas(color: AppColors.orSoleil),
          ),
          const SizedBox(height: 8),
          Text(
            "Recherche d'un grimpeur de niveau similaire…",
            textAlign: TextAlign.center,
            style: AppTypography.crimson(
              size: 15,
              color: AppColors.ivoire.withValues(alpha: 0.85),
              style: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
          _BandExpansionChip(state: state),
          const SizedBox(height: 8),
          Text(
            'Temps restant : ${remaining}s',
            style: AppTypography.bebas(
              size: 13,
              color: AppColors.ivoire.withValues(alpha: 0.6),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                await ref
                    .read(lobbyControllerProvider.notifier)
                    .cancelSearch();
                if (!context.mounted) return;
                context.pop();
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.rouge),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                'ANNULER',
                style: AppTypography.bebas(color: AppColors.rouge),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pulsing drum animation (cercles concentriques)
// ---------------------------------------------------------------------------

class _PulsingDrum extends StatefulWidget {
  const _PulsingDrum();

  @override
  State<_PulsingDrum> createState() => _PulsingDrumState();
}

class _PulsingDrumState extends State<_PulsingDrum>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.4, end: 0.85).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        return SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _Ring(
                diameter: 100 * _scale.value,
                color: AppColors.orSoleil,
                opacity: _opacity.value * 0.12,
              ),
              _Ring(
                diameter: 80 * _scale.value,
                color: AppColors.orSoleil,
                opacity: _opacity.value * 0.22,
              ),
              _Ring(
                diameter: 60 * _scale.value,
                color: AppColors.orSoleil,
                opacity: _opacity.value * 0.35,
              ),
              Transform.scale(scale: _scale.value, child: child),
            ],
          ),
        );
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.bois.withValues(alpha: 0.4),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.orSoleil.withValues(alpha: 0.8),
            width: 2,
          ),
        ),
        child: const Icon(
          Icons.music_note,
          color: AppColors.orSoleil,
          size: 30,
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.diameter,
    required this.color,
    required this.opacity,
  });

  final double diameter;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Band expansion chip
// ---------------------------------------------------------------------------

class _BandExpansionChip extends StatelessWidget {
  const _BandExpansionChip({required this.state});
  final LobbyState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.boisFonce.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.vertClair.withValues(alpha: 0.5)),
      ),
      child: Text(
        'Bande de recherche : ±${state.bandRadius} m',
        style: AppTypography.bebas(size: 13, color: AppColors.vertClair),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// No opponent body — griot pensif + deux CTA
// ---------------------------------------------------------------------------

class _NoOpponentBody extends ConsumerWidget {
  const _NoOpponentBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(AppAssets.griotIdle, width: 120, height: 120),
          const SizedBox(height: 24),
          Text(
            'PERSONNE DISPONIBLE',
            style: AppTypography.bebas(size: 22, color: AppColors.orSoleil),
          ),
          const SizedBox(height: 8),
          Text(
            'Personne dans ton altitude pour le moment.\nReviens dans quelques instants !',
            textAlign: TextAlign.center,
            style: AppTypography.crimson(
              size: 14,
              color: AppColors.ivoire.withValues(alpha: 0.8),
              style: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () =>
                  ref.read(lobbyControllerProvider.notifier).retry(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.vertClair,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                'RÉESSAYER',
                style: AppTypography.bebas(size: 18, color: AppColors.vertForet),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.go(AppRoutes.mountains),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.orSoleil),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                'GRAVIR UN SOMMET',
                style: AppTypography.bebas(size: 18, color: AppColors.orSoleil),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
