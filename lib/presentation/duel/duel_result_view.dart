import 'dart:io';
import 'dart:ui' as ui;

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/local/link_prompt_gate.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/matchmaking_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/avatars/avatar_catalog.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/domain/entities/player_profile.dart';
import 'package:defi_kilimandjaro/domain/services/pack_display.dart';
import 'package:defi_kilimandjaro/presentation/auth/link_account_prompt.dart';
import 'package:defi_kilimandjaro/presentation/duel/lobby_controller.dart'
    show lobbyPreviousMatchIdProvider, lobbyRematchUidProvider;
import 'package:defi_kilimandjaro/presentation/my_packs/widgets/unlock_pack_dialog.dart';
import 'package:defi_kilimandjaro/presentation/packs/pack_display.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:defi_kilimandjaro/presentation/widgets/dashed_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/pack_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
    // Le duel est terminé : moment clé pour inviter (si pertinent) à lier
    // le compte afin de sécuriser ELO et historique. Non bloquant.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowLinkAccountPrompt(
        context,
        ref,
        LinkPromptTrigger.duelFinished,
      );
    });
  }

  Future<void> _computeEloIfRanked() async {
    if (!widget.session.isRanked) {
      setState(() => _eloLoading = false);
      return;
    }
    // winner vide => match NUL : on appelle quand même endMatch (E3). Le
    // serveur est autoritaire, applique l'ELO de nul aux deux joueurs et
    // écrit l'historique (avant, le nul n'était jamais réglé).
    final winnerUid = widget.session.winner ?? '';
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

      // Pseudo adverse pour le texte de partage (déjà streamé par le banner).
      final opponentUid = _opponentUid();
      final opponentProfile = opponentUid == null
          ? null
          : ref.read(playerProfileProvider(opponentUid)).valueOrNull;
      final opponentName =
          (opponentProfile?.displayName?.isNotEmpty ?? false)
              ? opponentProfile!.displayName!
              : 'un adversaire';

      final delta = _eloDelta?.delta;
      final altitudeText =
          delta != null ? '${delta >= 0 ? '+' : ''}${delta}m' : '';
      final shareText = altitudeText.isNotEmpty
          ? "J'ai affronté $opponentName et gravi $altitudeText d'altitude sur Kilimandjaro Sagesse Ivoirienne !\nDéfie-moi : $deepLink"
          : "J'ai affronté $opponentName sur Kilimandjaro Sagesse Ivoirienne !\nDéfi : $deepLink";

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
    // 3 issues : nul (winner null), victoire, défaite.
    final isDraw = widget.session.winner == null;
    final won = widget.session.winner == myUid;

    // Bordure sémantique du héros (maquette `.pp.win` / `.pp.lose`).
    final heroBorder = isDraw
        ? AppColors.orJour.withValues(alpha: 0.4)
        : won
            ? AppColors.vertClair.withValues(alpha: 0.4)
            : AppColors.error.withValues(alpha: 0.4);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: RepaintBoundary(
                  key: _repaintKey,
                  child: ColoredBox(
                    color: AppColors.surface,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 8),

                          // Héros « carte » façon maquette : titre, avatars,
                          // scorebadge et altitude regroupés dans une carte
                          // Vert Nuit bordée sémantiquement.
                          Container(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: heroBorder),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  blurRadius: 60,
                                  offset: const Offset(0, 24),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isDraw)
                                  const Icon(
                                    Icons.handshake,
                                    size: 80,
                                    color: AppColors.orJour,
                                  )
                                else if (won)
                                  Image.asset(
                                    AppAssets.duelTrophy,
                                    width: 80,
                                    height: 80,
                                  )
                                else
                                  const Icon(
                                    Icons.terrain,
                                    size: 80,
                                    color: AppColors.error,
                                  ),
                                const SizedBox(height: 10),
                                // Eyebrow MATCH NUL / VICTOIRE / DÉFAITE.
                                Text(
                                  isDraw
                                      ? 'MATCH NUL'
                                      : won
                                          ? 'VICTOIRE'
                                          : 'DÉFAITE',
                                  style: AppTypography.bebas(
                                    size: 30,
                                    color: isDraw
                                        ? AppColors.orJour
                                        : won
                                            ? AppColors.vertClair
                                            : AppColors.error,
                                  ).copyWith(letterSpacing: 2),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isDraw
                                      ? 'Égalité — personne ne cède le sommet.'
                                      : won
                                          ? 'Tu as été le plus fort !'
                                          : 'Ton adversaire a été plus fort.',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.crimson(
                                    size: 14,
                                    color: AppColors.texteSecondaire,
                                    style: FontStyle.italic,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _PlayerVsBanner(
                                  selfUid: myUid,
                                  opponentUid: opponent?.uid ?? '',
                                  won: won,
                                  isDraw: isDraw,
                                ),
                                const SizedBox(height: 16),
                                Semantics(
                                  label:
                                      'Score final : Toi $selfScore, adversaire $opponentScore',
                                  child: _ScoreBadgePill(
                                    selfScore: selfScore,
                                    opponentScore: opponentScore,
                                  ),
                                ),
                                if (widget.session.isRanked) ...[
                                  const SizedBox(height: 14),
                                  _EloSection(
                                    loading: _eloLoading,
                                    delta: _eloDelta,
                                    won: won,
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // Détail des 3 manches (hors carte héros).
                          const SizedBox(height: 20),
                          _RoundsBreakdown(
                            session: widget.session,
                            selfUid: myUid,
                          ),

                          // Upsell : packs croisés en duel et non possédés.
                          _PackUpsellSection(session: widget.session),

                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // CTAs.
              const SizedBox(height: 12),
              AppButton(
                label: 'RETOUR AU HUB',
                onPressed: () => context.go(AppRoutes.hub),
                fullWidth: true,
              ),
              if (widget.session.isRanked) ...[
                const SizedBox(height: 10),
                DashedButton(
                  label: 'REVANCHE',
                  onTap: _onRematch,
                  borderColor: AppColors.hairline,
                  textColor: AppColors.textePrimaire,
                  leading: const Icon(
                    Icons.replay,
                    color: AppColors.textePrimaire,
                    size: 18,
                  ),
                ),
                const SizedBox(height: 10),
                DashedButton(
                  label: 'PARTAGER LE DÉFI',
                  onTap: _shareLoading ? null : _onShare,
                  borderColor: AppColors.hairline,
                  textColor: AppColors.texteSecondaire,
                  leading: _shareLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: AppColors.texteSecondaire,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.share,
                          color: AppColors.texteSecondaire,
                          size: 18,
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

/// Pastille de score compacte « 2 — 1 » (maquette `.scorebadge`).
class _ScoreBadgePill extends StatelessWidget {
  const _ScoreBadgePill({
    required this.selfScore,
    required this.opponentScore,
  });

  final int selfScore;
  final int opponentScore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        '$selfScore — $opponentScore',
        style: AppTypography.displaySm.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bandeau VS — avatars + pseudos des 2 joueurs en haut du récap
// ---------------------------------------------------------------------------

class _PlayerVsBanner extends ConsumerWidget {
  const _PlayerVsBanner({
    required this.selfUid,
    required this.opponentUid,
    required this.won,
    this.isDraw = false,
  });

  final String selfUid;
  final String opponentUid;
  final bool won;
  final bool isDraw;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfProfile = selfUid.isEmpty
        ? null
        : ref.watch(playerProfileProvider(selfUid)).valueOrNull;
    final opponentProfile = opponentUid.isEmpty
        ? null
        : ref.watch(playerProfileProvider(opponentUid)).valueOrNull;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: _PlayerVsSide(
            uid: selfUid,
            profile: selfProfile,
            fallbackLabel: 'Toi',
            highlighted: !isDraw && won,
            alignEnd: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.orJour.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.orJour.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              'VS',
              style: AppTypography.bebas(
                color: AppColors.orJour,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        Expanded(
          child: _PlayerVsSide(
            uid: opponentUid,
            profile: opponentProfile,
            fallbackLabel: 'Adversaire',
            highlighted: !isDraw && !won,
            alignEnd: false,
          ),
        ),
      ],
    );
  }
}

class _PlayerVsSide extends StatelessWidget {
  const _PlayerVsSide({
    required this.uid,
    required this.profile,
    required this.fallbackLabel,
    required this.highlighted,
    required this.alignEnd,
  });

  final String uid;
  final PlayerProfile? profile;
  final String fallbackLabel;
  final bool highlighted;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final hasName = profile?.displayName?.isNotEmpty ?? false;
    final label = hasName ? profile!.displayName! : fallbackLabel;
    final color =
        highlighted ? AppColors.orJour : AppColors.textePrimaire;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        _ResultAvatar(
          uid: uid,
          profile: profile,
          highlighted: highlighted,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: AppTypography.headingSm.copyWith(color: color),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        ),
      ],
    );
  }
}

class _ResultAvatar extends StatelessWidget {
  const _ResultAvatar({
    required this.uid,
    required this.profile,
    required this.highlighted,
  });

  final String uid;
  final PlayerProfile? profile;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final avatar = AvatarCatalog.byId(profile?.avatarId);
    final name = profile?.displayName;
    final initialSource = (name?.isNotEmpty ?? false)
        ? name!
        : (uid.isEmpty ? '?' : uid);
    final initial = initialSource.substring(0, 1).toUpperCase();
    final borderColor =
        highlighted ? AppColors.orJour : AppColors.texteSecondaire;

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceContainer,
        border: Border.all(
          color: borderColor.withValues(alpha: highlighted ? 0.9 : 0.55),
          width: highlighted ? 2.2 : 1.6,
        ),
        boxShadow: highlighted
            ? <BoxShadow>[
                BoxShadow(
                  color: AppColors.orJour.withValues(alpha: 0.4),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      clipBehavior: avatar != null ? Clip.antiAlias : Clip.none,
      child: avatar != null
          ? SvgPicture.asset(avatar.assetPath, fit: BoxFit.cover)
          : Center(
              child: Text(
                initial,
                style: AppTypography.bebas(
                  size: 24,
                  color: borderColor,
                ),
              ),
            ),
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

/// Upsell de fin de duel : agrège les packs **croisés** dans les manches
/// (dérivés des ids de devinette), filtre ceux **non possédés**, présents et
/// **achetables** dans le catalogue, et propose de les débloquer. Les samples
/// de fallback et le contenu gratuit ne déclenchent jamais d'upsell.
///
/// Réutilise [UnlockPackDialog] (validé serveur via le wallet). Conforme à la
/// règle « pas de pub pendant un duel » : c'est post-duel et c'est un achat.
class _PackUpsellSection extends ConsumerWidget {
  const _PackUpsellSection({required this.session});

  final DuelSession session;

  int _cost(Pack p) => p.unlockCostCauris ?? p.priceCauris;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Packs distincts croisés dans le duel (ordre de première apparition).
    final encountered = <String>{};
    for (final round in session.rounds) {
      final packId = packIdFromDevinetteId(round.devinetteId);
      if (packId != null) encountered.add(packId);
    }
    if (encountered.isEmpty) return const SizedBox.shrink();

    final owned = ref.watch(ownedPacksProvider);
    final catalog = ref.watch(packCatalogProvider).maybeWhen(
          data: (c) => c,
          orElse: () => const <Pack>[],
        );
    if (catalog.isEmpty) return const SizedBox.shrink();

    final upsellPacks = <Pack>[
      for (final p in catalog)
        if (encountered.contains(p.id) &&
            !owned.contains(p.id) &&
            p.visible &&
            _cost(p) > 0)
          p,
    ];
    if (upsellPacks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          'DÉBLOQUE CES PACKS',
          style: AppTypography.headingSm.copyWith(
            color: AppColors.texteSecondaire,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        for (final pack in upsellPacks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _UpsellCard(pack: pack, cost: _cost(pack)),
          ),
      ],
    );
  }
}

class _UpsellCard extends StatelessWidget {
  const _UpsellCard({required this.pack, required this.cost});

  final Pack pack;
  final int cost;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => UnlockPackDialog.show(context, pack: pack),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.orJour.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              PackIcon(pack: pack, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tu as croisé ${pack.displayName}',
                      style: AppTypography.headingSm,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Débloque-le pour le gravir en solo',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.texteTertiaire,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.orJour.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.orJour.withValues(alpha: 0.55),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$cost',
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.orJour),
                    ),
                    const SizedBox(width: 4),
                    const CaurisIcon(size: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final winnerUid = _roundWinnerUid();
    final selfWon = winnerUid == selfUid;
    final draw = winnerUid == null;

    // Provenance du pack — dérivée de l'id de devinette (`<packId>_<NNN>`),
    // résolue contre le catalogue chargé. Affichée après la réponse (post-
    // manche), jamais pendant la résolution (anti-spoiler).
    final devinetteId = roundData?.devinetteId;
    final packId =
        devinetteId == null ? null : packIdFromDevinetteId(devinetteId);
    final pack = packId == null
        ? null
        : ref.watch(packCatalogProvider).maybeWhen(
              data: (catalog) {
                for (final p in catalog) {
                  if (p.id == packId) return p;
                }
                return null;
              },
              orElse: () => null,
            );

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
            if (pack != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  PackIcon(pack: pack, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Devinette du pack ${pack.displayName}',
                      style: AppTypography.labelXs.copyWith(
                        color: AppColors.texteTertiaire,
                      ),
                    ),
                  ),
                ],
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
    final color = d >= 0 ? AppColors.vertClair : AppColors.error;

    // Maquette `.expl` : altitude gagnée en gras coloré + nouvelle altitude,
    // texte simple (pas de cartouche) puisque déjà dans la carte héros.
    return Column(
      children: [
        Text(
          "$sign$d m d'altitude",
          textAlign: TextAlign.center,
          style: AppTypography.bodyMd.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Nouvelle altitude : ${delta!.newElo} m',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMd.copyWith(
            fontSize: 13,
            color: AppColors.texteSecondaire,
          ),
        ),
      ],
    );
  }
}
