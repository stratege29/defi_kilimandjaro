import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_history_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/matchmaking_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/presence_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_history_entry.dart';
import 'package:defi_kilimandjaro/presentation/duel/lobby_view.dart';
import 'package:defi_kilimandjaro/presentation/hub/widgets/bottom_nav_bar.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_chip.dart';
import 'package:defi_kilimandjaro/presentation/widgets/mountain_hero_image.dart';
import 'package:defi_kilimandjaro/presentation/widgets/section_label.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';

// ---------------------------------------------------------------------------
// Data model for a pending incoming challenge
// ---------------------------------------------------------------------------

/// Pending challenge surfaced from `pending_challenges/{uid}` RTDB node.
class _PendingChallenge {
  const _PendingChallenge({
    required this.matchId,
    required this.fromName,
  });

  final String matchId;
  final String fromName;
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

/// Stream of the current player's pending incoming challenge (if any).
///
/// Listens to `pending_challenges/{uid}` in Realtime DB — the same node that
/// `IncomingChallengeListener` uses for the global dialog.  On the Hub screen
/// we surface a compact inline banner instead of the modal, giving the player
/// an additional entry point without duplicating the global listener logic.
///
/// Emits `null` when there is no pending challenge or the user is not signed in.
final _pendingChallengeProvider = StreamProvider<_PendingChallenge?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);

  return FirebaseDatabase.instance
      .ref('pending_challenges/$uid')
      .onValue
      .map((event) {
    final value = event.snapshot.value;
    if (value is! Map) return null;
    final data = Map<String, dynamic>.from(value);
    final matchId = data['matchId'] as String?;
    if (matchId == null) return null;
    return _PendingChallenge(
      matchId: matchId,
      fromName: (data['fromName'] as String?) ?? 'Un grimpeur',
    );
  });
});

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

/// Hub Défi — Phase 5b "Vert Nuit" redesign.
///
/// Layout (top → bottom):
///   1. Header : titre "Défi" + chip altitude/ELO (Hero animé).
///   2. Hero card EN LIGNE · CLASSÉ (fond montagne, ELO + rang, CTA or).
///   3. Invite banner Kola si challenge entrant.
///   4. Deux action cards côte à côte : Défier un ami / Scanner.
///   5. Section "Derniers duels" (empty state — TODO histoire).
///   6. Bottom nav, onglet Défi actif.
///
/// Data wiring:
///   - ELO / profil : [playerProfileStreamProvider] (Firestore).
///   - Présence "N en ligne" : NON disponible côté client — omise.
///     // TODO(presence): exposer un compteur RTDB `/lobby/stats/online` depuis
///     // la Cloud Function requestMatch et lire ici en StreamProvider.
///   - Historique duels : NON persisté côté client — empty state affiché.
///     // TODO(history): persister les N derniers résultats dans
///     // Firestore `profiles/{uid}/duel_history` depuis la CF endMatch et
///     // exposer via un StreamProvider ici.
///   - Challenge entrant : `_pendingChallengeProvider` (même noeud RTDB que
///     `IncomingChallengeListener`).
class DuelHubView extends ConsumerWidget {
  const DuelHubView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const _DuelHubHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.lg,
                ),
                children: const [
                  _OnlineHeroCard(),
                  AppSpacing.gapSm,
                  _InviteBanner(),
                  AppSpacing.gapSm,
                  _ActionCardsRow(),
                  SizedBox(height: AppSpacing.md),
                  _RecentDuelsSection(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: NavTab.defi,
        onTabSelected: (t) {
          switch (t) {
            case NavTab.accueil:
              context.go(AppRoutes.home);
            case NavTab.defi:
              break;
            case NavTab.sommets:
              context.go(AppRoutes.mountains);
            case NavTab.profil:
              context.go(AppRoutes.profile);
          }
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _DuelHubHeader extends ConsumerWidget {
  const _DuelHubHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(playerProfileStreamProvider);
    final elo = profileAsync.value?.elo ?? 1000;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.hairline),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Défi',
            style: AppTypography.headingXl,
          ),
          const Spacer(),
          // Hero animé partagé avec LobbyView et ProfileView.
          Hero(
            tag: kAltitudeHeroTag,
            child: _AltitudeChip(elo: elo),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.terrain_rounded,
            size: 14,
            color: AppColors.cielHauteur,
          ),
          AppSpacing.hGapXs,
          Text(
            '$elo m',
            style: AppTypography.labelSm.copyWith(
              color: AppColors.cielHauteur,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero EN LIGNE · CLASSÉ card
// ---------------------------------------------------------------------------

class _OnlineHeroCard extends ConsumerWidget {
  const _OnlineHeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(playerProfileStreamProvider);
    final profile = profileAsync.value;
    final elo = profile?.elo ?? 1000;
    final totalDuels = profile?.totalDuels ?? 0;

    final onlineAsync = ref.watch(onlinePlayersCountProvider);
    final onlineCount = onlineAsync.value ?? 0;

    // Rang approximatif basé sur l'ELO local (pas de classement global ici).
    // TODO(ranking): lire le rang depuis le leaderboard Firestore.
    final rankLabel = totalDuels == 0 ? 'Novice' : 'Classé';

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl - 2),
        border: Border.all(color: AppColors.hairline),
        // Dégradé ciel nocturne → vert nuit (dérivé des tokens, pas de hex).
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(AppColors.info, AppColors.surface, 0.42)!,
            AppColors.surfaceVariant,
            AppColors.surface,
          ],
          stops: const [0, 0.72, 1],
        ),
      ),
      child: Stack(
        children: [
          // Montagne en fond à faible opacité.
          const Positioned.fill(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: RepaintBoundary(
                child: MountainHeroImage(
                  mountainId: 'tz_kilimanjaro',
                  height: 120,
                  fit: BoxFit.cover,
                  alignment: Alignment.bottomCenter,
                  opacity: 0.18,
                  fallback: SizedBox.shrink(),
                ),
              ),
            ),
          ),
          // Contenu.
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label "EN LIGNE · CLASSÉ" with optional online count chip
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'EN LIGNE · CLASSÉ',
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.orJour,
                        letterSpacing: 1.4,
                        fontSize: 11,
                      ),
                    ),
                    // Show online count chip if available and > 0
                    if (onlineAsync.hasValue && onlineCount > 0)
                      AppChip(
                        label: '$onlineCount grimpeur${onlineCount != 1 ? 's' : ''}',
                        tone: AppChipTone.success,
                      ),
                  ],
                ),
                AppSpacing.gapSm,
                // Altitude ELO + rang.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$elo',
                      style: AppTypography.displaySm.copyWith(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    AppSpacing.hGapXs,
                    Text(
                      'm · $rankLabel',
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.texteSecondaire,
                      ),
                    ),
                  ],
                ),
                AppSpacing.gapSm,
                // CTA gold principal.
                AppButton(
                  label: 'TROUVER UN ADVERSAIRE',
                  onPressed: () => context.push(AppRoutes.duelLobby),
                  fullWidth: true,
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
// Invite banner — challenge entrant
// ---------------------------------------------------------------------------

class _InviteBanner extends ConsumerWidget {
  const _InviteBanner();

  static final Logger _log = Logger();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengeAsync = ref.watch(_pendingChallengeProvider);
    final challenge = challengeAsync.value;

    // Si pas de challenge, on n'affiche rien (SizedBox.shrink()).
    if (challenge == null) return const SizedBox.shrink();

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 3,
          vertical: AppSpacing.sm + 3,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: AppColors.kola.withValues(alpha: 0.5),
          ),
          gradient: LinearGradient(
            colors: [
              AppColors.kola.withValues(alpha: 0.18),
              AppColors.surface,
            ],
          ),
        ),
        child: Row(
          children: [
            // Avatar initiale de l'adversaire.
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.35),
                  colors: [
                    Color.lerp(
                      AppColors.cielHauteur,
                      AppColors.textePrimaire,
                      0.3,
                    )!,
                    Color.lerp(
                      AppColors.cielHauteur,
                      AppColors.surface,
                      0.5,
                    )!,
                  ],
                ),
                border: Border.all(color: AppColors.cielHauteur, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                challenge.fromName.isNotEmpty
                    ? challenge.fromName[0].toUpperCase()
                    : '?',
                style: AppTypography.headingMd.copyWith(
                  color: AppColors.surface,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            AppSpacing.hGapSm,
            // Texte.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${challenge.fromName} te défie',
                    style: AppTypography.headingSm.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'Duel amical',
                    style: AppTypography.labelXs.copyWith(
                      color: AppColors.texteTertiaire,
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.hGapSm,
            // Bouton ACCEPTER.
            AppButton(
              label: 'ACCEPTER',
              onPressed: () => _onAccept(context, ref, challenge),
              variant: AppButtonVariant.kola,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onAccept(
    BuildContext context,
    WidgetRef ref,
    _PendingChallenge challenge,
  ) async {
    try {
      final matchmakingRepo = ref.read(matchmakingRepositoryProvider);
      final duelRepo = ref.read(duelRepositoryProvider);

      await matchmakingRepo.respondToChallenge(
        matchId: challenge.matchId,
        accept: true,
      );
      final session = await duelRepo.joinOpen(challenge.matchId);

      if (!context.mounted) return;
      context.go(AppRoutes.duelPlay, extra: session);
    } on Exception catch (e) {
      _log.e('[DuelHub] Accept challenge failed', error: e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de rejoindre : $e',
            style: AppTypography.bodyMd,
          ),
          backgroundColor: AppColors.errorSoft,
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Action cards row — Défier un ami / Scanner
// ---------------------------------------------------------------------------

class _ActionCardsRow extends StatelessWidget {
  const _ActionCardsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            icon: Icons.grid_view_rounded,
            title: 'Défier un ami',
            subtitle: 'Génère un QR',
            onTap: () => context.push(AppRoutes.duelCreate),
          ),
        ),
        AppSpacing.hGapSm,
        Expanded(
          child: _ActionCard(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Scanner',
            subtitle: 'Rejoindre via QR',
            onTap: () => context.push(AppRoutes.duelScan),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg - 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg - 2),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg - 2),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.orJour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.sm + 2),
                ),
                child: Icon(icon, size: 18, color: AppColors.orJour),
              ),
              AppSpacing.gapSm,
              Text(
                title,
                style: AppTypography.headingSm.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              AppSpacing.gapXs,
              Text(
                subtitle,
                style: AppTypography.labelXs.copyWith(
                  color: AppColors.texteTertiaire,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Derniers duels section
// ---------------------------------------------------------------------------

/// Section historique des derniers duels.
///
/// Wired to `recentDuelsProvider` (Firestore subcollection
/// `profiles/{uid}/duel_history`, written by Cloud Function `endMatch`).
/// Shows last 5 duels with result badge, opponent name, and ELO delta.
/// Displays honest empty state for new players.
class _RecentDuelsSection extends ConsumerWidget {
  const _RecentDuelsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duelsAsync = ref.watch(recentDuelsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Derniers duels'),
        AppSpacing.gapSm,
        duelsAsync.when(
          loading: () => Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.hairline),
            ),
            child: const SizedBox(
              height: 60,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
          error: (err, st) => Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.lg,
              horizontal: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 28,
                  color: AppColors.texteDisabled,
                ),
                AppSpacing.gapSm,
                Text(
                  'Erreur de chargement',
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.texteSecondaire,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          data: (duels) {
            if (duels.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.lg,
                  horizontal: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.show_chart_rounded,
                      size: 28,
                      color: AppColors.texteDisabled,
                    ),
                    AppSpacing.gapSm,
                    Text(
                      'Aucun duel récent',
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.texteSecondaire,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    AppSpacing.gapXs,
                    Text(
                      'Lance ton premier défi pour voir tes résultats ici.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.texteTertiaire,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                for (final duel in duels) ...[
                  _DuelHistoryRow(duel: duel),
                  if (duel != duels.last) AppSpacing.gapXs,
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Single duel history row widget.
class _DuelHistoryRow extends StatelessWidget {
  const _DuelHistoryRow({required this.duel});

  final DuelHistoryEntry duel;

  @override
  Widget build(BuildContext context) {
    final resultColor = duel.didWin ? AppColors.successSoft : AppColors.errorSoft;
    final deltaColor = duel.eloDelta >= 0 ? AppColors.success : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          // Result badge (V/D)
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: resultColor,
              borderRadius: BorderRadius.circular(AppSpacing.sm),
            ),
            alignment: Alignment.center,
            child: Text(
              duel.resultBadge,
              style: AppTypography.headingSm.copyWith(
                color: duel.didWin ? AppColors.success : AppColors.error,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          AppSpacing.hGapSm,
          // Opponent name + timestamp
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  duel.displayOpponentName,
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (duel.finishedAt != null)
                  Text(
                    _formatDuelTime(duel.finishedAt!),
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.texteTertiaire,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          AppSpacing.hGapSm,
          // ELO delta
          Text(
            duel.eloDeltaLabel,
            style: AppTypography.labelSm.copyWith(
              color: deltaColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Format time since duel for display (e.g., "Il y a 2 heures").
  static String _formatDuelTime(DateTime finishedAt) {
    final now = DateTime.now();
    final diff = now.difference(finishedAt);

    if (diff.inMinutes < 1) return "À l'instant";
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    if (diff.inDays < 30) return 'Il y a ${diff.inDays ~/ 7} sem';
    return 'Il y a ${diff.inDays ~/ 30} mois';
  }
}
