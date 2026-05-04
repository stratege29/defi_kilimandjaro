import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/datasources/mock_worlds.dart';
import 'package:defi_kilimandjaro/data/repositories/devinette_repository_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/world.dart';
import 'package:defi_kilimandjaro/presentation/hub/widgets/bottom_nav_bar.dart';
import 'package:defi_kilimandjaro/presentation/hub/widgets/world_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran 02 — Hub des Mondes (cf. maquette p.4).
///
/// Sélection du monde thématique. Vue d'ensemble de la progression par monde.
/// - Header : Logo + coins + niveau joueur
/// - 4 cartes mondes verticales (défilable)
/// - Bottom nav : Jouer / Afrique / Profil
class HubView extends ConsumerStatefulWidget {
  const HubView({super.key});

  @override
  ConsumerState<HubView> createState() => _HubViewState();
}

class _HubViewState extends ConsumerState<HubView> {
  NavTab _currentTab = NavTab.jouer;

  Future<void> _onWorldTap(BuildContext context, World world) async {
    if (!world.unlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Coins requis : ${world.unlockCost}',
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.boisFonce,
        ),
      );
      return;
    }

    try {
      final repo = ref.read(devinetteRepositoryProvider);
      final devinette = await repo.randomFromWorld(world.id);
      if (!context.mounted) return;
      await context.push<void>(AppRoutes.game, extra: devinette);
    } on Exception catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Aucune devinette disponible pour ${world.name}',
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.rouge,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                itemCount: mockWorlds.length,
                itemBuilder: (_, i) {
                  final world = mockWorlds[i];
                  return WorldCard(
                    world: world,
                    onTap: () => _onWorldTap(context, world),
                    onLongPress: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Aperçu ${world.name} (TODO)',
                            style: AppTypography.bebas(),
                          ),
                          backgroundColor: AppColors.boisFonce,
                          duration: const Duration(milliseconds: 800),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: _currentTab,
        onTabSelected: (t) {
          switch (t) {
            case NavTab.jouer:
              setState(() => _currentTab = t);
            case NavTab.afrique:
              context.go(AppRoutes.mountains);
            case NavTab.profil:
              setState(() => _currentTab = t);
              // TODO(phase-3): context.go('/profile');
          }
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.orSoleil.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Logo + nom
          Text('KILIMANDJARO', style: AppTypography.bebas(size: 18)),
          const Spacer(),
          // Coins
          const _Chip(icon: '🪙', value: '120'),
          const SizedBox(width: 8),
          // Niveau joueur
          const _Chip(icon: '⭐', value: 'N1'),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.value});
  final String icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.orSoleil.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            value,
            style: AppTypography.bebas(
              size: 14,
              color: AppColors.orSoleil,
            ),
          ),
        ],
      ),
    );
  }
}
