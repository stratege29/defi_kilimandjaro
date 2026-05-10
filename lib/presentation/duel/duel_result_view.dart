import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/matchmaking_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';

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
              const SizedBox(height: 20),
              if (won)
                Image.asset(AppAssets.duelTrophy, width: 120, height: 120)
              else
                Image.asset(AppAssets.iconStreak, width: 120, height: 120),
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
              const Spacer(),
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
