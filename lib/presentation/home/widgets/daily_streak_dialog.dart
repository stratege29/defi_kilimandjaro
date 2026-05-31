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
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.orJour.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Flamme ▲ or (maquette `.fire`).
            const Icon(
              Icons.local_fire_department_rounded,
              size: 40,
              color: AppColors.orJour,
            ),
            const SizedBox(height: 6),
            // Eyebrow doré all-caps espacé (maquette `.eyebrow2`).
            Text(
              'SÉRIE · JOUR $streakDay',
              style: AppTypography.labelXs.copyWith(
                color: AppColors.orJour,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            // Escalier 7 jours (cases ✓ acquis / chiffre courant).
            _StreakLadder(
              currentDay: streakDay,
              rewards: rewards,
            ),
            const SizedBox(height: 16),
            Text(
              'Reviens chaque jour pour gravir plus vite.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMd.copyWith(
                fontSize: 13,
                color: AppColors.texteSecondaire,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            // Pastille récompense du jour (maquette `.reward`).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.orJour.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.orJour.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CaurisIcon(size: 16),
                  const SizedBox(width: 7),
                  Text(
                    '+$bonus cauris',
                    style: AppTypography.bodyMd.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.orJour,
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

/// Échelle 7 cases (maquette `.ladder`). Les jours acquis affichent un ✓ vert,
/// le jour courant son chiffre en or, les jours à venir leur chiffre en gris.
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
          _StreakDay(day: i, current: currentDay),
        ],
      ],
    );
  }
}

/// Case unique de l'échelle (maquette `.day` / `.day.done` / `.day.now`).
class _StreakDay extends StatelessWidget {
  const _StreakDay({required this.day, required this.current});

  final int day;
  final int current;

  @override
  Widget build(BuildContext context) {
    final isCurrent = day == current;
    final isPast = day < current;

    final (Color bg, Color border, Color fg) = isPast
        ? (
            AppColors.vertClair.withValues(alpha: 0.12),
            AppColors.vertClair,
            AppColors.vertClair,
          )
        : isCurrent
            ? (
                AppColors.orJour.withValues(alpha: 0.16),
                AppColors.orJour,
                AppColors.orJour,
              )
            : (
                AppColors.surfaceVariant,
                AppColors.hairline,
                AppColors.texteTertiaire,
              );

    return Container(
      width: 30,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: isPast
          ? Icon(Icons.check_rounded, size: 16, color: fg)
          : Text(
              '$day',
              style: AppTypography.labelSm.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
    );
  }
}
