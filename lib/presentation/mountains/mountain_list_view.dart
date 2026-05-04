import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/devinette_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/presentation/hub/widgets/bottom_nav_bar.dart';
import 'package:defi_kilimandjaro/presentation/mountains/widgets/mountain_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Liste des montagnes d'Afrique triées par altitude croissante.
///
/// Pivot Phase 2.1 — remplace la maquette p.8 (Carte d'Afrique 54 pays)
/// par une progression d'ascension : du Red Rocks (53 m, Gambie) au
/// Kilimandjaro (5 895 m, Tanzanie).
class MountainListView extends ConsumerStatefulWidget {
  const MountainListView({super.key});

  @override
  ConsumerState<MountainListView> createState() => _MountainListViewState();
}

class _MountainListViewState extends ConsumerState<MountainListView> {
  Future<void> _onMountainTap(BuildContext context, Mountain m) async {
    if (!m.unlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bientôt disponible — termine ${m.altitude}m',
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.boisFonce,
          duration: const Duration(milliseconds: 1500),
        ),
      );
      return;
    }

    try {
      // Phase 2.2 stub : pour l'instant on lance une devinette aléatoire
      // du monde "Village des Or" (le seul peuplé avec 30 entrées).
      // En Phase 2.3 on liera devinettes par tags pays / culture régionale.
      final repo = ref.read(devinetteRepositoryProvider);
      final devinette = await repo.randomFromWorld('village_des_or');
      if (!context.mounted) return;
      await context.push<void>(AppRoutes.game, extra: devinette);
    } on Exception catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erreur de chargement',
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.rouge,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncMountains = ref.watch(mountainsProvider);

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: asyncMountains.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.orSoleil,
                  ),
                ),
                error: (_, __) => Center(
                  child: Text(
                    'Impossible de charger les montagnes',
                    style: AppTypography.crimson(),
                  ),
                ),
                data: (mountains) => ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 24),
                  itemCount: mountains.length,
                  itemBuilder: (_, i) {
                    final m = mountains[i];
                    return MountainCard(
                      mountain: m,
                      rank: i + 1,
                      onTap: () => _onMountainTap(context, m),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: NavTab.afrique,
        onTabSelected: (t) {
          switch (t) {
            case NavTab.jouer:
              context.go(AppRoutes.hub);
            case NavTab.afrique:
              break;
            case NavTab.profil:
              // TODO(phase-3): /profile
              break;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏔️', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                "MONTAGNES D'AFRIQUE",
                style: AppTypography.bebas(size: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Du plus modeste sommet au toit du continent',
            style: AppTypography.crimson(
              size: 13,
              color: AppColors.ivoire.withValues(alpha: 0.7),
              style: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
