import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/core/utils/level_difficulty_resolver.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/services/devinette_selection_service_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';
import 'package:defi_kilimandjaro/domain/services/daily_challenge_service.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Carte « Défi du jour » — point d'entrée du daily challenge sur le Hub
/// d'Accueil. Trois états déterminés depuis `PlayerProgress` :
///
/// 1. **Disponible** (`lastDailyChallengeDate != today`) : CTA actif
///    « JOUER LE DÉFI » + caption récompense.
/// 2. **Terminé aujourd'hui** : badge ✓ + streak actuelle. Pas de retry.
/// 3. **Streak perdue** (`isStreakBroken == true`, mais pas encore joué
///    aujourd'hui) : variante "disponible" avec message « Série perdue
///    — recommence aujourd'hui ».
///
/// Au tap, pioche déterministiquement une devinette Tier 3 du pack actif
/// (seed = hash du jour) et lance `/game` en mode daily.
class DailyChallengeCard extends ConsumerWidget {
  const DailyChallengeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(playerProgressProvider);
    final now = DateTime.now();
    final playedToday = DailyChallengeService.isPlayedOn(
      progress: progress,
      date: now,
    );
    final streakBroken = DailyChallengeService.isStreakBroken(
      progress: progress,
      today: now,
    );
    final streak = progress.dailyChallengeStreak;
    // Si le joueur a joué aujourd'hui ET que son streak vient d'atteindre
    // un palier de bonus (3/7/30), on affiche un badge doré jusqu'au
    // lendemain (où le streak basculera sur 4/8/31). Pas de persistance
    // "vu/pas vu" — l'affichage suit le streak courant, ce qui reste lisible.
    final milestoneBonus =
        playedToday ? DailyChallengeService.bonusForStreak(streak) : 0;
    // Freeze appliqué aujourd'hui ? On affiche un badge cyan dédié pour
    // que le joueur voie clairement que son token l'a sauvé d'un skip.
    final freezeUsedToday = progress.lastFreezeUsedDate != null &&
        _isSameDay(progress.lastFreezeUsedDate!, now);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.bois.withValues(alpha: 0.85),
            AppColors.boisFonce.withValues(alpha: 0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.orSoleil.withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.orSoleil.withValues(alpha: 0.12),
            blurRadius: 20,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: <Widget>[
              Icon(
                playedToday
                    ? Icons.check_circle_outline
                    : Icons.calendar_today_outlined,
                size: 18,
                color: AppColors.orSoleil,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'daily.title'.tr(),
                  style: AppTypography.bebas(
                    size: 18,
                    color: AppColors.textePrimaire,
                  ),
                ),
              ),
              if (progress.freezeTokens > 0) ...<Widget>[
                Text(
                  'daily.freeze_tokens_count'.tr(
                    namedArgs: <String, String>{
                      'count': progress.freezeTokens.toString(),
                      'max': DailyChallengeService.maxFreezeTokens.toString(),
                    },
                  ),
                  style: AppTypography.crimson(
                    size: 12,
                    color: AppColors.cielHauteur,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (streak > 0)
                Text(
                  'daily.streak'.tr(
                    namedArgs: <String, String>{'count': streak.toString()},
                  ),
                  style: AppTypography.crimson(
                    size: 12,
                    color: AppColors.orSoleil,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            playedToday
                ? 'daily.cta_done'.tr()
                : (streakBroken
                    ? 'daily.streak_broken'.tr()
                    : 'daily.subtitle'.tr()),
            style: AppTypography.crimson(
              size: 13,
              color: AppColors.texteSecondaire,
              style: FontStyle.italic,
            ),
          ),
          if (milestoneBonus > 0) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    AppColors.orChaud,
                    AppColors.orSoleil,
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.orSoleil.withValues(alpha: 0.5),
                    blurRadius: 10,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Text(
                'daily.streak_bonus_banner'.tr(
                  namedArgs: <String, String>{
                    'cauris': milestoneBonus.toString(),
                    'days': streak.toString(),
                  },
                ),
                style: AppTypography.bebas(
                  size: 14,
                  color: AppColors.boisFonce,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          if (freezeUsedToday) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppColors.cielHauteur.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.cielHauteur.withValues(alpha: 0.6),
                ),
              ),
              child: Text(
                'daily.freeze_saved_banner'.tr(),
                style: AppTypography.bebas(
                  size: 13,
                  color: AppColors.cielHauteur,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (!playedToday)
            GestureDetector(
              onTap: () => _launch(context, ref),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.orSoleil,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'daily.cta_available'.tr(),
                      style: AppTypography.bebas(
                        size: 15,
                        color: AppColors.boisFonce,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'daily.reward_caption'.tr(
                        namedArgs: <String, String>{
                          'cauris': DailyChallengeService.rewardCauris
                              .toString(),
                        },
                      ),
                      style: AppTypography.crimson(
                        size: 12,
                        color: AppColors.boisFonce,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppColors.vertClair.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.vertClair.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                'daily.cta_done'.tr(),
                style: AppTypography.bebas(
                  size: 13,
                  color: AppColors.vertClair,
                ),
              ),
            ),
          // CTA achat freeze token. Toujours visible (visibilité du sink
          // économique), mais désactivé si stock max ou solde insuffisant.
          // L'UX décourage par opacité + clic qui affiche le snackbar
          // dédié plutôt que par disparition (clarté sur la mécanique).
          const SizedBox(height: 10),
          _FreezePurchaseButton(progress: progress),
        ],
      ),
    );
  }

  /// Comparaison jour calendaire local (ignore heures/min/sec).
  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _launch(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    try {
      // On utilise une montagne "virtuelle" Tier 3 (alt 2000 m, hors Rift)
      // pour calibrer la config via le resolver — garantit le bucket de
      // mot Tier 3, le timer, le multiplier cauris (peu importe pour le
      // daily mais reste cohérent) et zéro modifier exotique. La montagne
      // ne sera jamais persistée — usage purement éphémère pour la config.
      const virtualMountain = Mountain(
        id: '__daily__',
        name: 'Daily',
        countryCode: 'XX',
        countryName: 'Daily',
        flagEmoji: '★',
        altitude: 2000,
        totalLevels: 1,
      );
      final config = LevelDifficultyResolver.resolve(
        mountain: virtualMountain,
        levelIndex: 1,
      );

      // Seed déterministe : hash FNV-1a du jour (réutilise l'helper du
      // service). Tous les joueurs avec le même pack actif et la même
      // date verront la même devinette.
      final seed = _seedForDate(today);

      final progress = ref.read(playerProgressProvider);
      final devinette =
          await ref.read(devinetteSelectionServiceProvider).nextDevinette(
                mix: progress.activePackMix,
                targetDifficulty: config.difficultyTier,
                wordLengthBucket: config.wordLengthBucket,
                excludeIds: const <String>{},
                seed: seed,
              );

      if (!context.mounted) return;
      await context.push<void>(
        AppRoutes.game,
        extra: GameArgs.daily(
          devinette: devinette,
          config: config,
          date: today,
        ),
      );
    } on Exception catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'daily.pool_empty'.tr(),
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.rouge,
        ),
      );
    }
  }

  /// Hash FNV-1a 32-bit du yyyy-MM-dd → seed reproductible pour le
  /// service de sélection. Bit-identique cross-platform.
  static int _seedForDate(DateTime date) {
    final key = DailyChallengeService.dailyKeyForDate(date);
    const fnvOffset = 0x811c9dc5;
    const fnvPrime = 0x01000193;
    var hash = fnvOffset;
    for (final code in key.codeUnits) {
      hash ^= code;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash;
  }
}

/// Bouton CTA secondaire « Acheter ❄️ — N 🐚 ».
///
/// Trois états visuels :
/// - **Actif** (cauris ≥ cost && stock < max) : opacité pleine, tap
///   débite + incrémente le compteur.
/// - **Désactivé stock max** : opacité 0.4, tap → snackbar
///   `freeze_buy_full`.
/// - **Désactivé solde insuffisant** : opacité 0.4, tap → snackbar
///   `freeze_buy_insufficient`.
///
/// Découplé en widget privé pour isoler les states UI sans gonfler le
/// build de la card parente.
class _FreezePurchaseButton extends ConsumerWidget {
  const _FreezePurchaseButton({required this.progress});

  final PlayerProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final atMax =
        progress.freezeTokens >= DailyChallengeService.maxFreezeTokens;
    final canAfford =
        progress.cauris >= DailyChallengeService.freezeTokenCost;
    final enabled = !atMax && canAfford;

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: () => _handleTap(context, ref, atMax: atMax),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.cielHauteur.withValues(alpha: 0.6),
            ),
          ),
          child: Text(
            'daily.freeze_buy_cta'.tr(
              namedArgs: <String, String>{
                'cost':
                    DailyChallengeService.freezeTokenCost.toString(),
              },
            ),
            style: AppTypography.bebas(
              size: 12,
              color: AppColors.cielHauteur,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap(
    BuildContext context,
    WidgetRef ref, {
    required bool atMax,
  }) async {
    // Court-circuit : si stock max, on l'annonce sans toucher au notifier.
    if (atMax) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'daily.freeze_buy_full'.tr(
              namedArgs: <String, String>{
                'max': DailyChallengeService.maxFreezeTokens.toString(),
              },
            ),
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.boisFonce,
        ),
      );
      return;
    }
    final ok = await ref
        .read(playerProgressProvider.notifier)
        .purchaseFreezeToken();
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'daily.freeze_buy_insufficient'.tr(
              namedArgs: <String, String>{
                'cost':
                    DailyChallengeService.freezeTokenCost.toString(),
              },
            ),
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.rouge,
        ),
      );
    }
  }
}
