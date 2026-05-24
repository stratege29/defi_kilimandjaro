import 'dart:async';

import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/domain/entities/player_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          // Fond dégradé savane sombre.
          const _SavannahBackground(),

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

class _SavannahBackground extends StatelessWidget {
  const _SavannahBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.boisFonce,
            AppColors.vertForet,
            Colors.black,
          ],
          stops: [0, 0.45, 1],
        ),
      ),
    );
  }
}

class _PlayerPortrait extends ConsumerWidget {
  const _PlayerPortrait({
    required this.label,
    required this.uid,
    required this.roundsWon,
    required this.alignment,
  });

  /// Label fallback affiché si le profil n'est pas (encore) disponible.
  final String label;

  /// UID du joueur à observer.
  final String uid;
  final int roundsWon;
  final Alignment alignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Observe le profil live : displayName + ELO.
    final profileAsync = uid.isEmpty
        ? const AsyncValue<PlayerProfile?>.data(null)
        : ref.watch(playerProfileProvider(uid));

    final profile = profileAsync.value;
    final displayName = (profile?.displayName != null &&
            profile!.displayName!.trim().isNotEmpty)
        ? profile.displayName!.trim()
        : label;
    final elo = profile?.elo;

    // Initiale calculée à partir du displayName si dispo, sinon UID.
    final initialsSource = (profile?.displayName != null &&
            profile!.displayName!.trim().isNotEmpty)
        ? profile.displayName!.trim()
        : (uid.isNotEmpty ? uid : '?');
    final initials = initialsSource.substring(0, 1).toUpperCase();

    return Semantics(
      label: '$displayName, $roundsWon manche(s) gagnée(s)',
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar circulaire avec initiales.
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceContainer,
                  border: Border.all(
                    color: AppColors.orJour,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.orJour.withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: AppTypography.displaySm,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                displayName,
                style: AppTypography.headingMd,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (elo != null) ...[
                const SizedBox(height: 4),
                _EloChip(elo: elo),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Petite pastille altitude (ELO en mètres). Style cohérent avec
/// l'AltitudeChip du lobby et du profil.
class _EloChip extends StatelessWidget {
  const _EloChip({required this.elo});
  final int elo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.orJour.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.orJour.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        '$elo m',
        style: AppTypography.bebas(size: 12, color: AppColors.orJour),
      ),
    );
  }
}

class _VsBadge extends StatelessWidget {
  const _VsBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'VS',
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.orJour,
          boxShadow: [
            BoxShadow(
              color: AppColors.orJour.withValues(alpha: 0.7),
              blurRadius: 24,
              spreadRadius: 6,
            ),
          ],
        ),
        child: Center(
          child: Text(
            'VS',
            style: AppTypography.bebas(
              size: 24,
              color: AppColors.vertForet,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
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
