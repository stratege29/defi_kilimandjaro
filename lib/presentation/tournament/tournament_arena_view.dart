import 'dart:async';

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
import 'package:defi_kilimandjaro/presentation/tournament/widgets/tournament_countdown.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

/// Moteur de la boucle d'arène : tant que la fenêtre du tournoi est ouverte,
/// demande un match (`requestArenaMatch`), lance le duel (réutilise
/// [DuelPlayView] via la route `duelPlay`), puis ré-enchaîne au retour. Affiche
/// entre deux matchs : points/rang du joueur, temps restant, classement live.
///
/// La boucle vit dans l'état de la vue (pattern `await context.push` : le futur
/// se résout au `pop` du duel), ce qui sérialise naturellement les matchs sans
/// machine à états séparée.
class TournamentArenaView extends ConsumerStatefulWidget {
  const TournamentArenaView({required this.tournamentId, super.key});

  final String tournamentId;

  @override
  ConsumerState<TournamentArenaView> createState() =>
      _TournamentArenaViewState();
}

class _TournamentArenaViewState extends ConsumerState<TournamentArenaView> {
  final String _requestId = const Uuid().v4();
  int _expansionStep = 0;
  bool _searching = true;
  bool _loopStarted = false;

  String get _tid => widget.tournamentId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startLoop());
  }

  void _startLoop() {
    if (_loopStarted) return;
    _loopStarted = true;
    unawaited(_runLoop());
  }

  Future<void> _runLoop() async {
    final repo = ref.read(tournamentRepositoryProvider);

    while (mounted) {
      final tournament = ref.read(tournamentProvider(_tid)).value;
      if (tournament != null && !tournament.isOpenAt(DateTime.now())) {
        break; // fenêtre close → résultats
      }

      if (mounted) setState(() => _searching = true);

      ArenaMatchResult result;
      try {
        result = await repo.requestArenaMatch(
          tid: _tid,
          requestId: _requestId,
          expansionStep: _expansionStep,
        );
      } on Exception {
        // Erreur transitoire ou fenêtre fermée côté serveur : on temporise
        // puis on re-vérifie la condition de boucle.
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }

      if (!mounted) return;

      if (result is ArenaMatched) {
        _expansionStep = 0;
        setState(() => _searching = false);
        // Lance le duel ; le futur se résout quand DuelPlayView fait `pop`
        // (fin de match → endMatch déjà appelé côté DuelPlayView).
        await context.push<void>(
          AppRoutes.duelPlay,
          extra: DuelPlayArgs(session: result.session, tournamentId: _tid),
        );
        if (!mounted) return;
        // Petite respiration avant la recherche suivante.
        await Future<void>.delayed(const Duration(milliseconds: 600));
      } else {
        // En attente : élargit progressivement la bande de points.
        _expansionStep = (_expansionStep + 1).clamp(0, 6);
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }

    if (mounted) {
      context.go(AppRoutes.tournamentResultsPath(_tid));
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: Text('tournament.leave_confirm_title'.tr(),
            style: AppTypography.headingSm),
        content: Text('tournament.leave_confirm_body'.tr(),
            style: AppTypography.crimson(size: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('tournament.leave_arena'.tr(),
                style: const TextStyle(color: AppColors.rouge)),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tid = _tid;
    final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final tournament = ref.watch(tournamentProvider(tid)).value;
    final standings = ref.watch(tournamentStandingsProvider(tid)).value ?? [];
    final myParticipant = uid == null
        ? null
        : ref.watch(_arenaParticipantProvider((tid: tid, uid: uid))).value;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          automaticallyImplyLeading: false,
          title: Text(tournament?.name ?? 'tournament.title'.tr(),
              style: AppTypography.headingMd),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: AppColors.texteSecondaire),
              onPressed: _confirmLeave,
            ),
          ],
        ),
        body: Column(
          children: [
            _StatusHeader(
              tournament: tournament,
              participant: myParticipant,
              searching: _searching,
            ),
            const Divider(height: 1, color: AppColors.hairline),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('tournament.standings'.tr(),
                        style: AppTypography.headingSm),
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(
                      child: StandingsList(
                        participants: standings,
                        highlightUid: uid,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.tournament,
    required this.participant,
    required this.searching,
  });

  final Tournament? tournament;
  final TournamentParticipant? participant;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      color: AppColors.surfaceVariant,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat(
                label: 'tournament.your_points'.tr(),
                value: '${participant?.points ?? 0}',
              ),
              _Stat(
                label: 'tournament.your_rank'.tr(),
                value: participant?.rank != null
                    ? '${participant!.rank}'
                    : '—',
              ),
              Column(
                children: [
                  Text(
                    'tournament.time_left'.tr(),
                    style: AppTypography.labelXs
                        .copyWith(color: AppColors.texteSecondaire),
                  ),
                  const SizedBox(height: 2),
                  if (tournament != null)
                    TournamentCountdown(
                      target: tournament!.endAt,
                      color: AppColors.kola,
                      style: AppTypography.bebas(size: 22),
                    )
                  else
                    Text('—', style: AppTypography.bebas(size: 22)),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SearchingBanner(searching: searching),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: AppTypography.labelXs
                .copyWith(color: AppColors.texteSecondaire)),
        const SizedBox(height: 2),
        Text(value,
            style: AppTypography.bebas(size: 22, color: AppColors.orSoleil)),
      ],
    );
  }
}

class _SearchingBanner extends StatelessWidget {
  const _SearchingBanner({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (searching) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'tournament.searching_opponent'.tr(),
            style: AppTypography.crimson(
              size: 14,
              color: AppColors.texteSecondaire,
            ),
          ),
        ] else
          Text(
            'tournament.next_match_soon'.tr(),
            style: AppTypography.crimson(
              size: 14,
              color: AppColors.texteSecondaire,
            ),
          ),
      ],
    );
  }
}

/// Provider local : fiche du participant courant dans l'arène.
final _arenaParticipantProvider = StreamProvider.family<TournamentParticipant?,
    ({String tid, String uid})>((ref, key) {
  return ref
      .watch(tournamentRepositoryProvider)
      .watchMyParticipant(key.tid, key.uid);
});
