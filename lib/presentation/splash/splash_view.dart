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
/// Fond uni « Vert Nuit » (couleur du thème), logo "K", kicker « Défi » et
/// titre KILIMANDJARO, avec un point or pulsant comme indicateur de
/// chargement.
///
/// IMPORTANT — continuité avec le splash natif : le logo est posé au centre
/// EXACT de l'écran (hors SafeArea) à 128×128, soit la position et la taille
/// du splash natif (cf. `flutter_native_splash` dans pubspec.yaml, même fond
/// #0C1712). Sans ça le logo disparaissait avec le splash natif puis
/// réapparaissait ailleurs : l'utilisateur voyait deux fois le logo. Le titre
/// et le point de chargement viennent en fondu SOUS le logo, qui ne bouge
/// jamais. Toute modif de taille/position ici doit être répercutée sur la
/// config native (et inversement).
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
      backgroundColor: AppColors.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Logo calé sur le splash natif : centre exact de l'écran, 128×128.
          // Le titre est positionné SOUS lui (Stack, pas Column) pour que
          // l'arrivée du texte ne décale pas le logo.
          Center(
            child: SizedBox(
              width: double.infinity,
              height: _logoSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Image.asset(
                      AppAssets.logoK,
                      width: _logoSize,
                      height: _logoSize,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    top: _logoSize + 10,
                    left: 0,
                    right: 0,
                    child: _FadeIn(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Défi',
                            style: AppTypography.playfair(
                              size: 22,
                              style: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'KILIMANDJARO',
                            style: AppTypography.logoTitle,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Indicateur de chargement pulsant (or).
          SafeArea(
            child: Align(
              alignment: const Alignment(0, 0.92),
              child: _FadeIn(
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.7, end: 1.15).animate(
                    CurvedAnimation(
                      parent: _pulseCtrl,
                      curve: Curves.easeInOut,
                    ),
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
            ),
          ),
        ],
      ),
    );
  }
}

/// Taille du logo — doit rester identique à celle générée pour le splash
/// natif (128 pt : `splash.png` 128/192/256/384/512 px selon la densité,
/// `LaunchImage@1x/2x/3x` 128/256/384 px).
const double _logoSize = 128;

/// Fondu d'apparition one-shot, utilisé pour tout ce qui n'existe pas sur le
/// splash natif (titre, indicateur). Le logo, lui, est déjà à l'écran : il ne
/// doit ni réapparaître ni bouger.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      builder: (_, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }
}
