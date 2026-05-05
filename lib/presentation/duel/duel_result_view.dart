import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Résultat d'un duel — gagnant / perdant + résumé.
class DuelResultView extends ConsumerWidget {
  const DuelResultView({required this.session, super.key});

  final DuelSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfUid = ref.read(firebaseAuthProvider).currentUser?.uid ?? '';
    final won = session.winner == selfUid;

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Text(
                won ? '🏆' : '💪',
                style: const TextStyle(fontSize: 80),
              ),
              const SizedBox(height: 16),
              Text(
                won ? 'VICTOIRE' : 'DÉFAITE',
                style: AppTypography.bebas(
                  size: 36,
                  color: won ? AppColors.vertClair : AppColors.rouge,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                won
                    ? 'Tu as été le plus rapide !'
                    : 'Ton adversaire a été plus rapide.',
                textAlign: TextAlign.center,
                style: AppTypography.crimson(
                  size: 14,
                  color: AppColors.ivoire.withValues(alpha: 0.85),
                  style: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.boisFonce.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.orSoleil.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'Mot : ${session.answer}',
                      style: AppTypography.bebas(
                        size: 24,
                        color: AppColors.orSoleil,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      session.explanation,
                      textAlign: TextAlign.center,
                      style: AppTypography.crimson(size: 13),
                    ),
                    if (session.proverb.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        '« ${session.proverb} »',
                        textAlign: TextAlign.center,
                        style: AppTypography.crimson(
                          size: 14,
                          color: AppColors.orSoleil,
                          style: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go(AppRoutes.hub),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.vertClair,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'RETOUR AU HUB',
                    style: AppTypography.bebas(
                      size: 18,
                      color: AppColors.vertForet,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
