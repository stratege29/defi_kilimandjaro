import 'dart:async';

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// CTA sticky « GRIMPER » de l'accueil — bouton unique dominant façon
/// chess.com « Play ». Épinglé au-dessus de la bottom nav ; un tap pousse la
/// page plein écran `GrimperView` (`/grimper`) qui propose les modes de jeu.
///
/// Kili (pose « peek », tronquée à mi-corps) grimpe par-dessus le bord
/// supérieur du bouton — clin d'œil littéral au mot GRIMPER.
class GrimperCta extends StatelessWidget {
  const GrimperCta({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          AppButton(
            label: 'GRIMPER',
            icon: Icons.terrain,
            fullWidth: true,
            onPressed: () => unawaited(context.push<void>(AppRoutes.grimper)),
          ),
          // `IgnorePointer` : purement décoratif, ne doit pas voler le tap
          // destiné au bouton en dessous. Variante `kiliPeekGold` : la rampe
          // illustrée est recolorée en or pour se fondre avec le bouton (la
          // version grise d'origine créait une rupture de teinte visible).
          // `top: -37` calé pixel-perfect : la bordure de la rampe (dans le
          // PNG source) coïncide exactement avec le bord supérieur réel du
          // bouton.
          Positioned(
            top: -37,
            child: IgnorePointer(
              child: Image.asset(
                AppAssets.kiliPeekGold,
                width: 84,
                height: 43,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
