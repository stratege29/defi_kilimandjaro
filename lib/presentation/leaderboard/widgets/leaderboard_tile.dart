import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/leaderboard_entry.dart';
import 'package:defi_kilimandjaro/domain/entities/player_profile.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Tuile d'un joueur dans le classement.
///
/// Design :
/// - Rang doré pour top 3, ivoire sinon.
/// - Avatar : initiale du displayName dans un cercle bois.
/// - Altitude à droite en Bebas or.
/// - Badge MAÎTRE si ELO >= [PlayerProfile.eloMaster].
/// - Bordure dorée si c'est l'utilisateur courant.
/// - Long press + [onRemove] présent → menu "Retirer de la liste".
class LeaderboardTile extends StatelessWidget {
  const LeaderboardTile({
    required this.entry,
    required this.isMe,
    this.onRemove,
    super.key,
  });

  final LeaderboardEntry entry;
  final bool isMe;

  /// Si non null, affiche l'option "Retirer de la liste" au long press.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final isTop3 = entry.rank <= 3;
    final isMaster = entry.elo >= PlayerProfile.eloMaster;

    final borderColor =
        isMe ? AppColors.orSoleil : AppColors.orSoleil.withValues(alpha: 0.15);
    final borderWidth = isMe ? 1.5 : 1.0;

    return Semantics(
      label: '${entry.rank}. ${entry.displayName} — ${entry.altitudeLabel}',
      child: GestureDetector(
        onLongPress: onRemove != null ? () => _showRemoveMenu(context) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isMe
                ? AppColors.orSoleil.withValues(alpha: 0.08)
                : AppColors.bois.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Row(
            children: [
              // Rang.
              SizedBox(
                width: 40,
                child: Text(
                  '#${entry.rank}',
                  style: AppTypography.bebas(
                    size: 20,
                    color: isTop3 ? AppColors.orSoleil : AppColors.ivoire,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Avatar circulaire.
              _Avatar(displayName: entry.displayName),
              const SizedBox(width: 12),
              // Nom + badge MAÎTRE.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.displayName,
                      style: AppTypography.bebas(
                        size: 15,
                        color:
                            isMe ? AppColors.orSoleil : AppColors.ivoire,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isMaster)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: _MasterBadge(),
                      ),
                  ],
                ),
              ),
              // Altitude.
              Text(
                entry.altitudeLabel,
                style: AppTypography.bebas(color: AppColors.orSoleil),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRemoveMenu(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.boisFonce,
        title: Text(
          'friends.remove_title'.tr(),
          style: AppTypography.bebas(size: 18),
        ),
        content: Text(
          'friends.remove_body'.tr(args: [entry.displayName]),
          style: AppTypography.crimson(size: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr(), style: AppTypography.bebas()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'friends.remove_confirm'.tr(),
              style: AppTypography.bebas(color: AppColors.rouge),
            ),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      onRemove?.call();
    }
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.displayName});
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.bois.withValues(alpha: 0.6),
        border: Border.all(
          color: AppColors.orSoleil.withValues(alpha: 0.5),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTypography.bebas(size: 18),
      ),
    );
  }
}

class _MasterBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.orChaud.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.orChaud.withValues(alpha: 0.6),
        ),
      ),
      child: Text(
        'leaderboard.badge_master'.tr(),
        style: AppTypography.bebas(size: 10, color: AppColors.orChaud),
      ),
    );
  }
}
