import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/news_carousel.dart';
import 'package:defi_kilimandjaro/presentation/home/widgets/packs_section.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Écran « Découvrir » — packs de contenu, promos & actualités.
///
/// Relocalise hors de l'accueil les surfaces de découverte/monétisation
/// (cf. « retenue radicale » : l'accueil reste centré sur l'ascension).
/// Accessible via l'icône Boutique du header d'accueil. Distinct de
/// l'écran cauris (`AppRoutes.shop`), qui gère la recharge de monnaie.
class DiscoverView extends StatelessWidget {
  const DiscoverView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          color: AppColors.orJour,
          onPressed: () => context.pop(),
        ),
        title: Text('Découvrir', style: AppTypography.headingLg),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          children: const [
            PacksSection(),
            AppSpacing.gapLg,
            NewsCarousel(),
          ],
        ),
      ),
    );
  }
}
