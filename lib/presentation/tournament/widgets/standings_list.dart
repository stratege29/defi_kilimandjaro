import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/tournament_participant.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Liste de classement (live ou final) d'un tournoi. Met en évidence la ligne
/// du joueur courant [highlightUid]. L'ordre des [participants] suit le tri
/// fourni par le repository (points desc, victoires desc).
class StandingsList extends StatelessWidget {
  const StandingsList({
    required this.participants,
    this.highlightUid,
    this.shrinkWrap = false,
    this.physics,
    super.key,
  });

  final List<TournamentParticipant> participants;
  final String? highlightUid;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: Text(
            'tournament.standings_empty'.tr(),
            style: AppTypography.crimson(
              size: 14,
              color: AppColors.texteSecondaire,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: participants.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (_, i) => _StandingRow(
        rank: participants[i].rank ?? (i + 1),
        participant: participants[i],
        highlighted: participants[i].uid == highlightUid,
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.participant,
    required this.highlighted,
  });

  final int rank;
  final TournamentParticipant participant;
  final bool highlighted;

  Color get _rankColor {
    switch (rank) {
      case 1:
        return AppColors.orSoleil;
      case 2:
        return const Color(0xFFC0C7CE);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return AppColors.texteSecondaire;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.orSoleil.withValues(alpha: 0.12)
            : AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: highlighted
            ? Border.all(color: AppColors.orSoleil, width: 1.2)
            : Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: AppTypography.bebas(size: 18, color: _rankColor),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              participant.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.headingSm.copyWith(
                color: highlighted
                    ? AppColors.textePrimaire
                    : AppColors.textePrimaire,
              ),
            ),
          ),
          if (participant.onFire) ...[
            const Icon(Icons.local_fire_department,
                size: 16, color: AppColors.kola),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            'tournament.points_short'
                .tr(args: ['${participant.points}']),
            style: AppTypography.bebas(size: 18, color: AppColors.orSoleil),
          ),
        ],
      ),
    );
  }
}
