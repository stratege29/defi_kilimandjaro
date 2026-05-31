import 'dart:async';

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/presentation/onboarding/onboarding_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran 01 — Splash Screen, sobre.
///
/// Ciel en dégradé (savane → forêt → indigo d'altitude), logo "K", kicker
/// « Défi » et titre KILIMANDJARO centrés, avec un point or pulsant comme
/// indicateur de chargement.
///
/// Auto-transition après 2.5s vers l'onboarding (1er lancement) ou le hub.
class SplashView extends ConsumerStatefulWidget {
  const SplashView({super.key});

  @override
  ConsumerState<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends ConsumerState<SplashView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _navTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      final prefs = ref.read(sharedPreferencesProvider);
      final destination = isOnboardingSeen(prefs)
          ? AppRoutes.home
          : AppRoutes.onboarding;
      context.go(destination);
    });
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        // Ciel de l'ascension : savane chaude en bas → indigo d'altitude.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              AppColors.savanneOcre,
              AppColors.vertForet,
              AppColors.info,
              AppColors.infoSoft,
            ],
            stops: [0.0, 0.42, 0.78, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Logo + kicker « Défi » + titre, centrés.
              Align(
                alignment: const Alignment(0, -0.08),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      AppAssets.logoK,
                      width: 128,
                      height: 128,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Défi',
                      style: AppTypography.playfair(
                        size: 22,
                        color: AppColors.orJour,
                        style: FontStyle.italic,
                      ).copyWith(shadows: _textShadow),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'KILIMANDJARO',
                      style: AppTypography.logoTitle.copyWith(
                        shadows: _textShadow,
                      ),
                    ),
                  ],
                ),
              ),
              // Indicateur de chargement pulsant (or).
              Align(
                alignment: const Alignment(0, 0.92),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.7, end: 1.15).animate(
                    CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
                  ),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppColors.orJour,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const List<Shadow> _textShadow = [
    Shadow(color: AppColors.surface, blurRadius: 8),
  ];
}
