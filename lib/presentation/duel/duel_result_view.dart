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

/// Résultat d'un duel — gagnant / perdant + résumé.
///
/// Si le match était ranked ([DuelSession.isRanked] == true), appelle
/// automatiquement `endMatch` Cloud Function pour calculer et persister l'ELO.
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

  /// Clé utilisée pour capturer le widget résultat en PNG via [RepaintBoundary].
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
      final delta = await ref.read(matchmakingRepositoryProvider).endMatch(
            matchId: widget.session.matchId,
            winnerUid: winnerUid,
          );
      if (mounted) {
        setState(() {
          _eloDelta = delta;
          _eloLoading = false;
        });
      }
    } on Exception catch (e) {
      _log.e('endMatch failed', error: e);
      if (mounted) {
        setState(() => _eloLoading = false);
      }
    }
  }

  /// Détermine l'UID de l'adversaire (pour le bouton REMATCH).
  String? _opponentUid() {
    final myUid = ref.read(firebaseAuthProvider).currentUser?.uid ?? '';
    for (final uid in widget.session.players.keys) {
      if (uid != myUid) return uid;
    }
    return null;
  }

  void _onRematch() {
    final opponentUid = _opponentUid();
    // Pre-positionne les providers rematch avant de naviguer.
    // Le LobbyController detectera isRematch == true et appellera
    // requestRematch CF au lieu du matchmaking ELO standard.
    if (opponentUid != null) {
      ref.read(lobbyRematchUidProvider.notifier).state = opponentUid;
    }
    ref.read(lobbyPreviousMatchIdProvider.notifier).state =
        widget.session.matchId;
    context.go(AppRoutes.duelLobby);
  }

  /// Crée un nouveau match ouvert, capture le widget résultat en PNG,
  /// puis déclenche le share sheet natif avec texte + image.
  Future<void> _onShare() async {
    if (_shareLoading) return;
    setState(() => _shareLoading = true);

    try {
      // 1. Crée un nouveau match ouvert (le match courant est finished).
      final repo = ref.read(duelRepositoryProvider);
      final (:matchId, secret: _) = await repo.createDuel();
      final deepLink = 'kilimandjaro://duel/$matchId';

      // 2. Capture le widget résultat en PNG.
      final boundary = _repaintKey.currentContext?.findRenderObject()
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

      // 3. Construit le texte de partage.
      final delta = _eloDelta?.delta;
      final altitudeText =
          delta != null ? '${delta >= 0 ? '+' : ''}${delta}m' : '';
      final shareText = altitudeText.isNotEmpty
          ? "J'ai gravi $altitudeText d'altitude sur Kilimandjaro Sagesse Ivoirienne !\nDéfie-moi : $deepLink"
          : 'Affronte-moi sur Kilimandjaro Sagesse Ivoirienne !\nDéfi : $deepLink';

      // 4. Déclenche le share sheet natif (API share_plus v11+).
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
    final won = widget.session.winner == myUid;

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // RepaintBoundary : tout le contenu résultat capturé pour le share.
              Expanded(
                child: RepaintBoundary(
                  key: _repaintKey,
                  child: ColoredBox(
                    color: AppColors.vertForet,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        if (won)
                          Image.asset(
                            AppAssets.duelTrophy,
                            width: 120,
                            height: 120,
                          )
                        else
                          Image.asset(
                            AppAssets.iconStreak,
                            width: 120,
                            height: 120,
                          ),
                        const SizedBox(height: 16),
                        Text(
                          won ? 'VICTOIRE' : 'DÉFAITE',
                          style: AppTypography.bebas(
                            size: 36,
                            color: won ? AppColors.vertClair : AppColors.rouge,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          won
                              ? 'Tu as été le plus rapide !'
                              : 'Ton adversaire a été plus rapide.',
                          textAlign: TextAlign.center,
                          style: AppTypography.crimson(
                            size: 14,
                            color: AppColors.ivoire.withValues(alpha: 0.85),
                            style: FontStyle.italic,
                          ),
                        ),
                        // --- Section ELO (uniquement si ranked) ---
                        if (widget.session.isRanked) ...[
                          const SizedBox(height: 20),
                          _EloSection(
                            loading: _eloLoading,
                            delta: _eloDelta,
                            won: won,
                          ),
                        ],
                        const SizedBox(height: 24),
                        // --- Résumé du mot ---
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.boisFonce.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.orSoleil.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Mot : ${widget.session.answer}',
                                style: AppTypography.bebas(
                                  size: 24,
                                  color: AppColors.orSoleil,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.session.explanation,
                                textAlign: TextAlign.center,
                                style: AppTypography.crimson(size: 13),
                              ),
                              if (widget.session.proverb.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  '« ${widget.session.proverb} »',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.crimson(
                                    size: 14,
                                    color: AppColors.orSoleil,
                                    style: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
              // --- CTAs ---
              const SizedBox(height: 12),
              // CTA principal : RETOUR AU HUB
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
              // CTA secondaire : REMATCH (uniquement pour les duels ranked)
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
              ],
              // CTA tertiaire : PARTAGER LE DÉFI (ranked uniquement)
              if (widget.session.isRanked) ...[
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

/// Section altitude gagnée/perdue pour les matchs ranked.
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
          Text(
            label,
            style: AppTypography.bebas(size: 22, color: color),
          ),
          Text(
            'Nouvelle altitude : ${delta!.newElo} m',
            style: AppTypography.crimson(
              size: 13,
              color: AppColors.ivoire.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
