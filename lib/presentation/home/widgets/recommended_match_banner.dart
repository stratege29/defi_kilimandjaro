import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Recommandation de match (défi ami reçu, adversaire ELO match…).
///
/// MVP : stub — le provider retourne toujours `null` tant que la logique
/// FCM/matchmaking n'est pas câblée. Le widget rend alors `SizedBox.shrink()`
/// pour ne pas prendre de place. La structure est prête pour Phase 2 où on
/// listera la file de défis amis reçus (Firestore + FCM unread).
class RecommendedMatchBanner extends ConsumerWidget {
  const RecommendedMatchBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reco = ref.watch(recommendedMatchProvider);
    if (reco == null) return const SizedBox.shrink();
    return _Banner(reco: reco);
  }
}

/// Données affichées dans le bandeau (extensible Phase 2 : avatar, ELO…).
class RecommendedMatch {
  const RecommendedMatch({
    required this.opponentLabel,
    required this.subtitle,
    required this.onAccept,
    required this.onDismiss,
  });

  final String opponentLabel;
  final String subtitle;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;
}

/// Stub provider — retourne toujours `null` pour l'instant.
///
/// Phase 2 : alimenter via défis amis reçus (DuelRepository queue
/// `duels/pending/{uid}`) + FCM unread notifications.
final recommendedMatchProvider = Provider<RecommendedMatch?>((_) => null);

class _Banner extends StatelessWidget {
  const _Banner({required this.reco});

  final RecommendedMatch reco;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.vertClair.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.vertClair.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: AppColors.vertClair, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reco.opponentLabel,
                  style: AppTypography.bebas(
                    size: 14,
                    color: AppColors.vertClair,
                  ),
                ),
                Text(
                  reco.subtitle,
                  style: AppTypography.crimson(
                    size: 12,
                    color: AppColors.texteSecondaire,
                    style: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: reco.onAccept,
            child: Text(
              'ACCEPTER',
              style: AppTypography.bebas(
                size: 13,
                color: AppColors.vertClair,
              ),
            ),
          ),
          IconButton(
            onPressed: reco.onDismiss,
            icon: const Icon(
              Icons.close,
              size: 18,
              color: AppColors.texteTertiaire,
            ),
          ),
        ],
      ),
    );
  }
}
