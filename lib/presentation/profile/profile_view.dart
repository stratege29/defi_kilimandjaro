import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/avatars/avatar_catalog.dart';
import 'package:defi_kilimandjaro/domain/entities/honorific_title.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/domain/entities/player_profile.dart';
import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';
import 'package:defi_kilimandjaro/presentation/duel/lobby_view.dart'
    show kAltitudeHeroTag;
import 'package:defi_kilimandjaro/presentation/hub/widgets/bottom_nav_bar.dart';
import 'package:defi_kilimandjaro/presentation/leaderboard/widgets/display_name_prompt.dart';
import 'package:defi_kilimandjaro/presentation/mountains/widgets/mountain_silhouette_vector.dart';
import 'package:defi_kilimandjaro/presentation/profile/widgets/account_section.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:defi_kilimandjaro/presentation/widgets/flag_roundel.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

/// Écran 08 — Profil joueur, refonte world-class 2026.
///
/// Architecture éditoriale :
/// - **Hero** : avatar 96pt halo doré, nom en Fraunces, chip de titre premium.
/// - **Stats grid 2×2** : chiffres en Fraunces displaySm sur surfaceContainer
///   opaque, pictos unifiés Material outlined.
/// - **Altitude card** : altitude en Fraunces displayMd, signature 2026.
/// - **Montagnes gravies** : remplace l'ancien "Pays explorés". Liste les
///   sommets entièrement conquis (`levelsOn >= totalLevels`), un état vide
///   teaser, et une mini-section "En cours" pour les sommets partiellement
///   gravis.
/// - **Titres honorifiques** : timeline avec barre de progression réelle
///   pour les titres locked, halo or pour le titre courant.
/// - **Sections** : headings en Barlow Cond w700 + accent or fin.
class ProfileView extends ConsumerWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Defense au cold start (cf. HubView._Header) : si un provider throw
    // pendant que les fournisseurs ne sont pas encore prets (sharedPreferences
    // override pas encore applique, Firebase Auth en cours d'init), on tombe
    // sur l'etat initial vide plutot que de propager l'exception et faire
    // crasher tout le ProfileView (= ecran blanc en release).
    PlayerProgress progress;
    try {
      progress = ref.watch(playerProgressProvider);
    } on Object {
      progress = PlayerProgress.initial();
    }
    AsyncValue<List<Mountain>> asyncMountains;
    try {
      asyncMountains = ref.watch(mountainsProvider);
    } on Object {
      asyncMountains = const AsyncValue<List<Mountain>>.loading();
    }
    final audioState = ref.watch(audioControllerProvider);
    AsyncValue<PlayerProfile> profileAsync;
    try {
      profileAsync = ref.watch(playerProfileStreamProvider);
    } on Object {
      profileAsync = const AsyncValue<PlayerProfile>.loading();
    }

    final title = HonorificTitle.currentFor(progress.totalLevelsCompleted);
    final mountains = asyncMountains.value ?? const <Mountain>[];
    final conquered = mountains
        .where((m) => progress.levelsOn(m.id) >= m.totalLevels)
        .toList();
    final inProgress = mountains
        .where(
          (m) =>
              progress.levelsOn(m.id) > 0 &&
              progress.levelsOn(m.id) < m.totalLevels,
        )
        .toList();

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _ProfileHero(
              profile: profileAsync.value,
              title: title,
              levelsCompleted: progress.totalLevelsCompleted,
              mountainsConquered: conquered.length,
              cauris: progress.cauris,
            ),
            const SizedBox(height: 16),
            _AltitudeCard(profile: profileAsync.value),
            const SizedBox(height: 16),
            _StatsGrid(
              progress: progress,
              mountainsConquered: conquered.length,
            ),
            const SizedBox(height: 28),
            const _SectionHeader(title: 'MONTAGNES GRAVIES'),
            const SizedBox(height: 12),
            asyncMountains.when(
              loading: () => const SizedBox(
                height: 60,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.orJour),
                ),
              ),
              error: (_, __) => Text(
                'Erreur de chargement',
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.texteSecondaire,
                ),
              ),
              data: (_) => _MountainsBlock(
                conquered: conquered,
                inProgress: inProgress,
              ),
            ),
            const SizedBox(height: 28),
            const _SectionHeader(title: 'TITRES HONORIFIQUES'),
            const SizedBox(height: 12),
            Column(
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
            const SizedBox(height: 28),
            _SectionHeader(title: 'profile.sections.leaderboard'.tr()),
            const SizedBox(height: 12),
            _SettingTile(
              icon: Icons.emoji_events_outlined,
              label: 'profile.settings.leaderboard'.tr(),
              onTap: () => context.push(AppRoutes.leaderboard),
            ),
            const SizedBox(height: 28),
            const _SectionHeader(title: 'DEVINETTES COMMUNAUTAIRES'),
            const SizedBox(height: 12),
            _SettingTile(
              icon: Icons.add_circle_outline,
              label: 'Soumettre une devinette',
              onTap: () => context.push(AppRoutes.ugcSubmit),
            ),
            _SettingTile(
              icon: Icons.list_alt_outlined,
              label: 'Mes soumissions',
              onTap: () => context.push(AppRoutes.ugcMine),
            ),
            const SizedBox(height: 28),
            _SectionHeader(title: 'profile.account.section'.tr()),
            const SizedBox(height: 12),
            const AccountSection(),
            const SizedBox(height: 28),
            const _SectionHeader(title: 'PARAMÈTRES'),
            const SizedBox(height: 12),
            _SettingTile(
              icon: audioState.muted
                  ? Icons.volume_off_outlined
                  : Icons.volume_up_outlined,
              label: 'Son',
              trailingLabel: audioState.muted ? 'Muet' : 'Activé',
              onTap: () =>
                  ref.read(audioControllerProvider.notifier).toggleMute(),
            ),
            _SettingTile(
              icon: Icons.refresh_outlined,
              label: 'Réinitialiser la progression',
              danger: true,
              onTap: () => _confirmReset(context, ref),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: NavTab.profil,
        onTabSelected: (t) {
          switch (t) {
            case NavTab.accueil:
              context.go(AppRoutes.home);
            case NavTab.defi:
              context.go(AppRoutes.hub);
            case NavTab.sommets:
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
        backgroundColor: AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
        ),
        title: Text(
          'Réinitialiser ?',
          style: AppTypography.headingMd.copyWith(color: AppColors.error),
        ),
        content: Text(
          'Tous les cauris, niveaux et titres seront perdus. Action '
          'irréversible.',
          style: AppTypography.bodyMd.copyWith(color: AppColors.textePrimaire),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Annuler',
              style: AppTypography.headingSm.copyWith(
                color: AppColors.texteSecondaire,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Réinitialiser',
              style: AppTypography.headingSm.copyWith(color: AppColors.error),
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
// Hero éditorial — avatar halo doré + nom Fraunces + chip titre + contexte
// ---------------------------------------------------------------------------

class _ProfileHero extends ConsumerWidget {
  const _ProfileHero({
    required this.profile,
    required this.title,
    required this.levelsCompleted,
    required this.mountainsConquered,
    required this.cauris,
  });

  final PlayerProfile? profile;
  final HonorificTitle? title;
  final int levelsCompleted;
  final int mountainsConquered;
  final int cauris;

  Future<void> _editDisplayName(BuildContext context, WidgetRef ref) async {
    final (result, name) = await DisplayNamePromptDialog.show(context);
    if (!context.mounted) return;
    if (result != DisplayNamePromptResult.confirmed || name == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateDisplayName(uid, name);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surfaceContainer,
          content: Text(
            'Nom mis à jour : $name',
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.textePrimaire,
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Exception {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text(
            'Échec de la mise à jour du nom.',
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.textePrimaire,
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasName = profile?.displayName?.isNotEmpty ?? false;
    final displayName = hasName ? profile!.displayName! : 'Grimpeur anonyme';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          const _AvatarBadge(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: true,
                  label: 'Modifier le nom de grimpeur',
                  child: InkWell(
                    onTap: () => _editDisplayName(context, ref),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 4,
                      ),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              style: AppTypography.headingLg.copyWith(
                                color: hasName
                                    ? AppColors.textePrimaire
                                    : AppColors.texteSecondaire,
                                fontStyle: hasName
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.orJour.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    AppColors.orJour.withValues(alpha: 0.5),
                              ),
                            ),
                            child: const Icon(
                              Icons.edit,
                              size: 12,
                              color: AppColors.orJour,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (title != null)
                  _CurrentTitleChip(title: title!)
                else
                  Text(
                    'Encore aucun titre — joue 5 niveaux',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.texteSecondaire,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                const SizedBox(height: 10),
                _ContextLine(
                  levels: levelsCompleted,
                  mountains: mountainsConquered,
                  cauris: cauris,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar du profil — cliquable, ouvre le picker.
///
/// Lookup dynamique sur `profile.avatarId` :
/// - avatarId défini + asset valide → image du catalogue
/// - sinon → fallback `AppAssets.griotIdle` (comportement legacy)
///
/// Un petit pictogramme crayon dans le coin signale la clickabilité.
class _AvatarBadge extends ConsumerWidget {
  const _AvatarBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Defense au cold start : si playerProfileStreamProvider throw (cf.
    // ProfileView.build), on tombe sur asyncProfile=loading sans avatar.
    AsyncValue<PlayerProfile> asyncProfile;
    try {
      asyncProfile = ref.watch(playerProfileStreamProvider);
    } on Object {
      asyncProfile = const AsyncValue<PlayerProfile>.loading();
    }
    final avatar = AvatarCatalog.byId(asyncProfile.value?.avatarId);

    // Avatar SVG si défini, sinon mascotte griot PNG legacy.
    final avatarChild = avatar != null
        ? SvgPicture.asset(avatar.assetPath, fit: BoxFit.cover)
        : Image.asset(AppAssets.griotIdle, fit: BoxFit.cover);

    return Semantics(
      button: true,
      label: 'profile.avatar_badge.semantics'.tr(),
      child: GestureDetector(
        onTap: () => context.push(AppRoutes.avatarPicker),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 74,
          height: 74,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.orJour, width: 2),
                ),
                child: ClipOval(child: avatarChild),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.orJour,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.surfaceContainer,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.edit,
                    size: 12,
                    color: AppColors.vertForet,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentTitleChip extends StatelessWidget {
  const _CurrentTitleChip({required this.title});
  final HonorificTitle title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.orJour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: AppColors.orJour.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(title.badgeAsset, width: 18, height: 18),
          const SizedBox(width: 6),
          Text(
            title.name,
            style: AppTypography.labelSm.copyWith(
              color: AppColors.orJour,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextLine extends StatelessWidget {
  const _ContextLine({
    required this.levels,
    required this.mountains,
    required this.cauris,
  });

  final int levels;
  final int mountains;
  final int cauris;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: AppTypography.labelSm.copyWith(
        color: AppColors.texteSecondaire,
        letterSpacing: 0.4,
      ),
      child: Row(
        children: [
          Text('$levels niveaux'),
          _Bullet(),
          Text('$mountains sommets'),
          _Bullet(),
          const CaurisIcon(size: 12),
          const SizedBox(width: 4),
          Text('$cauris'),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 3,
        height: 3,
        decoration: const BoxDecoration(
          color: AppColors.texteTertiaire,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats grid 2×2 — Fraunces 32pt sur surfaceContainer, pictos unifiés
// ---------------------------------------------------------------------------

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.progress, required this.mountainsConquered});

  final PlayerProgress progress;
  final int mountainsConquered;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                value: '${progress.totalLevelsCompleted}',
                label: 'Niveaux',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                value: '${progress.cauris}',
                label: 'Cauris',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                value: '$mountainsConquered',
                label: 'Sommets',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                value: '${progress.dailyStreak}',
                label: 'Série',
                valueColor: AppColors.kola,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    this.valueColor,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.displaySm.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.orJour,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label.toUpperCase(),
            style: AppTypography.labelXs.copyWith(
              color: AppColors.texteTertiaire,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Altitude card — altitude en Fraunces displayMd, halo or signature
// ---------------------------------------------------------------------------

class _AltitudeCard extends StatelessWidget {
  const _AltitudeCard({required this.profile});
  final PlayerProfile? profile;

  @override
  Widget build(BuildContext context) {
    final elo = profile?.elo ?? PlayerProfile.eloInitial;
    final peak = profile?.peakElo ?? PlayerProfile.eloInitial;
    final totalDuels = profile?.totalDuels ?? 0;
    final wins = profile?.wins ?? 0;
    final losses = profile?.losses ?? 0;
    final isMaster = elo >= PlayerProfile.eloMaster;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'DÉFI EN LIGNE',
                style: AppTypography.labelSm.copyWith(
                  color: AppColors.texteSecondaire,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (peak > PlayerProfile.eloInitial) _RecordChip(peak: peak),
              if (isMaster) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.orJour.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.orJour.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    'MAÎTRE',
                    style: AppTypography.labelXs.copyWith(
                      color: AppColors.orJour,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Hero(
                tag: kAltitudeHeroTag,
                child: Text(
                  '$elo',
                  style: AppTypography.displayMd.copyWith(
                    fontSize: 44,
                    color: AppColors.orJour,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  'm',
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.texteSecondaire,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.hairline),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AltitudeStat(label: 'Duels', value: '$totalDuels'),
              ),
              Container(width: 1, height: 28, color: AppColors.hairline),
              Expanded(
                child: _AltitudeStat(
                  label: 'Victoires',
                  value: '$wins',
                  valueColor: AppColors.success,
                ),
              ),
              Container(width: 1, height: 28, color: AppColors.hairline),
              Expanded(
                child: _AltitudeStat(
                  label: 'Défaites',
                  value: '$losses',
                  valueColor: AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordChip extends StatelessWidget {
  const _RecordChip({required this.peak});
  final int peak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.orJour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.orJour.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Record · $peak m',
        style: AppTypography.labelXs.copyWith(
          color: AppColors.orJour,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _AltitudeStat extends StatelessWidget {
  const _AltitudeStat({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.displaySm.copyWith(
            fontSize: 20,
            color: valueColor ?? AppColors.textePrimaire,
            height: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label.toUpperCase(),
          style: AppTypography.labelXs.copyWith(
            color: AppColors.texteTertiaire,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section header — Barlow Cond + filet or fin
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: AppTypography.headingMd.copyWith(
            fontSize: 14,
            color: AppColors.textePrimaire,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.orJour.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Montagnes gravies + en cours — remplace l'ancien "Pays explorés"
// ---------------------------------------------------------------------------

class _MountainsBlock extends StatelessWidget {
  const _MountainsBlock({required this.conquered, required this.inProgress});

  final List<Mountain> conquered;
  final List<Mountain> inProgress;

  @override
  Widget build(BuildContext context) {
    if (conquered.isEmpty && inProgress.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.orJour.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.terrain_outlined,
              color: AppColors.texteTertiaire,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Aucun sommet conquis. Gravis ta première montagne pour la '
                'voir apparaître ici.',
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.texteSecondaire,
                  fontStyle: FontStyle.italic,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sommets conquis : carrousel horizontal d'icônes (scroll plus court
        // qu'une liste verticale quand le joueur a gravi beaucoup de sommets).
        if (conquered.isNotEmpty)
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: conquered.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _ConqueredMountainChip(mountain: conquered[i]),
            ),
          ),
        if (inProgress.isNotEmpty) ...[
          SizedBox(height: conquered.isEmpty ? 0 : 16),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6, top: 4),
            child: Text(
              'EN COURS',
              style: AppTypography.labelXs.copyWith(
                color: AppColors.texteTertiaire,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final m in inProgress) _MountainCard(mountain: m, conquered: false),
        ],
      ],
    );
  }
}

/// Vignette icône d'un sommet conquis pour le carrousel horizontal du profil.
///
/// Silhouette `.vec` posée sur une tuile Vert Nuit bordée vert (succès), avec
/// drapeau pays en coin + nom et altitude dessous.
class _ConqueredMountainChip extends StatelessWidget {
  const _ConqueredMountainChip({required this.mountain});

  final Mountain mountain;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tuile silhouette (ciel transparent du .vec sur surfaceVariant).
          SizedBox(
            height: 64,
            width: double.infinity,
            child: ColoredBox(
              color: AppColors.surfaceVariant,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MountainSilhouetteVector(mountain: mountain),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: FlagRoundel(
                      countryCode: mountain.countryCode,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mountain.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.textePrimaire,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${mountain.altitude} m',
                  style: AppTypography.labelXs.copyWith(
                    color: AppColors.texteSecondaire,
                    letterSpacing: 0.6,
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

class _MountainCard extends StatelessWidget {
  const _MountainCard({required this.mountain, required this.conquered});

  final Mountain mountain;
  final bool conquered;

  @override
  Widget build(BuildContext context) {
    final progressValue = mountain.totalLevels == 0
        ? 0.0
        : mountain.completedLevels / mountain.totalLevels;
    final accent = conquered ? AppColors.success : AppColors.orJour;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(alpha: conquered ? 0.55 : 0.3),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          FlagRoundel(countryCode: mountain.countryCode, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        mountain.name,
                        style: AppTypography.headingSm.copyWith(
                          color: AppColors.textePrimaire,
                          fontSize: 16,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (conquered)
                      const Icon(
                        Icons.verified_rounded,
                        color: AppColors.success,
                        size: 18,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${mountain.altitude} m',
                      style: AppTypography.labelXs.copyWith(
                        color: AppColors.texteSecondaire,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                          color: AppColors.texteTertiaire,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Text(
                      '${mountain.completedLevels}/${mountain.totalLevels} niveaux',
                      style: AppTypography.labelXs.copyWith(
                        color: AppColors.texteSecondaire,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                if (!conquered) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: LinearProgressIndicator(
                      value: progressValue,
                      minHeight: 4,
                      backgroundColor: AppColors.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Honorific title row — current/locked/unlocked avec progress bar réelle
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
    final accent = isCurrent
        ? AppColors.orJour
        : unlocked
        ? AppColors.success
        : AppColors.texteTertiaire;

    final progressValue = (progressTowards / title.threshold).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.orJour.withValues(alpha: 0.08)
            : AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(alpha: isCurrent ? 0.7 : 0.3),
          width: isCurrent ? 1.5 : 1.2,
        ),
        boxShadow: isCurrent
            ? <BoxShadow>[
                BoxShadow(
                  color: AppColors.orJour.withValues(alpha: 0.18),
                  blurRadius: 16,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Opacity(
            opacity: unlocked ? 1 : 0.35,
            child: Image.asset(title.badgeAsset, width: 50, height: 50),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.name,
                        style: AppTypography.headingSm.copyWith(
                          color: unlocked
                              ? AppColors.textePrimaire
                              : AppColors.texteTertiaire,
                          fontSize: 16,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.orJour.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.orJour.withValues(alpha: 0.55),
                          ),
                        ),
                        child: Text(
                          'ACTUEL',
                          style: AppTypography.labelXs.copyWith(
                            color: AppColors.orJour,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else if (unlocked)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                        size: 18,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  unlocked
                      ? title.description
                      : 'Termine ${title.threshold} niveaux',
                  style: AppTypography.bodySm.copyWith(
                    color: unlocked
                        ? AppColors.texteSecondaire
                        : AppColors.texteTertiaire,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
                if (!unlocked) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(100),
                          child: LinearProgressIndicator(
                            value: progressValue,
                            minHeight: 4,
                            backgroundColor: AppColors.surface,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.orJour.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$progressTowards/${title.threshold}',
                        style: AppTypography.labelXs.copyWith(
                          color: AppColors.texteTertiaire,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Setting tile — surfaceContainer + accents sémantiques
// ---------------------------------------------------------------------------

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingLabel,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? trailingLabel;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final accent = danger ? AppColors.error : AppColors.orJour;
    final labelColor = danger
        ? AppColors.error
        : AppColors.textePrimaire;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accent.withValues(alpha: 0.3),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.headingSm.copyWith(
                    color: labelColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (trailingLabel != null && trailingLabel!.isNotEmpty)
                Text(
                  trailingLabel!,
                  style: AppTypography.labelSm.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: accent.withValues(alpha: 0.7),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
