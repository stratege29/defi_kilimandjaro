import 'dart:async';
import 'dart:math' as math;

import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/avatars/avatar_catalog.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/domain/entities/player_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Superposition animée affichée pendant la phase [DuelPhase.intro].
///
/// Deux portraits se rapprochent du centre depuis les bords de l'écran
/// (~1 s, [Curves.easeOutBack]), puis un flash blanc et le VS doré
/// apparaissent en [ScaleTransition].
///
/// Durée totale : ~2,5 s.
/// La transition vers [DuelPhase.countdown] est déclenchée côté serveur par
/// la Cloud Function `advanceRound` — ce widget n'a pas à la piloter.
class DuelIntroOverlay extends ConsumerStatefulWidget {
  const DuelIntroOverlay({required this.session, super.key});

  final DuelSession session;

  @override
  ConsumerState<DuelIntroOverlay> createState() => _DuelIntroOverlayState();
}

class _DuelIntroOverlayState extends ConsumerState<DuelIntroOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final AnimationController _vsCtrl;
  late final AnimationController _flashCtrl;

  late final Animation<double> _selfSlide;
  late final Animation<double> _opponentSlide;
  late final Animation<double> _vsScale;
  late final Animation<double> _vsOpacity;
  late final Animation<double> _flashOpacity;

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _vsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    // Portraits glissent de ±1 (hors écran) vers 0 (centre de leur côté).
    _selfSlide = Tween<double>(begin: -1, end: 0).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutBack),
    );
    _opponentSlide = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutBack),
    );

    _vsScale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _vsCtrl, curve: Curves.easeOutBack),
    );
    _vsOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _vsCtrl,
        curve: const Interval(0, 0.5, curve: Curves.easeIn),
      ),
    );

    _flashOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 0.85),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.85, end: 0),
        weight: 60,
      ),
    ]).animate(_flashCtrl);

    _playSequence();
  }

  Future<void> _playSequence() async {
    // 1. Slides portraits.
    await _slideCtrl.forward();

    // 2. Flash + VS simultanément.
    unawaited(_flashCtrl.forward());
    unawaited(_vsCtrl.forward());

    // 3. Son duel start.
    unawaited(
      ref.read(audioControllerProvider.notifier).playDuelStart(),
    );
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _vsCtrl.dispose();
    _flashCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selfUid =
        ref.watch(firebaseAuthProvider).currentUser?.uid ?? '';
    final self = widget.session.players[selfUid];
    final opponent = widget.session.opponentOf(selfUid);

    final screenWidth = MediaQuery.sizeOf(context).width;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Fond VERSUS — split diagonal (or vs indigo) + seam + vignette.
          const Positioned.fill(child: _VersusBackdrop()),

          // Flash blanc au croisement des portraits.
          AnimatedBuilder(
            animation: _flashOpacity,
            builder: (_, __) => Opacity(
              opacity: _flashOpacity.value,
              child: const ColoredBox(color: Colors.white),
            ),
          ),

          // Portraits + noms.
          SafeArea(
            child: AnimatedBuilder(
              animation: _slideCtrl,
              builder: (_, __) => Row(
                children: [
                  // Joueur local — glisse depuis la gauche.
                  Expanded(
                    child: Transform.translate(
                      offset: Offset(_selfSlide.value * screenWidth / 2, 0),
                      child: _PlayerPortrait(
                        label: 'Moi',
                        uid: selfUid,
                        roundsWon: self?.roundsWon ?? 0,
                        alignment: Alignment.centerRight,
                        showElo: widget.session.isRanked,
                        accent: AppColors.orJour,
                      ),
                    ),
                  ),

                  // Espace central pour le VS.
                  const SizedBox(width: 72),

                  // Adversaire — glisse depuis la droite.
                  Expanded(
                    child: Transform.translate(
                      offset:
                          Offset(_opponentSlide.value * screenWidth / 2, 0),
                      child: _PlayerPortrait(
                        label: 'Adversaire',
                        uid: opponent?.uid ?? '',
                        roundsWon: opponent?.roundsWon ?? 0,
                        alignment: Alignment.centerLeft,
                        showElo: widget.session.isRanked,
                        accent: AppColors.cielHauteur,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // VS doré centré.
          Center(
            child: AnimatedBuilder(
              animation: _vsCtrl,
              builder: (_, __) => FadeTransition(
                opacity: _vsOpacity,
                child: ScaleTransition(
                  scale: _vsScale,
                  child: const _VsBadge(),
                ),
              ),
            ),
          ),

          // Indicateur de manche en haut.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _RoundLabel(
                currentRound: widget.session.currentRound,
                totalRounds: widget.session.totalRounds,
                difficulty:
                    widget.session.currentRoundData?.difficulty ?? 'easy',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sous-widgets privés
// ---------------------------------------------------------------------------

/// Fond « écran VERSUS » façon jeu de combat : split diagonal teinté
/// (or côté joueur, indigo côté adversaire), lame dorée au centre, montagne
/// silhouettée en bas et vignette. Aucun `MaskFilter.blur` (perf iOS 26).
class _VersusBackdrop extends StatelessWidget {
  const _VersusBackdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _VersusBackdropPainter(),
      size: Size.infinite,
    );
  }
}

class _VersusBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    // Base sombre.
    canvas.drawRect(rect, Paint()..color = AppColors.surface);

    // Diagonale : 60 % en haut → 40 % en bas.
    final topX = w * 0.60;
    final botX = w * 0.40;

    // Camp joueur (gauche, or/kola).
    final leftPath = Path()
      ..moveTo(0, 0)
      ..lineTo(topX, 0)
      ..lineTo(botX, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      leftPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.kola.withValues(alpha: 0.26),
            AppColors.orJour.withValues(alpha: 0.12),
            AppColors.surface.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // Camp adversaire (droite, indigo).
    final rightPath = Path()
      ..moveTo(topX, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(botX, h)
      ..close();
    canvas.drawPath(
      rightPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            AppColors.info.withValues(alpha: 0.30),
            AppColors.cielHauteur.withValues(alpha: 0.12),
            AppColors.surface.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // Montagne silhouettée (on s'affronte pour le sommet).
    final mtn = Path()
      ..moveTo(0, h)
      ..lineTo(w * 0.14, h * 0.74)
      ..lineTo(w * 0.30, h * 0.82)
      ..lineTo(w * 0.50, h * 0.62)
      ..lineTo(w * 0.72, h * 0.80)
      ..lineTo(w * 0.88, h * 0.70)
      ..lineTo(w, h * 0.80)
      ..lineTo(w, h)
      ..close();
    canvas
      ..drawPath(
        mtn,
        Paint()..color = Colors.black.withValues(alpha: 0.45),
      )
      // Vignette.
      ..drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, -0.1),
            radius: 1,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.6),
            ],
            stops: const [0.42, 1],
          ).createShader(rect),
      )
      // Lame dorée centrale.
      ..drawLine(
        Offset(topX, -h * 0.05),
        Offset(botX, h * 1.05),
        Paint()
          ..color = AppColors.orJour
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
  }

  @override
  bool shouldRepaint(_VersusBackdropPainter oldDelegate) => false;
}

/// Portrait d'un joueur — branché sur [playerProfileProvider] pour afficher :
/// - Pseudo réel (fallback "Joueur" si profil null / displayName vide)
/// - Avatar SVG si [PlayerProfile.avatarId] défini (fallback initiale du
///   pseudo, sinon initiale UID)
/// - Score ELO en mètres si [showElo] (i.e. duel ranked)
///
/// [label] reste affiché en petite étiquette ("Moi" / "Adversaire") au-dessus
/// du pseudo pour identifier rapidement chaque côté.
class _PlayerPortrait extends ConsumerWidget {
  const _PlayerPortrait({
    required this.label,
    required this.uid,
    required this.roundsWon,
    required this.alignment,
    required this.showElo,
    required this.accent,
  });

  final String label;
  final String uid;
  final int roundsWon;
  final Alignment alignment;
  final bool showElo;

  /// Couleur de camp (or côté joueur, indigo côté adversaire) — anneau
  /// d'avatar, halo et plaque de nom.
  final Color accent;

  static const String _fallbackPseudo = 'Joueur';

  static String _fallbackInitial(String uid) =>
      uid.isEmpty ? '?' : uid.substring(0, 1).toUpperCase();

  static String _initialOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Si pas d'uid (adversaire pas encore connecté), rendu placeholder.
    final asyncProfile = uid.isEmpty
        ? const AsyncValue<PlayerProfile?>.data(null)
        : ref.watch(playerProfileProvider(uid));

    final profile = asyncProfile.asData?.value;
    final hasDisplayName = profile?.displayName?.isNotEmpty ?? false;
    final pseudo = hasDisplayName ? profile!.displayName! : _fallbackPseudo;
    final initial =
        hasDisplayName ? _initialOf(profile!.displayName!) : _fallbackInitial(uid);
    final avatar = AvatarCatalog.byId(profile?.avatarId);
    final eloLabel = (showElo && profile != null) ? '${profile.elo} m' : null;

    return Semantics(
      label: '$label $pseudo, $roundsWon manche(s) gagnée(s)',
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar circulaire (SVG ou initiale), anneau couleur de camp.
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceContainer,
                  border: Border.all(color: accent, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.5),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                clipBehavior: avatar != null ? Clip.antiAlias : Clip.none,
                child: avatar != null
                    ? SvgPicture.asset(
                        avatar.assetPath,
                        fit: BoxFit.cover,
                        placeholderBuilder: (_) =>
                            _InitialBadge(initial: initial),
                      )
                    : _InitialBadge(initial: initial),
              ),
              const SizedBox(height: 12),
              // Plaque de nom inclinée façon HUD de combat.
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.skewX(-0.12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: accent.withValues(alpha: 0.6)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        accent.withValues(alpha: 0.20),
                        AppColors.surface.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.skewX(0.12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: AppTypography.labelXs.copyWith(
                            color: accent,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          pseudo,
                          style: AppTypography.headingMd.copyWith(
                            letterSpacing: 0.8,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        if (eloLabel != null)
                          Text(
                            eloLabel,
                            style: AppTypography.labelXs.copyWith(
                              color: AppColors.texteSecondaire,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InitialBadge extends StatelessWidget {
  const _InitialBadge({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: AppTypography.displaySm,
      ),
    );
  }
}

/// VS « métallique » façon jeu de combat : éclat de rayons doré + lettrage
/// Fraunces italique en relief (double ombre bronze + halo).
class _VsBadge extends StatelessWidget {
  const _VsBadge();

  @override
  Widget build(BuildContext context) {
    final vsStyle = AppTypography.playfair(
      size: 96,
      color: Color.lerp(AppColors.orJour, AppColors.textePrimaire, 0.30)!,
      weight: FontWeight.w900,
      style: FontStyle.italic,
    ).copyWith(
      shadows: [
        // Relief « métal gravé » à 3 couches (cf. maquette .ds-vs2) :
        // or profond → bronze sombre → profondeur noire, puis halo doré.
        const Shadow(color: AppColors.orChaud, offset: Offset(3, 4)),
        const Shadow(color: AppColors.orCrepuscule, offset: Offset(5, 7)),
        Shadow(
          color: Colors.black.withValues(alpha: 0.7),
          offset: const Offset(6, 9),
          blurRadius: 16,
        ),
        Shadow(
          color: AppColors.orJour.withValues(alpha: 0.7),
          blurRadius: 34,
        ),
      ],
    );

    return Semantics(
      label: 'VS',
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(200, 200),
              painter: _BurstPainter(),
            ),
            Transform.rotate(
              angle: -0.14,
              child: Text('VS', style: vsStyle),
            ),
          ],
        ),
      ),
    );
  }
}

/// Éclat de rayons dorés rayonnant du centre (énergie du choc).
class _BurstPainter extends CustomPainter {
  static const int _rays = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.width * 0.5;
    final paint = Paint()..color = AppColors.orJour.withValues(alpha: 0.16);
    for (var i = 0; i < _rays; i++) {
      final a = (i / _rays) * 2 * math.pi;
      const half = math.pi / _rays * 0.5;
      final tip = center + Offset(math.cos(a), math.sin(a)) * outer;
      final b1 = center + Offset(math.cos(a - half), math.sin(a - half)) * (outer * 0.22);
      final b2 = center + Offset(math.cos(a + half), math.sin(a + half)) * (outer * 0.22);
      canvas.drawPath(
        Path()
          ..moveTo(b1.dx, b1.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(b2.dx, b2.dy)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) => false;
}

class _RoundLabel extends StatelessWidget {
  const _RoundLabel({
    required this.currentRound,
    required this.totalRounds,
    required this.difficulty,
  });

  final int currentRound;
  final int totalRounds;
  final String difficulty;

  String get _difficultyLabel {
    return switch (difficulty) {
      'easy' => 'Facile',
      'medium' => 'Moyen',
      'hard' => 'Difficile',
      _ => difficulty,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Manche ${currentRound + 1} / $totalRounds — $_difficultyLabel',
            style: AppTypography.labelSm,
          ),
        ),
      ),
    );
  }
}
