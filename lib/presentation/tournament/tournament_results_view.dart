import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart'
    show firebaseAuthProvider;
import 'package:defi_kilimandjaro/data/repositories/tournament_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/tournament.dart';
import 'package:defi_kilimandjaro/domain/entities/tournament_participant.dart';
import 'package:defi_kilimandjaro/presentation/tournament/widgets/standings_list.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran de résultats d'un tournoi : classement final figé, rang du joueur et
/// récompenses gagnées (cauris + badge). Tant que le tournoi n'est pas finalisé,
/// affiche le classement live avec un bandeau « en cours ».
class TournamentResultsView extends ConsumerWidget {
  const TournamentResultsView({required this.tournamentId, super.key});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tid = tournamentId;
    final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final tournament = ref.watch(tournamentProvider(tid)).value;
    final standings = ref.watch(tournamentStandingsProvider(tid)).value ?? [];
    final myParticipant = uid == null
        ? null
        : ref.watch(_resultParticipantProvider((tid: tid, uid: uid))).value;

    final isFinished = tournament?.isFinished ?? false;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('tournament.results_title'.tr(),
            style: AppTypography.headingMd),
      ),
      body: Column(
        children: [
          if (tournament != null)
            _ResultHeader(
              tournament: tournament,
              participant: myParticipant,
              isFinished: isFinished,
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: StandingsList(
                participants: standings,
                highlightUid: uid,
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: AppButton(
                label: 'tournament.back_to_list'.tr(),
                fullWidth: true,
                onPressed: () => context.go(AppRoutes.tournaments),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({
    required this.tournament,
    required this.participant,
    required this.isFinished,
  });

  final Tournament tournament;
  final TournamentParticipant? participant;
  final bool isFinished;

  @override
  Widget build(BuildContext context) {
    final rank = participant?.rank;
    final reward = participant?.rewardCauris ?? 0;
    final badge = participant?.rewardBadge;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: AppColors.surfaceVariant,
      child: Column(
        children: [
          Text(tournament.name, style: AppTypography.headingMd),
          const SizedBox(height: AppSpacing.sm),
          if (!isFinished)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.kola.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Text(
                'tournament.status_live'.tr(),
                style: AppTypography.bebas(size: 13, color: AppColors.kola),
              ),
            )
          else ...[
            const Icon(Icons.emoji_events,
                size: 40, color: AppColors.orSoleil),
            const SizedBox(height: AppSpacing.sm),
            Text(
              rank != null
                  ? 'tournament.final_rank'.tr(args: ['$rank'])
                  : 'tournament.final_rank_unranked'.tr(),
              style: AppTypography.displaySm,
            ),
            if (reward > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'tournament.reward_earned'.tr(args: ['$reward']),
                style: AppTypography.bebas(size: 18, color: AppColors.orSoleil),
              ),
            ],
            if (badge != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'tournament.badge_earned'.tr(),
                style:
                    AppTypography.crimson(size: 14, color: AppColors.vertClair),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Provider local : fiche du participant courant pour l'écran résultats.
final _resultParticipantProvider = StreamProvider.family<
    TournamentParticipant?, ({String tid, String uid})>((ref, key) {
  return ref
      .watch(tournamentRepositoryProvider)
      .watchMyParticipant(key.tid, key.uid);
});
