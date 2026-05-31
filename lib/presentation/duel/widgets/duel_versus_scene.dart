import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/avatars/avatar_catalog.dart';
import 'package:defi_kilimandjaro/domain/entities/player_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Briques visuelles partagées de l'écran VERSUS (maquette `duelstart`),
/// réutilisées par `DuelIntroOverlay` (slam animé) et `DuelCountdownOverlay`
/// (même décor + décompte « Le duel commence dans N »).
///
/// Garder ces pièces dans un seul fichier évite que les deux superpositions
/// divergent : le décompte doit être la continuité exacte de l'intro.

// ---------------------------------------------------------------------------
// Géométrie diagonale (façon jeu de combat) — fractions de la hauteur écran.
// ---------------------------------------------------------------------------

/// Marge horizontale des combattants depuis le bord (cf. maquette `left/right:22`).
const double kDuelFighterInset = 18;

/// Position verticale du combattant local (haut-gauche).
const double kDuelLeftFighterTopFraction = 0.10;

/// Position verticale de l'adversaire (bas-droite) — diagonale du VS.
const double kDuelRightFighterTopFraction = 0.42;

/// Centre vertical du badge VS.
const double kDuelVsCenterFraction = 0.42;

/// Convertit le code difficulté serveur en libellé français.
String duelDifficultyLabel(String difficulty) => switch (difficulty) {
      'easy' => 'Facile',
      'medium' => 'Moyen',
      'hard' => 'Difficile',
      _ => difficulty,
    };

// ---------------------------------------------------------------------------
// Fond VERSUS — split diagonal (or vs indigo) + montagne + vignette + lame.
// ---------------------------------------------------------------------------

/// Fond « écran VERSUS » : split diagonal teinté (or côté joueur, indigo côté
/// adversaire), lame dorée centrale, montagne silhouettée et vignette.
/// Aucun `MaskFilter.blur` (perf iOS 26).
class DuelVersusBackdrop extends StatelessWidget {
  const DuelVersusBackdrop({super.key});

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

// ---------------------------------------------------------------------------
// Pastille de manche — « MANCHE 1 / 3 · FACILE » (maquette `.ds-round`).
// ---------------------------------------------------------------------------

class DuelRoundPill extends StatelessWidget {
  const DuelRoundPill({
    required this.currentRound,
    required this.totalRounds,
    required this.difficulty,
    super.key,
  });

  final int currentRound;
  final int totalRounds;
  final String difficulty;

  @override
  Widget build(BuildContext context) {
    final label = 'MANCHE ${currentRound + 1} / $totalRounds · '
        '${duelDifficultyLabel(difficulty).toUpperCase()}';
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.orJour.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: AppTypography.labelSm.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Portrait combattant — avatar + plaque inclinée (maquette `.ds-fighter`).
// ---------------------------------------------------------------------------

/// Portrait d'un joueur (avatar SVG/initiale + plaque de nom inclinée).
/// Le positionnement (gauche-haut / droite-bas) est laissé à l'appelant.
class DuelFighterPortrait extends ConsumerWidget {
  const DuelFighterPortrait({
    required this.label,
    required this.uid,
    required this.roundsWon,
    required this.showElo,
    required this.accent,
    super.key,
  });

  final String label;
  final String uid;
  final int roundsWon;
  final bool showElo;

  /// Couleur de camp (or côté joueur, indigo côté adversaire).
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
    final asyncProfile = uid.isEmpty
        ? const AsyncValue<PlayerProfile?>.data(null)
        : ref.watch(playerProfileProvider(uid));

    final profile = asyncProfile.asData?.value;
    final hasDisplayName = profile?.displayName?.isNotEmpty ?? false;
    final pseudo = hasDisplayName ? profile!.displayName! : _fallbackPseudo;
    final initial = hasDisplayName
        ? _initialOf(profile!.displayName!)
        : _fallbackInitial(uid);
    final avatar = AvatarCatalog.byId(profile?.avatarId);
    final eloLabel = (showElo && profile != null) ? '${profile.elo} m' : null;

    return Semantics(
      label: '$label $pseudo, $roundsWon manche(s) gagnée(s)',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar circulaire (SVG ou initiale), anneau couleur de camp.
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceContainer,
              border: Border.all(color: accent, width: 3),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.5),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: avatar != null ? Clip.antiAlias : Clip.none,
            child: avatar != null
                ? SvgPicture.asset(
                    avatar.assetPath,
                    fit: BoxFit.cover,
                    placeholderBuilder: (_) => _InitialBadge(initial: initial),
                  )
                : _InitialBadge(initial: initial),
          ),
          const SizedBox(height: 10),
          // Plaque de nom inclinée façon HUD de combat.
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(-0.12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                        letterSpacing: 1.6,
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
    );
  }
}

class _InitialBadge extends StatelessWidget {
  const _InitialBadge({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(initial, style: AppTypography.displaySm),
    );
  }
}

// ---------------------------------------------------------------------------
// Badge VS — éclat de rayons + lettrage Fraunces en relief (maquette `.ds-vs2`).
// ---------------------------------------------------------------------------

class DuelVsBadge extends StatelessWidget {
  const DuelVsBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final vsStyle = AppTypography.playfair(
      size: 104,
      color: Color.lerp(AppColors.orJour, AppColors.textePrimaire, 0.30)!,
      weight: FontWeight.w900,
      style: FontStyle.italic,
    ).copyWith(
      shadows: [
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
        width: 210,
        height: 210,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(210, 210),
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
      final b1 = center +
          Offset(math.cos(a - half), math.sin(a - half)) * (outer * 0.22);
      final b2 = center +
          Offset(math.cos(a + half), math.sin(a + half)) * (outer * 0.22);
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
