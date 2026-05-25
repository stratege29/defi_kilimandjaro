import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/section_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Carrousel horizontal des 3 modes défi disponibles.
class DuelsCarousel extends ConsumerWidget {
  const DuelsCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(playerProfileStreamProvider);
    final elo = profileAsync.value?.elo ?? 1000;

    final cards = <_DuelCardData>[
      _DuelCardData(
        icon: Icons.qr_code_2,
        label: 'DÉFIER UN AMI',
        subtitle: 'Duel temps réel via QR',
        color: AppColors.vertClair,
        onTap: () => context.push(AppRoutes.duel),
      ),
      _DuelCardData(
        icon: Icons.public,
        label: 'DÉFI EN LIGNE',
        subtitle: 'ELO $elo m · matchmaking',
        color: AppColors.orSoleil,
        onTap: () => context.push(AppRoutes.duelLobby),
      ),
      _DuelCardData(
        icon: Icons.replay,
        label: 'CLASSEMENT',
        subtitle: 'Top grimpeurs de la semaine',
        color: AppColors.bois,
        onTap: () => context.push(AppRoutes.leaderboard),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'TES DÉFIS'),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _DuelCard(data: cards[i]),
          ),
        ),
      ],
    );
  }
}

class _DuelCardData {
  const _DuelCardData({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
}

class _DuelCard extends StatelessWidget {
  const _DuelCard({required this.data});

  final _DuelCardData data;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: data.onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: data.color.withValues(alpha: 0.7), width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(data.icon, color: data.color, size: 28),
                const Spacer(),
                Text(
                  data.label,
                  style: AppTypography.bebas(size: 15, color: data.color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  data.subtitle,
                  style: AppTypography.crimson(
                    size: 12,
                    color: AppColors.texteSecondaire,
                    style: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
