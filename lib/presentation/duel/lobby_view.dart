import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/presentation/duel/lobby_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Hero tag partagé entre HubView, LobbyView et ProfileView pour la chip
/// "Altitude X m". Donne une continuité visuelle à travers les écrans.
const kAltitudeHeroTag = 'player-altitude-chip';

/// Écran lobby du matchmaking ELO (Phase 6).
///
/// Trois états :
/// - [LobbyPhase.searching] : **radar** (ondes + balayage) autour de ton avatar + bande ELO.
/// - [LobbyPhase.matched] : flash doré + transition crossfade vers [AppRoutes.duelPlay].
/// - [LobbyPhase.noOpponent] : griot pensif + 2 CTA slide-up.
class LobbyView extends ConsumerStatefulWidget {
  const LobbyView({super.key});

  @override
  ConsumerState<LobbyView> createState() => _LobbyViewState();
}

class _LobbyViewState extends ConsumerState<LobbyView>
    with TickerProviderStateMixin {
  /// Animation du flash doré (matched state).
  late final AnimationController _flashCtrl;
  late final Animation<double> _flashOpacity;

  /// Animation slide-up du noOpponent body.
  late final AnimationController _slideCtrl;

  @override
  void initState() {
    super.initState();

    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _flashOpacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut));

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _flashCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lobbyState = ref.watch(lobbyControllerProvider);
    final profileAsync = ref.watch(playerProfileStreamProvider);
    final myElo = profileAsync.value?.elo ?? 1000;

    // Réactions aux changements de phase.
    ref.listen<LobbyState>(lobbyControllerProvider, (prev, next) {
      _onPhaseChanged(prev?.phase, next);
    });

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ref.read(lobbyControllerProvider.notifier).cancelSearch();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.vertForet,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _LobbyHeader(myElo: myElo),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: switch (lobbyState.phase) {
                        LobbyPhase.searching ||
                        LobbyPhase.matched => _SearchingBody(
                          key: const ValueKey('searching'),
                          state: lobbyState,
                          myElo: myElo,
                        ),
                        LobbyPhase.noOpponent => _NoOpponentBody(
                          key: const ValueKey('noOpponent'),
                          slideCtrl: _slideCtrl,
                          isRematch: lobbyState.isRematch,
                          wasDeclined:
                              lobbyState.errorMessage == 'declined',
                          isOutdated:
                              lobbyState.errorMessage == 'outdated',
                        ),
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Flash doré sur la transition matched → duel.
            AnimatedBuilder(
              animation: _flashOpacity,
              builder: (_, __) => IgnorePointer(
                child: Container(
                  color: AppColors.orSoleil.withValues(
                    alpha: _flashOpacity.value * 0.55,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onPhaseChanged(LobbyPhase? prev, LobbyState next) {
    if (prev == next.phase) return;

    if (next.phase == LobbyPhase.noOpponent && prev != LobbyPhase.noOpponent) {
      // Déclenche le slide-up des boutons.
      _slideCtrl.forward(from: 0);
    }

    if (next.phase == LobbyPhase.matched && next.matchedSession != null) {
      // Flash doré → pause → navigate.
      _flashCtrl.forward().then((_) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          context.go(AppRoutes.duelPlay, extra: next.matchedSession);
        });
      });
    }
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _LobbyHeader extends StatelessWidget {
  const _LobbyHeader({required this.myElo});
  final int myElo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.orSoleil.withValues(alpha: 0.2)),
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
          // Hero partagé avec ProfileView et DuelResultView.
          Hero(
            tag: kAltitudeHeroTag,
            child: _AltitudeChip(elo: myElo),
          ),
        ],
      ),
    );
  }
}

class _AltitudeChip extends StatelessWidget {
  const _AltitudeChip({required this.elo});
  final int elo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orSoleil.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.terrain, size: 14, color: AppColors.orSoleil),
          const SizedBox(width: 4),
          Text(
            '$elo m',
            style: AppTypography.bebas(size: 14, color: AppColors.orSoleil),
          ),
        ],
      ),
    );
  }
}

// ─── Searching body ───────────────────────────────────────────────────────────

class _SearchingBody extends ConsumerWidget {
  const _SearchingBody({required this.state, required this.myElo, super.key});

  final LobbyState state;
  final int myElo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(playerProfileStreamProvider).value;
    final name = profile?.displayName?.trim();
    final initial =
        (name != null && name.isNotEmpty) ? name[0].toUpperCase() : '?';
    final title = state.isRematch
        ? 'Défi envoyé — en attente…'
        : "Recherche d'un adversaire…";

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Radar : ondes concentriques + balayage rotatif autour de l'avatar.
          _RadarSearch(initial: initial),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.bebas(size: 19),
          ),
          const SizedBox(height: 6),
          Text(
            'À ta hauteur · $myElo m',
            textAlign: TextAlign.center,
            style: AppTypography.crimson(
              size: 14,
              color: AppColors.texteSecondaire,
              style: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 28),
          // Bande ELO visuelle (zone de recherche).
          _BandExpansionBar(state: state),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                await ref.read(lobbyControllerProvider.notifier).cancelSearch();
                if (!context.mounted) return;
                context.pop();
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                'ANNULER',
                style: AppTypography.bebas(color: AppColors.error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Radar de recherche d'adversaire ─────────────────────────────────────────

/// Radar « scan du monde » : ondes concentriques qui se propagent + balayage
/// rotatif doré autour de ton avatar. Remplace l'ancien anneau de décompte +
/// emoji tam-tam. Aucun `MaskFilter.blur` (perf iOS 26).
class _RadarSearch extends StatefulWidget {
  const _RadarSearch({required this.initial});

  final String initial;

  @override
  State<_RadarSearch> createState() => _RadarSearchState();
}

class _RadarSearchState extends State<_RadarSearch>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2700),
    )..repeat();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 190,
        height: 190,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_pulse, _sweep]),
              builder: (_, __) => CustomPaint(
                size: const Size(190, 190),
                painter: _RadarPainter(
                  pulseT: _pulse.value,
                  sweep: _sweep.value * 2 * math.pi,
                ),
              ),
            ),
            // Cœur : ton avatar (initiale) sur disque or lumineux.
            Container(
              width: 86,
              height: 86,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.3, -0.35),
                  colors: [AppColors.orJour, AppColors.orCrepuscule],
                ),
                border: Border.all(color: AppColors.orJour, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.orJour.withValues(alpha: 0.5),
                    blurRadius: 26,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Text(
                widget.initial,
                style: AppTypography.playfair(
                  size: 32,
                  color: AppColors.surface,
                  weight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.pulseT, required this.sweep});

  /// Phase 0..1 des ondes concentriques.
  final double pulseT;

  /// Angle du balayage en radians.
  final double sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.width / 2;
    final ringRect = Rect.fromCircle(center: c, radius: maxR * 0.96);

    canvas
      // Anneau statique discret.
      ..drawCircle(
        c,
        maxR * 0.96,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.orJour.withValues(alpha: 0.18),
      )
      // Balayage rotatif (secteur dégradé).
      ..drawCircle(
        c,
        maxR * 0.96,
        Paint()
          ..shader = SweepGradient(
            colors: [
              AppColors.orJour.withValues(alpha: 0.38),
              AppColors.orJour.withValues(alpha: 0),
            ],
            stops: const [0, 0.25],
            transform: GradientRotation(sweep),
          ).createShader(ringRect),
      );

    // Ondes concentriques (3 anneaux déphasés).
    for (var i = 0; i < 3; i++) {
      final p = (pulseT + i / 3) % 1.0;
      final r = maxR * (0.20 + 0.78 * p);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.orJour.withValues(alpha: 0.5 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.pulseT != pulseT || old.sweep != sweep;
}

// ─── Band expansion bar (visual slider) ──────────────────────────────────────

class _BandExpansionBar extends StatelessWidget {
  const _BandExpansionBar({required this.state});
  final LobbyState state;

  // Nombre max de steps affichés avant que la barre soit "pleine".
  static const _maxSteps = 4;

  @override
  Widget build(BuildContext context) {
    final step = state.expansionStep.clamp(0, _maxSteps);
    final fraction = step / _maxSteps;
    final radius = state.bandRadius;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Zone de recherche',
              style: AppTypography.crimson(
                size: 12,
                color: AppColors.texteSecondaire,
              ),
            ),
            Text(
              '±$radius m',
              style: AppTypography.bebas(size: 13, color: AppColors.vertClair),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Slider visuel.
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              // Fond.
              Container(
                height: 8,
                color: AppColors.boisFonce.withValues(alpha: 0.5),
              ),
              // Remplissage animé.
              AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                widthFactor: 0.15 + fraction * 0.85, // commence à 15% min.
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.vertClair,
                        AppColors.orChaud.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── No opponent body ─────────────────────────────────────────────────────────

class _NoOpponentBody extends ConsumerWidget {
  const _NoOpponentBody({
    required this.slideCtrl,
    required this.isRematch,
    this.wasDeclined = false,
    this.isOutdated = false,
    super.key,
  });

  final AnimationController slideCtrl;
  final bool isRematch;

  /// True quand l'adversaire a explicitement refuse le rematch (vs timeout).
  final bool wasDeclined;

  /// True quand le serveur a rejeté ce client (build trop ancien pour le
  /// contrat duel — barrière de version).
  final bool isOutdated;

  String _bodyText() {
    if (isOutdated) {
      return "Cette version de l'app n'est plus compatible avec le Défi en ligne.\nMets-la à jour pour rejouer !";
    }
    if (wasDeclined) {
      return "Ton adversaire n'a pas accepté ce duel.\nPropose-en un autre !";
    }
    if (isRematch) {
      return "Ton adversaire n'a pas répondu à temps.\nRetente ta chance !";
    }
    return 'Personne dans ton altitude pour le moment.\nReviens dans quelques instants !';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          // Griot pensif fade-in.
          FadeTransition(
            opacity: slideCtrl,
            child: Image.asset(AppAssets.griotIdle, width: 120, height: 120),
          ),
          const SizedBox(height: 24),
          FadeTransition(
            opacity: slideCtrl,
            child: Text(
              isOutdated
                  ? 'MISE À JOUR REQUISE'
                  : wasDeclined
                      ? 'DÉFI REFUSÉ'
                      : 'PERSONNE DISPONIBLE',
              style: AppTypography.bebas(size: 22, color: AppColors.orSoleil),
            ),
          ),
          const SizedBox(height: 8),
          FadeTransition(
            opacity: slideCtrl,
            child: Text(
              _bodyText(),
              textAlign: TextAlign.center,
              style: AppTypography.crimson(
                size: 14,
                style: FontStyle.italic,
              ),
            ),
          ),
          const Spacer(),
          // CTA 1 : RÉESSAYER — slide-up depuis le bas.
          _SlideUpButton(
            controller: slideCtrl,
            delay: 0,
            child: SizedBox(
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
                  style: AppTypography.bebas(
                    size: 18,
                    color: AppColors.vertForet,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // CTA 2 : GRAVIR UN SOMMET — décalé 100ms.
          _SlideUpButton(
            controller: slideCtrl,
            delay: 0.25, // 25% dans l'animation = ~100ms de décalage
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.go(AppRoutes.mountains),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.orSoleil),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  'GRAVIR UN SOMMET',
                  style: AppTypography.bebas(
                    size: 18,
                    color: AppColors.orSoleil,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wrapper qui fait apparaître son enfant en slide-up depuis le bas.
/// [delay] : 0.0–1.0, fraction de l'animation [controller] avant de démarrer.
class _SlideUpButton extends StatelessWidget {
  const _SlideUpButton({
    required this.controller,
    required this.delay,
    required this.child,
  });

  final AnimationController controller;
  final double delay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final begin = delay.clamp(0.0, 0.99);
    final end = (begin + (1 - begin)).clamp(begin + 0.01, 1.0);

    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(begin, end, curve: Curves.easeOut),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 30 * (1 - animation.value)),
        child: Opacity(opacity: animation.value, child: child),
      ),
      child: child,
    );
  }
}
