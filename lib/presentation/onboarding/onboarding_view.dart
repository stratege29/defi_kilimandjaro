import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String onboardingSeenKey = 'onboarding_seen';

bool isOnboardingSeen(SharedPreferences prefs) =>
    prefs.getBool(onboardingSeenKey) ?? false;

Future<void> markOnboardingSeen(SharedPreferences prefs) async {
  await prefs.setBool(onboardingSeenKey, true);
}

/// 3 écrans skippables au premier lancement.
///
/// Étape 1 : drag des lettres (Kili peek)
/// Étape 2 : ascension des montagnes (Kili point)
/// Étape 3 : défi entre amis (Kili cheer)
class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key});

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  final PageController _pageCtrl = PageController();
  int _index = 0;

  static const _steps = <_OnboardingStep>[
    _OnboardingStep(
      titleKey: 'onboarding.step1.title',
      bodyKey: 'onboarding.step1.body',
      defaultTitle: 'Bienvenue, voyageur',
      defaultBody:
          'Glisse ton doigt sur les lettres pour former le mot caché par le griot.',
      mascotAsset: AppAssets.kiliPeek,
    ),
    _OnboardingStep(
      titleKey: 'onboarding.step2.title',
      bodyKey: 'onboarding.step2.body',
      defaultTitle: "Gravis l'Afrique",
      defaultBody:
          "51 sommets t'attendent, du Red Rocks de Gambie au toit du Kilimandjaro.",
      mascotAsset: AppAssets.kiliPoint,
    ),
    _OnboardingStep(
      titleKey: 'onboarding.step3.title',
      bodyKey: 'onboarding.step3.body',
      defaultTitle: 'Défie un ami',
      defaultBody:
          'QR code en main, lance un duel temps réel. Le plus rapide remporte la sagesse.',
      mascotAsset: AppAssets.kiliCheer,
    ),
  ];

  Future<void> _finish() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await markOnboardingSeen(prefs);
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button top-right.
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(
                  'Passer',
                  style: AppTypography.crimson(
                    size: 14,
                    color: AppColors.texteSecondaire,
                    style: FontStyle.italic,
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _StepView(step: _steps[i]),
              ),
            ),
            _DotsRow(count: _steps.length, current: _index),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_index < _steps.length - 1) {
                      _pageCtrl.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                      );
                    } else {
                      _finish();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.vertClair,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    _index < _steps.length - 1 ? 'Suivant' : "C'EST PARTI",
                    style: AppTypography.bebas(color: AppColors.vertForet),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
          ],
        ),
      ),
    );
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.titleKey,
    required this.bodyKey,
    required this.defaultTitle,
    required this.defaultBody,
    required this.mascotAsset,
  });
  final String titleKey;
  final String bodyKey;
  final String defaultTitle;
  final String defaultBody;
  final String mascotAsset;
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step});
  final _OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(
            flex: 3,
            child: Center(
              child: Image.asset(step.mascotAsset, fit: BoxFit.contain),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Text(
                  step.defaultTitle,
                  textAlign: TextAlign.center,
                  style: AppTypography.bebas(size: 26),
                ),
                const SizedBox(height: 12),
                Text(
                  step.defaultBody,
                  textAlign: TextAlign.center,
                  style: AppTypography.crimson(
                    color: AppColors.textePrimaire,
                    style: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DotsRow extends StatelessWidget {
  const _DotsRow({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == current ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == current
                  ? AppColors.orSoleil
                  : AppColors.texteDisabled,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
