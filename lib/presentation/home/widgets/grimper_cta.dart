import 'dart:async';

import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// CTA sticky « GRIMPER » de l'accueil — bouton unique dominant façon
/// chess.com « Play ». Épinglé au-dessus de la bottom nav ; un tap pousse la
/// page plein écran `GrimperView` (`/grimper`) qui propose les modes de jeu.
class GrimperCta extends StatelessWidget {
  const GrimperCta({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: AppButton(
        label: 'GRIMPER',
        icon: Icons.terrain,
        fullWidth: true,
        onPressed: () => unawaited(context.push<void>(AppRoutes.grimper)),
      ),
    );
  }
}
