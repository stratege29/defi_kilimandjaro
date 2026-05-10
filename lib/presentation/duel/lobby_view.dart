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

// ─── Constantes de timing ────────────────────────────────────────────────────

/// Durée du timeout lobby en secondes (doit correspondre à
/// [LobbyController._timeoutSeconds]).
const _kLobbyTimeoutSeconds = 30;

/// BPM du tam-tam lobby — 108 BPM → 556 ms par beat.
const _kLobbyBpm = 108.0;
const _kLobbyBeatMs = 60000 / _kLobbyBpm; // ~556 ms

/// Écran lobby du matchmaking ELO (Phase 6).
///
/// Trois états :
/// - [LobbyPhase.searching] : tam-tam animé + anneau countdown + bande ELO.
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
    _flashOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut),
    );

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
                        LobbyPhase.matched =>
                          _SearchingBody(
                            key: const ValueKey('searching'),
                            state: lobbyState,
                            myElo: myElo,
                          ),
                        LobbyPhase.noOpponent => _NoOpponentBody(
                            key: const ValueKey('noOpponent'),
                            slideCtrl: _slideCtrl,
                            isRematch: lobbyState.isRematch,
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
                  color: AppColors.orSoleil
                      .withValues(alpha: _flashOpacity.value * 0.55),
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
  const _SearchingBody({
    required this.state,
    required this.myElo,
    super.key,
  });

  final LobbyState state;
  final int myElo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining =
        (_kLobbyTimeoutSeconds - state.secondsElapsed).clamp(0, _kLobbyTimeoutSeconds);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Tam-tam animé avec anneau countdown.
          _CountdownRing(
            secondsRemaining: remaining,
            totalSeconds: _kLobbyTimeoutSeconds,
            child: const _TamTamMascot(),
          ),
          const SizedBox(height: 32),
          Text(
            'Altitude actuelle : $myElo m',
            style: AppTypography.bebas(color: AppColors.orSoleil),
          ),
          if (state.isRematch) ...[
            const SizedBox(height: 4),
            Text(
              'Recherche de ton dernier adversaire…',
              textAlign: TextAlign.center,
              style: AppTypography.crimson(
                size: 13,
                color: AppColors.orSoleil.withValues(alpha: 0.75),
                style: FontStyle.italic,
              ),
            ),
          ] else
            const SizedBox(height: 4),
          Text(
            "Recherche d'un grimpeur de niveau similaire…",
            textAlign: TextAlign.center,
            style: AppTypography.crimson(
              size: 15,
              color: AppColors.ivoire.withValues(alpha: 0.85),
              style: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 28),
          // Bande ELO visuelle.
          _BandExpansionBar(state: state),
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

// ─── Countdown ring (CustomPainter) ──────────────────────────────────────────

class _CountdownRing extends StatelessWidget {
  const _CountdownRing({
    required this.secondsRemaining,
    required this.totalSeconds,
    required this.child,
  });

  final int secondsRemaining;
  final int totalSeconds;
  final Widget child;

  Color _ringColor() {
    if (secondsRemaining > 15) return AppColors.vertClair;
    if (secondsRemaining > 5) return AppColors.orChaud;
    return AppColors.rouge;
  }

  @override
  Widget build(BuildContext context) {
    final progress = secondsRemaining / totalSeconds;
    final color = _ringColor();

    return SizedBox(
      width: 170,
      height: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Anneau de fond.
          CustomPaint(
            size: const Size(170, 170),
            painter: _RingPainter(
              progress: 1,
              color: AppColors.boisFonce.withValues(alpha: 0.35),
            ),
          ),
          // Anneau de progression animé.
          AnimatedCustomPaint(
            progress: progress,
            color: color,
          ),
          child,
        ],
      ),
    );
  }
}

class AnimatedCustomPaint extends ImplicitlyAnimatedWidget {
  const AnimatedCustomPaint({
    required this.progress,
    required this.color,
    super.key,
  }) : super(duration: const Duration(milliseconds: 800));

  final double progress;
  final Color color;

  @override
  ImplicitlyAnimatedWidgetState<AnimatedCustomPaint> createState() =>
      _AnimatedCustomPaintState();
}

class _AnimatedCustomPaintState
    extends AnimatedWidgetBaseState<AnimatedCustomPaint> {
  Tween<double>? _progress;
  ColorTween? _color;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _progress = visitor(
      _progress,
      widget.progress,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;
    _color = visitor(
      _color,
      widget.color,
      (v) => ColorTween(begin: v as Color),
    ) as ColorTween?;
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(170, 170),
      painter: _RingPainter(
        progress: _progress?.evaluate(animation) ?? widget.progress,
        color: _color?.evaluate(animation) ?? widget.color,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;
  static const double strokeWidth = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth / 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      // Commence à midi (−π/2) et dessine dans le sens horaire.
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

// ─── Tam-tam mascot (bounce + slight rotation) ───────────────────────────────

class _TamTamMascot extends StatefulWidget {
  const _TamTamMascot();

  @override
  State<_TamTamMascot> createState() => _TamTamMascotState();
}

class _TamTamMascotState extends State<_TamTamMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _bounce;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    // 108 BPM → 556 ms. On fait un demi-cycle par beat (bounce aller-retour).
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _kLobbyBeatMs.round()),
    )..repeat(reverse: true);

    _bounce = Tween<double>(begin: 0, end: -10).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );

    // Rotation 5° gauche/droite synchronisée avec le bounce.
    _rotation = Tween<double>(begin: -0.087, end: 0.087).animate(
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
        return Transform.translate(
          offset: Offset(0, _bounce.value),
          child: Transform.rotate(
            angle: _rotation.value,
            child: child,
          ),
        );
      },
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: AppColors.bois.withValues(alpha: 0.35),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.orSoleil.withValues(alpha: 0.85),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.orSoleil.withValues(alpha: 0.25),
              blurRadius: 16,
              spreadRadius: 4,
            ),
          ],
        ),
        child: const Center(
          // Emoji tam-tam. Fallback : icône music_note si le rendu l'écrase.
          child: Text(
            '\u{1F941}', // drum 🥁
            style: TextStyle(fontSize: 42),
          ),
        ),
      ),
    );
  }
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
                color: AppColors.ivoire.withValues(alpha: 0.7),
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
    super.key,
  });

  final AnimationController slideCtrl;
  final bool isRematch;

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
              'PERSONNE DISPONIBLE',
              style: AppTypography.bebas(size: 22, color: AppColors.orSoleil),
            ),
          ),
          const SizedBox(height: 8),
          FadeTransition(
            opacity: slideCtrl,
            child: Text(
              isRematch
                  ? "Ton adversaire n'est plus en ligne.\nRetente ta chance !"
                  : 'Personne dans ton altitude pour le moment.\nReviens dans quelques instants !',
              textAlign: TextAlign.center,
              style: AppTypography.crimson(
                size: 14,
                color: AppColors.ivoire.withValues(alpha: 0.8),
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
                  style: AppTypography.bebas(size: 18, color: AppColors.orSoleil),
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
        child: Opacity(
          opacity: animation.value,
          child: child,
        ),
      ),
      child: child,
    );
  }
}
