import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/tournament_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/tournament.dart';
import 'package:defi_kilimandjaro/presentation/tournament/widgets/tournament_countdown.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran de découverte des tournois : liste des tournois programmés et en cours,
/// avec compte à rebours et nombre de participants. Plusieurs tournois peuvent
/// coexister.
class TournamentListView extends ConsumerWidget {
  const TournamentListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(openTournamentsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        // Retour toujours disponible : la pile peut avoir été remplacée
        // (retour depuis l'écran résultats via `go`) → fallback vers le hub.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.hub),
        ),
        title: Text('tournament.title'.tr(), style: AppTypography.headingLg),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Text(
            'error.load_failed'.tr(),
            style: AppTypography.crimson(color: AppColors.texteSecondaire),
          ),
        ),
        data: (tournaments) {
          if (tournaments.isEmpty) {
            return _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: tournaments.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) => _TournamentCard(tournament: tournaments[i]),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_outlined,
                size: 56, color: AppColors.texteSecondaire),
            const SizedBox(height: AppSpacing.md),
            Text(
              'tournament.empty'.tr(),
              textAlign: TextAlign.center,
              style: AppTypography.crimson(
                size: 15,
                color: AppColors.texteSecondaire,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TournamentCard extends StatelessWidget {
  const _TournamentCard({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isLive = tournament.isLive;

    return Material(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        onTap: () =>
            context.push(AppRoutes.tournamentDetailPath(tournament.id)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tournament.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.headingMd,
                    ),
                  ),
                  _StatusChip(status: tournament.status),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(Icons.group,
                      size: 16, color: AppColors.texteSecondaire),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'tournament.participants'
                        .tr(args: ['${tournament.participantCount}']),
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.texteSecondaire),
                  ),
                  const Spacer(),
                  if (tournament.isFinished) ...[
                    const Icon(Icons.leaderboard_outlined,
                        size: 16, color: AppColors.texteSecondaire),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'tournament.view_results'.tr(),
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.texteSecondaire),
                    ),
                  ] else ...[
                    Icon(
                      isLive ? Icons.timer_outlined : Icons.schedule,
                      size: 16,
                      color: isLive ? AppColors.kola : AppColors.orSoleil,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      isLive
                          ? '${'tournament.ends_in'.tr()} '
                          : '${'tournament.starts_in'.tr()} ',
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.texteSecondaire),
                    ),
                    TournamentCountdown(
                      target: isLive ? tournament.endAt : tournament.startAt,
                      color: isLive ? AppColors.kola : AppColors.orSoleil,
                      style: AppTypography.bebas(),
                    ),
                  ],
                ],
              ),
              if (now.isAfter(tournament.startAt) && tournament.isScheduled) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'tournament.starting_soon'.tr(),
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.texteSecondaire),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TournamentStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      TournamentStatus.live => ('tournament.status_live'.tr(), AppColors.kola),
      TournamentStatus.scheduled => (
          'tournament.status_scheduled'.tr(),
          AppColors.orSoleil,
        ),
      TournamentStatus.finished => (
          'tournament.status_finished'.tr(),
          AppColors.texteSecondaire,
        ),
      TournamentStatus.cancelled => (
          'tournament.status_cancelled'.tr(),
          AppColors.texteSecondaire,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: color),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.bebas(size: 12, color: color),
      ),
    );
  }
}
