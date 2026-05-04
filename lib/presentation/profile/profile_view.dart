import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/honorific_title.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';
import 'package:defi_kilimandjaro/presentation/hub/widgets/bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran 08 — Profil joueur (cf. maquette p.10).
///
/// Tableau de bord personnel : avatar, titre honorifique, 4 stats,
/// pays explorés, 4 titres progressifs, settings (son, timer, reset).
class ProfileView extends ConsumerWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(playerProgressProvider);
    final asyncMountains = ref.watch(mountainsProvider);
    final audioState = ref.watch(audioControllerProvider);

    final title = HonorificTitle.currentFor(progress.totalLevelsCompleted);

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            _AvatarHeader(title: title),
            const SizedBox(height: 24),
            _StatsRow(
              progress: progress,
              countriesExplored: asyncMountains.maybeWhen(
                data: (list) =>
                    list.where((m) => progress.levelsOn(m.id) > 0).length,
                orElse: () => 0,
              ),
            ),
            const SizedBox(height: 28),
            _Section(
              title: 'PAYS EXPLORÉS',
              child: asyncMountains.when(
                loading: () => const SizedBox(
                  height: 60,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.orSoleil,
                    ),
                  ),
                ),
                error: (_, __) => Text(
                  'Erreur de chargement',
                  style: AppTypography.crimson(),
                ),
                data: (list) => _ExploredCountriesGrid(
                  mountains: list,
                  progress: progress,
                ),
              ),
            ),
            const SizedBox(height: 28),
            _Section(
              title: 'TITRES HONORIFIQUES',
              child: Column(
                children: [
                  for (final t in HonorificTitle.values)
                    _TitleRow(
                      title: t,
                      unlocked: progress.totalLevelsCompleted >= t.threshold,
                      isCurrent: title == t,
                      progressTowards: progress.totalLevelsCompleted,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _Section(
              title: 'PARAMÈTRES',
              child: Column(
                children: [
                  _SettingTile(
                    icon: audioState.muted ? Icons.volume_off : Icons.volume_up,
                    label: 'Son',
                    valueLabel: audioState.muted ? 'Muet' : 'Activé',
                    onTap: () => ref
                        .read(audioControllerProvider.notifier)
                        .toggleMute(),
                  ),
                  _SettingTile(
                    icon: Icons.refresh,
                    label: 'Réinitialiser la progression',
                    valueLabel: '',
                    danger: true,
                    onTap: () => _confirmReset(context, ref),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: NavTab.profil,
        onTabSelected: (t) {
          switch (t) {
            case NavTab.jouer:
              context.go(AppRoutes.hub);
            case NavTab.afrique:
              context.go(AppRoutes.mountains);
            case NavTab.profil:
              break;
          }
        },
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.boisFonce,
        title: Text(
          'Réinitialiser ?',
          style: AppTypography.bebas(size: 18),
        ),
        content: Text(
          'Tous les coins, niveaux et titres seront perdus. Action '
          'irréversible.',
          style: AppTypography.crimson(size: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Annuler',
              style: AppTypography.bebas(),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Réinitialiser',
              style: AppTypography.bebas(color: AppColors.rouge),
            ),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(playerProgressProvider.notifier).reset();
    }
  }
}

// ---------------------------------------------------------------------------
// Avatar + name + current title
// ---------------------------------------------------------------------------

class _AvatarHeader extends StatelessWidget {
  const _AvatarHeader({required this.title});
  final HonorificTitle? title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.bois.withValues(alpha: 0.5),
            border: Border.all(color: AppColors.orSoleil, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.person, color: AppColors.ivoire, size: 40),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Joueur', style: AppTypography.bebas(size: 22)),
              const SizedBox(height: 6),
              if (title != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.vertClair.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.vertClair.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title!.icon, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(
                        title!.name,
                        style: AppTypography.bebas(
                          size: 13,
                          color: AppColors.vertClair,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  'Encore aucun titre — joue 5 niveaux',
                  style: AppTypography.crimson(
                    size: 13,
                    color: AppColors.ivoire.withValues(alpha: 0.6),
                    style: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stats row : Niveaux · Coins · Pays · Streak
// ---------------------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.progress, required this.countriesExplored});

  final PlayerProgress progress;
  final int countriesExplored;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatBox(
            icon: '🏆',
            label: 'Niveaux',
            value: '${progress.totalLevelsCompleted}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatBox(
            icon: '🪙',
            label: 'Coins',
            value: '${progress.coins}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatBox(
            icon: '🏔️',
            label: 'Pays',
            value: '$countriesExplored',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatBox(
            icon: '🔥',
            label: 'Streak',
            value: '${progress.dailyStreak}',
          ),
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
  });

  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.orSoleil.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 2),
          Text(value, style: AppTypography.bebas(size: 20)),
          Text(
            label,
            style: AppTypography.crimson(
              size: 11,
              color: AppColors.ivoire.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section wrapper with golden header
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.bebas(size: 14)),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Explored countries — wrap of flag chips
// ---------------------------------------------------------------------------

class _ExploredCountriesGrid extends StatelessWidget {
  const _ExploredCountriesGrid({
    required this.mountains,
    required this.progress,
  });

  final List<Mountain> mountains;
  final PlayerProgress progress;

  @override
  Widget build(BuildContext context) {
    final explored = mountains
        .where((m) => progress.levelsOn(m.id) > 0)
        .toList();

    if (explored.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bois.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.orSoleil.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          "Explore la carte d'Afrique pour commencer ton voyage",
          style: AppTypography.crimson(
            size: 13,
            color: AppColors.ivoire.withValues(alpha: 0.6),
            style: FontStyle.italic,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in explored)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.bois.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.orSoleil.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.flagEmoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  m.countryName,
                  style: AppTypography.bebas(size: 13),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Honorific title row (locked / current / unlocked)
// ---------------------------------------------------------------------------

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.title,
    required this.unlocked,
    required this.isCurrent,
    required this.progressTowards,
  });

  final HonorificTitle title;
  final bool unlocked;
  final bool isCurrent;
  final int progressTowards;

  @override
  Widget build(BuildContext context) {
    final bg = isCurrent
        ? AppColors.vertClair.withValues(alpha: 0.18)
        : unlocked
            ? AppColors.bois.withValues(alpha: 0.30)
            : AppColors.bois.withValues(alpha: 0.12);

    final border = isCurrent
        ? AppColors.vertClair.withValues(alpha: 0.7)
        : unlocked
            ? AppColors.orSoleil.withValues(alpha: 0.4)
            : AppColors.orSoleil.withValues(alpha: 0.15);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: unlocked ? 1 : 0.35,
            child: Text(title.icon, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      title.name,
                      style: AppTypography.bebas(
                        color: unlocked
                            ? AppColors.ivoire
                            : AppColors.ivoire.withValues(alpha: 0.5),
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.star,
                        color: AppColors.orSoleil,
                        size: 14,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  unlocked
                      ? title.description
                      : 'Termine ${title.threshold} niveaux pour débloquer '
                          '($progressTowards/${title.threshold})',
                  style: AppTypography.crimson(
                    size: 12,
                    color: AppColors.ivoire.withValues(alpha: 0.7),
                    style: FontStyle.italic,
                  ),
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
// Settings tile
// ---------------------------------------------------------------------------

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.rouge : AppColors.orSoleil;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bois.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bebas(
                    size: 15,
                    color: danger ? AppColors.rouge : AppColors.ivoire,
                  ),
                ),
              ),
              if (valueLabel.isNotEmpty)
                Text(
                  valueLabel,
                  style: AppTypography.bebas(size: 13, color: color),
                ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: color.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}
