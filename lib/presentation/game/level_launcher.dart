import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/core/utils/level_difficulty_resolver.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/services/devinette_selection_service_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/domain/services/level_devinette_drawer.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Lance le niveau [levelIndex] de [mountain] : résout la config, propose
/// l'embranchement « voie exposée » quand le niveau s'y prête, tire les
/// devinettes selon la structure du niveau (`LevelKind`), mémorise leurs
/// ids pour l'anti-répétition puis navigue vers `/game`.
///
/// Point d'entrée **unique** des niveaux Sommets — partagé par la carte
/// d'accueil, le détail montagne et l'enchaînement après victoire
/// ([replace] = `pushReplacement` de la route `/game` courante).
///
/// Renvoie `true` si la navigation a eu lieu ; `false` si le joueur a
/// refermé l'embranchement sans choisir, ou en cas d'erreur de tirage
/// (un snackbar est alors affiché). Le défi du jour et le Hub ne passent
/// pas par ici.
Future<bool> launchMountainLevel(
  BuildContext context,
  WidgetRef ref, {
  required Mountain mountain,
  required int levelIndex,
  bool replace = false,
}) async {
  var config = LevelDifficultyResolver.resolve(
    mountain: mountain,
    levelIndex: levelIndex,
  );
  var isExposed = false;

  if (LevelDifficultyResolver.isBranchingLevel(
    mountain: mountain,
    levelIndex: levelIndex,
  )) {
    final chosen = await _chooseRoute(context, config);
    if (chosen == null) return false;
    isExposed = chosen != config;
    config = chosen;
  }

  try {
    final progress = ref.read(playerProgressProvider);
    final drawer = LevelDevinetteDrawer(
      ref.read(devinetteSelectionServiceProvider),
    );
    final devinettes = await drawer.draw(
      config: config,
      mix: progress.activePackMix,
      excludeIds: progress.recentDevinetteIds.toSet(),
      fallbackPackIds: progress.ownedPacks,
    );
    final notifier = ref.read(playerProgressProvider.notifier);
    for (final d in devinettes) {
      await notifier.recordRecentDevinette(d.id);
    }
    if (!context.mounted) return false;
    final args = GameArgs(
      devinette: devinettes.first,
      extraDevinettes: devinettes.sublist(1),
      mountainId: mountain.id,
      levelIndex: levelIndex,
      config: config,
      isExposed: isExposed,
    );
    if (replace) {
      context.pushReplacement(AppRoutes.game, extra: args);
    } else {
      await context.push<void>(AppRoutes.game, extra: args);
    }
    return true;
  } on Object catch (_) {
    // `on Object` (pas `on Exception`) : un tirage épuisé lève un
    // `StateError`, qui étend `Error` et n'est PAS une `Exception`.
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erreur de chargement', style: AppTypography.bebas()),
        backgroundColor: AppColors.rouge,
      ),
    );
    return false;
  }
}

/// Dialogue d'embranchement : « Voie facile » (config telle quelle) ou
/// « Voie exposée » (`LevelDifficultyResolver.exposedVariant`). Chaque
/// option affiche ses chiffres — temps, lettres parasites, multiplicateur
/// cauris. Renvoie la config choisie, ou `null` si le dialogue est fermé
/// sans choix (retour système). Le choix n'est pas persisté.
Future<LevelDifficultyConfig?> _chooseRoute(
  BuildContext context,
  LevelDifficultyConfig config,
) {
  final exposed = LevelDifficultyResolver.exposedVariant(config);
  return showDialog<LevelDifficultyConfig>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: AppColors.boisFonce,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.orSoleil.withValues(alpha: 0.5)),
      ),
      title: Text(
        'game.route_choice.title'.tr(),
        style: AppTypography.bebas(size: 20, color: AppColors.orSoleil),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'game.route_choice.subtitle'.tr(),
            style: AppTypography.crimson(size: 15),
          ),
          const SizedBox(height: 14),
          _RouteOption(
            label: 'game.route_choice.easy'.tr(),
            config: config,
            color: AppColors.vertClair,
            onTap: () => Navigator.of(dialogCtx).pop(config),
          ),
          const SizedBox(height: 10),
          _RouteOption(
            label: 'game.route_choice.exposed'.tr(),
            config: exposed,
            color: AppColors.rouge,
            onTap: () => Navigator.of(dialogCtx).pop(exposed),
          ),
        ],
      ),
    ),
  );
}

/// Carte d'une voie : libellé + chiffres (temps, lettres parasites, cauris).
class _RouteOption extends StatelessWidget {
  const _RouteOption({
    required this.label,
    required this.config,
    required this.color,
    required this.onTap,
  });

  final String label;
  final LevelDifficultyConfig config;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final figures = <String>[
      'game.route_choice.time'.tr(
        namedArgs: <String, String>{'seconds': '${config.timerSeconds}'},
      ),
      'game.route_choice.extra_letters'.tr(
        namedArgs: <String, String>{'count': '${config.distractorCount}'},
      ),
      'game.route_choice.cauris'.tr(
        namedArgs: <String, String>{
          'mult': config.caurisMultiplier.toStringAsFixed(2),
        },
      ),
    ];
    return Material(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.7), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: AppTypography.bebas(
                  size: 18,
                  color: color,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                figures.join('  ·  '),
                style: AppTypography.bodySm.copyWith(color: AppColors.ivoire),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
