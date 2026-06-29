import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/presentation/duel/lobby_view.dart';
import 'package:defi_kilimandjaro/presentation/hub/widgets/bottom_nav_bar.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran 02 — Hub Défi.
///
/// Point d'entrée des modes compétitifs :
/// - Défier un ami (QR code, temps réel) — actif.
/// - Défi en ligne ELO (matchmaking aléatoire) — bientôt.
///
/// La progression solo est désormais regroupée dans l'onglet « Sommets »
/// (cf. `mountain_list_view.dart`).
class HubView extends ConsumerStatefulWidget {
  const HubView({super.key});

  @override
  ConsumerState<HubView> createState() => _HubViewState();
}

class _HubViewState extends ConsumerState<HubView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            const _IntroBlock(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _DuelButton(
                    icon: Icons.qr_code_2,
                    label: 'DÉFIER UN AMI',
                    description: 'Duel temps réel via QR code',
                    accent: AppColors.vertClair,
                    onTap: () => context.push(AppRoutes.duel),
                  ),
                  const SizedBox(height: 14),
                  // Hero tag sur ce bouton : la couleur orSoleil reste
                  // visuellement continue pendant la navigation vers le lobby.
                  Hero(
                    tag: 'hub-duel-en-ligne',
                    child: _DuelButton(
                      icon: Icons.public,
                      label: 'DÉFI EN LIGNE',
                      description: 'Matchmaking ELO — trouve ton rival',
                      accent: AppColors.orSoleil,
                      onTap: () => context.push(AppRoutes.duelLobby),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: NavTab.defi,
        onTabSelected: (t) {
          switch (t) {
            case NavTab.accueil:
              context.go(AppRoutes.home);
            case NavTab.defi:
              break;
            case NavTab.sommets:
              context.go(AppRoutes.mountains);
            case NavTab.packs:
              context.go(AppRoutes.myPacks);
            case NavTab.profil:
              context.go(AppRoutes.profile);
          }
        },
      ),
    );
  }

  // _showSoonSnack supprimé — le bouton DÉFI EN LIGNE est désormais actif
  // et navigue vers AppRoutes.duelLobby (Phase 6).
}

class _IntroBlock extends StatelessWidget {
  const _IntroBlock();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DÉFI 1V1',
            style: AppTypography.bebas(size: 26, color: AppColors.orSoleil),
          ),
          const SizedBox(height: 4),
          Text(
            'Mesure-toi à un ami ou à la communauté.',
            style: AppTypography.crimson(
              size: 13,
              color: AppColors.texteSecondaire,
              style: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _DuelButton extends StatelessWidget {
  const _DuelButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.7), width: 2),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: AppTypography.bebas(size: 18)),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: AppTypography.crimson(
                        size: 12,
                        color: AppColors.texteSecondaire,
                        style: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Defense au cold start : si playerProgressProvider throw (override
    // sharedPreferences pas encore applique, ou autre), on tombe sur des
    // valeurs initiales plutot que de propager l'exception et faire crasher
    // tout le HubView (= ecran blanc). Idem pour le profil ELO.
    var totalLevels = 0;
    var cauris = 0;
    try {
      final progress = ref.watch(playerProgressProvider);
      totalLevels = progress.totalLevelsCompleted;
      cauris = progress.cauris;
    } on Object {
      // Valeurs initiales conservees.
    }
    final levelTier = 1 + (totalLevels ~/ 10);

    var myElo = 1000;
    try {
      myElo = ref.watch(playerProfileStreamProvider).value?.elo ?? 1000;
    } on Object {
      // Fallback altitude 1000m conserve.
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.orSoleil.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          // Le titre rétrécit sur écrans étroits (iPhone normal ~393pt)
          // pour laisser la place aux 3 chips à droite. FittedBox
          // garantit qu'on ne dépasse jamais en largeur, tout en
          // préservant la taille naturelle sur écrans larges.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'KILIMANDJARO',
                style: AppTypography.bebas(size: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _Chip(
            iconWidget: const CaurisIcon(size: 16),
            value: '$cauris',
            trailingPlus: true,
            onTap: () => context.push(AppRoutes.shop),
          ),
          const SizedBox(width: 8),
          _Chip(icon: '⭐', value: 'N$levelTier'),
          const SizedBox(width: 8),
          // Hero partagé avec LobbyView et ProfileView.
          Hero(
            tag: kAltitudeHeroTag,
            child: _AltitudeHeroChip(elo: myElo),
          ),
        ],
      ),
    );
  }
}

/// Chip altitude partagée via Hero entre Hub, Lobby et Profile.
class _AltitudeHeroChip extends StatelessWidget {
  const _AltitudeHeroChip({required this.elo});
  final int elo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orSoleil.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.terrain, size: 14, color: AppColors.orSoleil),
          const SizedBox(width: 4),
          Text(
            '$elo m',
            style: AppTypography.bebas(size: 14, color: AppColors.orSoleil),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.value,
    this.icon,
    this.iconWidget,
    this.trailingPlus = false,
    this.onTap,
  }) : assert(
         icon != null || iconWidget != null,
         'Provide either icon (emoji) or iconWidget',
       );
  final String? icon;
  final Widget? iconWidget;
  final String value;
  final bool trailingPlus;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orSoleil.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget ?? Text(icon!, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            value,
            style: AppTypography.bebas(size: 14, color: AppColors.orSoleil),
          ),
          if (trailingPlus) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.add_circle,
              size: 16,
              color: AppColors.orSoleil.withValues(alpha: 0.85),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: body,
      ),
    );
  }
}
