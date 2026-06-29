import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart'
    show firebaseAuthProvider;
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/tournament_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/domain/entities/tournament.dart';
import 'package:defi_kilimandjaro/domain/entities/tournament_participant.dart';
import 'package:defi_kilimandjaro/presentation/packs/pack_display.dart';
import 'package:defi_kilimandjaro/presentation/tournament/widgets/standings_list.dart';
import 'package:defi_kilimandjaro/presentation/tournament/widgets/tournament_countdown.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Salle d'attente d'un tournoi : compte à rebours, participants, règles +
/// récompenses, et inscription. Quand le tournoi est `live` et que le joueur
/// est inscrit, le bouton bascule sur « Entrer dans l'arène ».
class TournamentDetailView extends ConsumerStatefulWidget {
  const TournamentDetailView({required this.tournamentId, super.key});

  final String tournamentId;

  @override
  ConsumerState<TournamentDetailView> createState() =>
      _TournamentDetailViewState();
}

class _TournamentDetailViewState extends ConsumerState<TournamentDetailView> {
  bool _joining = false;

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      await ref
          .read(tournamentRepositoryProvider)
          .joinTournament(widget.tournamentId);
    } on Exception catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('tournament.join_failed'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _enterArena() {
    context.push(AppRoutes.tournamentArenaPath(widget.tournamentId));
  }

  @override
  Widget build(BuildContext context) {
    final tid = widget.tournamentId;
    final async = ref.watch(tournamentProvider(tid));
    final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final myParticipant = uid == null
        ? const AsyncValue<TournamentParticipant?>.data(null)
        : ref.watch(_myParticipantProvider((tid: tid, uid: uid)));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('tournament.title'.tr(), style: AppTypography.headingMd),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Text(
            'error.load_failed'.tr(),
            style: AppTypography.crimson(color: AppColors.texteSecondaire),
          ),
        ),
        data: (tournament) {
          if (tournament == null) {
            return Center(
              child: Text(
                'tournament.not_found'.tr(),
                style: AppTypography.crimson(color: AppColors.texteSecondaire),
              ),
            );
          }
          final joined = myParticipant.value != null;
          return _Body(
            tournament: tournament,
            joined: joined,
            joining: _joining,
            onJoin: _join,
            onEnterArena: _enterArena,
            highlightUid: uid,
          );
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.tournament,
    required this.joined,
    required this.joining,
    required this.onJoin,
    required this.onEnterArena,
    required this.highlightUid,
  });

  final Tournament tournament;
  final bool joined;
  final bool joining;
  final VoidCallback onJoin;
  final VoidCallback onEnterArena;
  final String? highlightUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standings =
        ref.watch(tournamentStandingsProvider(tournament.id)).value ?? [];
    final isLive = tournament.isLive;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(tournament.name, style: AppTypography.displaySm),
              const SizedBox(height: AppSpacing.md),
              if (tournament.isScheduled || tournament.isLive) ...[
                _CountdownBanner(tournament: tournament),
                const SizedBox(height: AppSpacing.md),
              ],
              _InfoRow(
                icon: Icons.group,
                label: 'tournament.participants'
                    .tr(args: ['${tournament.participantCount}']),
              ),
              _InfoRow(
                icon: Icons.timer_outlined,
                label: 'tournament.duration'
                    .tr(args: ['${tournament.durationMin}']),
              ),
              if (tournament.packIds.isNotEmpty)
                _PacksRow(packIds: tournament.packIds),
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _showRulesDialog(context, tournament),
                  icon: const Icon(Icons.info_outline,
                      size: 18, color: AppColors.orSoleil),
                  label: Text(
                    'tournament.rules'.tr(),
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.orSoleil),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              if (tournament.rewards.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _RewardsCard(tournament: tournament),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text('tournament.standings'.tr(),
                  style: AppTypography.headingSm),
              const SizedBox(height: AppSpacing.sm),
              StandingsList(
                participants: standings,
                highlightUid: highlightUid,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: _PrimaryAction(
              tournament: tournament,
              joined: joined,
              joining: joining,
              onJoin: onJoin,
              onEnterArena: onEnterArena,
            ),
          ),
        ),
        if (isLive && joined) const SizedBox.shrink(),
      ],
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.tournament,
    required this.joined,
    required this.joining,
    required this.onJoin,
    required this.onEnterArena,
  });

  final Tournament tournament;
  final bool joined;
  final bool joining;
  final VoidCallback onJoin;
  final VoidCallback onEnterArena;

  @override
  Widget build(BuildContext context) {
    // Inscriptions fermées : tournoi terminé/annulé.
    if (tournament.isFinished || tournament.isCancelled) {
      return AppButton(
        label: 'tournament.view_results'.tr(),
        variant: AppButtonVariant.soft,
        fullWidth: true,
        onPressed: () =>
            context.push(AppRoutes.tournamentResultsPath(tournament.id)),
      );
    }

    if (tournament.isLive && joined) {
      return AppButton(
        label: 'tournament.enter_arena'.tr(),
        variant: AppButtonVariant.kola,
        fullWidth: true,
        onPressed: onEnterArena,
      );
    }

    if (joined) {
      // Inscrit mais pas encore démarré.
      return AppButton(
        label: 'tournament.joined'.tr(),
        variant: AppButtonVariant.soft,
        fullWidth: true,
        onPressed: null,
      );
    }

    if (tournament.isFull) {
      return AppButton(
        label: 'tournament.full'.tr(),
        variant: AppButtonVariant.soft,
        fullWidth: true,
        onPressed: null,
      );
    }

    return AppButton(
      label: 'tournament.join'.tr(),
      fullWidth: true,
      loading: joining,
      onPressed: joining ? null : onJoin,
    );
  }
}

class _CountdownBanner extends StatelessWidget {
  const _CountdownBanner({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final isLive = tournament.isLive;
    final label =
        isLive ? 'tournament.ends_in'.tr() : 'tournament.starts_in'.tr();
    final color = isLive ? AppColors.kola : AppColors.orSoleil;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(label,
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.texteSecondaire)),
          const SizedBox(height: AppSpacing.xs),
          TournamentCountdown(
            target: isLive ? tournament.endAt : tournament.startAt,
            color: color,
            style: AppTypography.bebas(size: 34),
          ),
        ],
      ),
    );
  }
}

/// Packs dont le tournoi tire ses devinettes, résolus en noms lisibles via le
/// catalogue (override serveur → traduction bundlée → fallback). N'apparaît que
/// si des packs ont été sélectionnés (sinon = pool global, rien à montrer).
class _PacksRow extends ConsumerWidget {
  const _PacksRow({required this.packIds});

  final List<String> packIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(packCatalogProvider).value ?? const <Pack>[];
    final byId = {for (final p in catalog) p.id: p};
    final lang = context.locale.languageCode;
    String label(String id) {
      final p = byId[id];
      return p?.localizedName(lang) ?? p?.displayName ?? id;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.style_outlined,
              size: 18, color: AppColors.texteSecondaire),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final id in packIds) _PackChip(label: label(id)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PackChip extends StatelessWidget {
  const _PackChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(label, style: AppTypography.bodySm),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.texteSecondaire),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: AppTypography.bodyMd),
        ],
      ),
    );
  }
}

/// Popup des règles du tournoi (déclenchée depuis le lien « Règles »).
Future<void> _showRulesDialog(BuildContext context, Tournament tournament) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceContainer,
      title: Text('tournament.rules'.tr(), style: AppTypography.headingSm),
      content: Text(
        'tournament.rules_body'.tr(args: [
          '${tournament.pointsWin}',
          '${tournament.pointsDraw}',
        ]),
        style: AppTypography.crimson(
          size: 14,
          color: AppColors.texteSecondaire,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('common.close'.tr()),
        ),
      ],
    ),
  );
}

class _RewardsCard extends StatelessWidget {
  const _RewardsCard({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('tournament.rewards'.tr(), style: AppTypography.headingSm),
          const SizedBox(height: AppSpacing.sm),
          ...tournament.rewards.map(
            (t) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.rankMin == t.rankMax
                          ? 'tournament.rank_single'
                              .tr(args: ['${t.rankMin}'])
                          : 'tournament.rank_range'
                              .tr(args: ['${t.rankMin}', '${t.rankMax}']),
                      style: AppTypography.bodySm,
                    ),
                  ),
                  if (t.cauris > 0)
                    Text(
                      'tournament.cauris'.tr(args: ['${t.cauris}']),
                      style: AppTypography.bebas(
                          size: 15, color: AppColors.orSoleil),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Provider local : fiche du participant courant pour un (tid, uid) donné.
final _myParticipantProvider = StreamProvider.family<TournamentParticipant?,
    ({String tid, String uid})>((ref, key) {
  return ref
      .watch(tournamentRepositoryProvider)
      .watchMyParticipant(key.tid, key.uid);
});
