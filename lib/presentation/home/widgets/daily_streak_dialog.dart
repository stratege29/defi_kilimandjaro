import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Popup escalier streak quotidien.
///
/// Affiché par `HomeView` au premier build du jour si
/// [PlayerProgressNotifier.peekClaimableStreak] retourne un résultat.
/// Le claim se fait sur le tap "RÉCOLTER" — tant que le joueur ne tape
/// pas, la session ne consomme pas le bonus (utile si l'app crash après
/// l'ouverture du popup : pas de double-claim au prochain run).
///
/// Layout :
/// - Rangée de 7 jours (J1..J7) avec le jour courant highlight or, les
///   précédents en vert (acquis), les suivants en gris (à venir)
/// - Récompense du jour en gros chip pill
/// - CTA "RÉCOLTER" primaire
class DailyStreakDialog extends ConsumerWidget {
  const DailyStreakDialog({required this.streakDay, super.key});

  /// Jour de streak qui sera atteint après le claim (1-indexed). Utilisé
  /// pour highlighter la bonne case dans l'escalier.
  final int streakDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameEconomyConfigProvider);
    final bonus = config.streakRewardForDay(streakDay);
    final rewards = config.streakRewards;

    return Dialog(
      backgroundColor: AppColors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.orJour, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.local_fire_department_rounded,
              size: 48,
              color: AppColors.orJour,
            ),
            const SizedBox(height: 6),
            Text(
              'STREAK · JOUR $streakDay',
              style: AppTypography.bebas(size: 18, color: AppColors.orJour)
                  .copyWith(letterSpacing: 2),
            ),
            const SizedBox(height: 14),
            // Escalier 7 jours.
            _StreakLadder(
              currentDay: streakDay,
              rewards: rewards,
            ),
            const SizedBox(height: 20),
            // Bonus du jour mis en avant.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.orJour.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: AppColors.orJour.withValues(alpha: 0.55),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CaurisIcon(),
                  const SizedBox(width: 8),
                  Text(
                    '+$bonus',
                    style: AppTypography.headingMd.copyWith(
                      color: AppColors.orJour,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'CAURIS',
                    style: AppTypography.labelSm.copyWith(
                      color: AppColors.orJour.withValues(alpha: 0.75),
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'RÉCOLTER',
              fullWidth: true,
              onPressed: () async {
                final bonus = await ref
                    .read(playerProgressProvider.notifier)
                    .claimDailyStreak(config: config);
                if (!context.mounted) return;
                Navigator.of(context).pop(bonus);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Rangée d'icônes correspondant aux 7 paliers du streak. Le jour courant
/// est entouré + or pulsé, les précédents (1..current-1) en vert "acquis",
/// les suivants en gris atténué pour donner la trajectoire à venir.
class _StreakLadder extends StatelessWidget {
  const _StreakLadder({required this.currentDay, required this.rewards});

  final int currentDay;
  final List<int> rewards;

  @override
  Widget build(BuildContext context) {
    final length = rewards.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (var i = 1; i <= length; i++) ...<Widget>[
          if (i > 1) const SizedBox(width: 6),
          Expanded(child: _StreakStep(day: i, current: currentDay, reward: rewards[i - 1])),
        ],
      ],
    );
  }
}

class _StreakStep extends StatelessWidget {
  const _StreakStep({
    required this.day,
    required this.current,
    required this.reward,
  });

  final int day;
  final int current;
  final int reward;

  @override
  Widget build(BuildContext context) {
    final isCurrent = day == current;
    final isPast = day < current;
    final color = isCurrent
        ? AppColors.orJour
        : (isPast
            ? AppColors.vertClair
            : AppColors.textePrimaire.withValues(alpha: 0.3));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.orJour.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: isCurrent ? 0.8 : 0.4),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'J$day',
            style: AppTypography.bebas(size: 11, color: color),
          ),
          const SizedBox(height: 2),
          Icon(
            isPast ? Icons.check_circle_rounded : Icons.local_fire_department,
            size: 14,
            color: color,
          ),
          const SizedBox(height: 2),
          Text(
            '+$reward',
            style: AppTypography.bebas(size: 10, color: color),
          ),
        ],
      ),
    );
  }
}
