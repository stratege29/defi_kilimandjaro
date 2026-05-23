import 'dart:io';
import 'dart:ui' as ui;

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/matchmaking_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/presentation/duel/lobby_controller.dart'
    show lobbyPreviousMatchIdProvider, lobbyRematchUidProvider;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Résultat d'un duel 3-manches — score global + détail par manche.
class DuelResultView extends ConsumerStatefulWidget {
  const DuelResultView({required this.session, super.key});

  final DuelSession session;

  @override
  ConsumerState<DuelResultView> createState() => _DuelResultViewState();
}

class _DuelResultViewState extends ConsumerState<DuelResultView> {
  final Logger _log = Logger();
  EloDelta? _eloDelta;
  bool _eloLoading = true;
  bool _shareLoading = false;

  final GlobalKey _repaintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _computeEloIfRanked();
  }

  Future<void> _computeEloIfRanked() async {
    if (!widget.session.isRanked) {
      setState(() => _eloLoading = false);
      return;
    }
    final winnerUid = widget.session.winner ?? '';
    if (winnerUid.isEmpty) {
      setState(() => _eloLoading = false);
      return;
    }
    try {
      final delta = await ref
          .read(matchmakingRepositoryProvider)
          .endMatch(matchId: widget.session.matchId, winnerUid: winnerUid);
      if (mounted) {
        setState(() {
          _eloDelta = delta;
          _eloLoading = false;
        });
      }
    } on Exception catch (e) {
      _log.e('endMatch failed', error: e);
      if (mounted) setState(() => _eloLoading = false);
    }
  }

  String? _opponentUid() {
    final myUid = ref.read(firebaseAuthProvider).currentUser?.uid ?? '';
    for (final uid in widget.session.players.keys) {
      if (uid != myUid) return uid;
    }
    return null;
  }

  void _onRematch() {
    final opponentUid = _opponentUid();
    if (opponentUid != null) {
      ref.read(lobbyRematchUidProvider.notifier).state = opponentUid;
    }
    ref.read(lobbyPreviousMatchIdProvider.notifier).state =
        widget.session.matchId;
    context.go(AppRoutes.duelLobby);
  }

  Future<void> _onShare() async {
    if (_shareLoading) return;
    setState(() => _shareLoading = true);

    try {
      final repo = ref.read(duelRepositoryProvider);
      final (:matchId, secret: _) = await repo.createDuel();
      final deepLink = 'kilimandjaro://duel/$matchId';

      final boundary =
          _repaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;

      XFile? imageFile;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 2);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final tmpDir = await getTemporaryDirectory();
          final file = File('${tmpDir.path}/kilimandjaro_result.png');
          await file.writeAsBytes(byteData.buffer.asUint8List());
          imageFile = XFile(file.path, mimeType: 'image/png');
        }
      }

      final delta = _eloDelta?.delta;
      final altitudeText =
          delta != null ? '${delta >= 0 ? '+' : ''}${delta}m' : '';
      final shareText = altitudeText.isNotEmpty
          ? "J'ai gravi $altitudeText d'altitude sur Kilimandjaro Sagesse Ivoirienne !\nDéfie-moi : $deepLink"
          : 'Affronte-moi sur Kilimandjaro Sagesse Ivoirienne !\nDéfi : $deepLink';

      if (imageFile != null) {
        await SharePlus.instance.share(
          ShareParams(files: [imageFile], text: shareText),
        );
      } else {
        await SharePlus.instance.share(ShareParams(text: shareText));
      }
    } on Exception catch (e) {
      _log.e('Share failed', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de partager le défi.')),
      );
    } finally {
      if (mounted) setState(() => _shareLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = ref.read(firebaseAuthProvider).currentUser?.uid ?? '';
    final self = widget.session.players[myUid];
    final opponent = widget.session.opponentOf(myUid);
    final selfScore = self?.roundsWon ?? 0;
    final opponentScore = opponent?.roundsWon ?? 0;
    final won = widget.session.winner == myUid;

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: RepaintBoundary(
                  key: _repaintKey,
                  child: ColoredBox(
                    color: AppColors.vertForet,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 12),

                          // Trophée ou icône résultat.
                          if (won)
                            Image.asset(
                              AppAssets.duelTrophy,
                              width: 100,
                              height: 100,
                            )
                          else
                            Image.asset(
                              AppAssets.iconStreak,
                              width: 100,
                              height: 100,
                            ),
                          const SizedBox(height: 12),

                          // Titre VICTOIRE / DÉFAITE.
                          Text(
                            won ? 'VICTOIRE' : 'DÉFAITE',
                            style: AppTypography.bebas(
                              size: 36,
                              color: won
                                  ? AppColors.vertClair
                                  : AppColors.rouge,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            won
                                ? 'Tu as été le plus fort !'
                                : 'Ton adversaire a été plus fort.',
                            textAlign: TextAlign.center,
                            style: AppTypography.crimson(
                              size: 14,
                              color: AppColors.textePrimaire,
                              style: FontStyle.italic,
                            ),
                          ),

                          // Score final en grand.
                          const SizedBox(height: 20),
                          Semantics(
                            label:
                                'Score final : Toi $selfScore - Adversaire $opponentScore',
                            child: _FinalScoreBadge(
                              selfScore: selfScore,
                              opponentScore: opponentScore,
                              won: won,
                            ),
                          ),

                          // Section ELO (ranked uniquement).
                          if (widget.session.isRanked) ...[
                            const SizedBox(height: 16),
                            _EloSection(
                              loading: _eloLoading,
                              delta: _eloDelta,
                              won: won,
                            ),
                          ],

                          // Détail des 3 manches.
                          const SizedBox(height: 20),
                          _RoundsBreakdown(
                            session: widget.session,
                            selfUid: myUid,
                          ),

                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // CTAs.
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go(AppRoutes.hub),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.vertClair,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'RETOUR AU HUB',
                    style: AppTypography.bebas(
                      size: 18,
                      color: AppColors.vertForet,
                    ),
                  ),
                ),
              ),
              if (widget.session.isRanked) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _onRematch,
                    icon: const Icon(
                      Icons.replay,
                      color: AppColors.vertClair,
                      size: 20,
                    ),
                    label: Text(
                      'REMATCH',
                      style: AppTypography.bebas(
                        size: 18,
                        color: AppColors.vertClair,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.vertClair),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _shareLoading ? null : _onShare,
                    icon: _shareLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: AppColors.orChaud,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.share,
                            color: AppColors.orChaud,
                            size: 20,
                          ),
                    label: Text(
                      'PARTAGER LE DÉFI',
                      style: AppTypography.bebas(
                        size: 18,
                        color: AppColors.orChaud,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.orChaud),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Score final
// ---------------------------------------------------------------------------

class _FinalScoreBadge extends StatelessWidget {
  const _FinalScoreBadge({
    required this.selfScore,
    required this.opponentScore,
    required this.won,
  });

  final int selfScore;
  final int opponentScore;
  final bool won;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: won
              ? AppColors.orJour.withValues(alpha: 0.6)
              : AppColors.laterite.withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ScoreCol(label: 'Toi', value: selfScore, highlighted: won),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '-',
              style: AppTypography.displayMd.copyWith(
                color: AppColors.texteSecondaire,
              ),
            ),
          ),
          _ScoreCol(
            label: 'Adv.',
            value: opponentScore,
            highlighted: !won,
          ),
        ],
      ),
    );
  }
}

class _ScoreCol extends StatelessWidget {
  const _ScoreCol({
    required this.label,
    required this.value,
    required this.highlighted,
  });

  final String label;
  final int value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? AppColors.orJour : AppColors.textePrimaire;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: AppTypography.displayLg.copyWith(color: color),
        ),
        Text(label, style: AppTypography.labelSm.copyWith(color: color)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Détail des 3 manches
// ---------------------------------------------------------------------------

class _RoundsBreakdown extends StatelessWidget {
  const _RoundsBreakdown({
    required this.session,
    required this.selfUid,
  });

  final DuelSession session;
  final String selfUid;

  @override
  Widget build(BuildContext context) {
    final self = session.players[selfUid];
    final opponent = session.opponentOf(selfUid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DÉTAIL DES MANCHES',
          style: AppTypography.headingSm.copyWith(
            color: AppColors.texteSecondaire,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        ...List<Widget>.generate(session.totalRounds, (i) {
          final roundData = i < session.rounds.length
              ? session.rounds[i]
              : null;
          final selfRound = self?.rounds[i];
          final opponentRound = opponent?.rounds[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RoundCard(
              roundIndex: i,
              roundData: roundData,
              selfRound: selfRound,
              opponentRound: opponentRound,
              selfUid: selfUid,
              opponentUid: opponent?.uid,
            ),
          );
        }),
      ],
    );
  }
}

class _RoundCard extends StatelessWidget {
  const _RoundCard({
    required this.roundIndex,
    required this.roundData,
    required this.selfRound,
    required this.opponentRound,
    required this.selfUid,
    required this.opponentUid,
  });

  final int roundIndex;
  final RoundData? roundData;
  final RoundResult? selfRound;
  final RoundResult? opponentRound;
  final String selfUid;
  final String? opponentUid;

  String get _difficultyLabel {
    final d = roundData?.difficulty ?? 'easy';
    return switch (d) {
      'easy' => 'Facile',
      'medium' => 'Moyen',
      'hard' => 'Difficile',
      _ => d,
    };
  }

  String _formatMs(int? ms) {
    if (ms == null) return '--';
    return '${(ms / 1000).toStringAsFixed(1)} s';
  }

  /// Détermine qui a gagné ce round.
  String? _roundWinnerUid() {
    final selfFound = selfRound?.found ?? false;
    final opponentFound = opponentRound?.found ?? false;
    if (!selfFound && !opponentFound) return null;
    if (selfFound && !opponentFound) return selfUid;
    if (!selfFound && opponentFound) return opponentUid;
    // Les deux ont trouvé — le plus rapide.
    final sMs = selfRound!.timeTakenMs ?? 0;
    final oMs = opponentRound!.timeTakenMs ?? 0;
    return sMs <= oMs ? selfUid : opponentUid;
  }

  @override
  Widget build(BuildContext context) {
    final winnerUid = _roundWinnerUid();
    final selfWon = winnerUid == selfUid;
    final draw = winnerUid == null;

    final Color borderColor;
    final IconData resultIcon;

    if (draw) {
      borderColor = AppColors.texteSecondaire.withValues(alpha: 0.3);
      resultIcon = Icons.remove_circle_outline;
    } else if (selfWon) {
      borderColor = AppColors.orJour.withValues(alpha: 0.5);
      resultIcon = Icons.check_circle_outline;
    } else {
      borderColor = AppColors.laterite.withValues(alpha: 0.4);
      resultIcon = Icons.cancel_outlined;
    }

    final iconColor = draw
        ? AppColors.texteSecondaire
        : (selfWon ? AppColors.orJour : AppColors.laterite);

    final selfTime = (selfRound?.found ?? false)
        ? _formatMs(selfRound?.timeTakenMs)
        : '--';
    final opponentTime = (opponentRound?.found ?? false)
        ? _formatMs(opponentRound?.timeTakenMs)
        : '--';

    final neitherFound =
        !(selfRound?.found ?? false) && !(opponentRound?.found ?? false);

    return Semantics(
      label:
          'Manche ${roundIndex + 1} : $_difficultyLabel. ${selfWon ? "Gagnée" : draw ? "Nulle" : "Perdue"}. Ton temps : $selfTime, adversaire : $opponentTime',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(resultIcon, size: 20, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  'Manche ${roundIndex + 1}',
                  style: AppTypography.headingSm.copyWith(color: iconColor),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _difficultyLabel,
                    style: AppTypography.labelXs,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (neitherFound)
              Text(
                "Personne n'a trouve le mot",
                style: AppTypography.bodySm,
              )
            else
              Row(
                children: [
                  _TimeChip(label: 'Toi', time: selfTime, highlight: selfWon),
                  const SizedBox(width: 12),
                  _TimeChip(
                    label: 'Adv.',
                    time: opponentTime,
                    highlight: !selfWon && !draw,
                  ),
                ],
              ),
            if (roundData != null && roundData!.answer.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Mot : ${roundData!.answer}',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.texteSecondaire,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.label,
    required this.time,
    required this.highlight,
  });

  final String label;
  final String time;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.orJour : AppColors.textePrimaire;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label : ',
          style: AppTypography.bodySm,
        ),
        Text(
          time,
          style: AppTypography.headingSm.copyWith(color: color),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section ELO (ranked)
// ---------------------------------------------------------------------------

class _EloSection extends StatelessWidget {
  const _EloSection({
    required this.loading,
    required this.delta,
    required this.won,
  });

  final bool loading;
  final EloDelta? delta;
  final bool won;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: AppColors.orSoleil,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    if (delta == null) return const SizedBox.shrink();

    final d = delta!.delta;
    final sign = d >= 0 ? '+' : '';
    final color = d >= 0 ? AppColors.vertClair : AppColors.rouge;
    final label = "$sign$d m d'altitude";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(label, style: AppTypography.bebas(size: 22, color: color)),
          Text(
            'Nouvelle altitude : ${delta!.newElo} m',
            style: AppTypography.crimson(
              size: 13,
              color: AppColors.texteSecondaire,
            ),
          ),
        ],
      ),
    );
  }
}
