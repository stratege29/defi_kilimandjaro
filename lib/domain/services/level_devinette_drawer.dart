import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_kind.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:defi_kilimandjaro/domain/services/devinette_selection_service.dart';

/// Tire **toutes** les devinettes d'un niveau selon sa structure
/// (`LevelDifficultyConfig.kind`), par-dessus le [DevinetteSelectionService]
/// mono-devinette.
///
/// - [LevelKind.classic] / [LevelKind.blindBoss] : une devinette au bucket
///   de la config (comportement historique).
/// - [LevelKind.rafale] : trois mots **courts** — bucket ramené à
///   [rafaleMaxBucket] (4-6 lettres) quelle que soit la config, ids distincts.
/// - [LevelKind.duo] : deux mots au bucket de la config, ids distincts, de
///   longueurs différentes de préférence (un retirage si la seconde a la
///   même longueur que la première).
///
/// Chaque tirage exclut les ids déjà tirés dans le niveau en plus des
/// exclusions du caller (récentes) — le seen-tracker est appliqué par le
/// service lui-même.
class LevelDevinetteDrawer {
  const LevelDevinetteDrawer(this._selection);

  final DevinetteSelectionService _selection;

  /// Bucket de longueur maximal d'un mot de rafale (bucket 2 = 5-6 lettres).
  static const int rafaleMaxBucket = 2;

  /// Renvoie les devinettes du niveau, principale en tête. La liste a
  /// toujours `config.kind.devinetteCount` éléments.
  Future<List<Devinette>> draw({
    required LevelDifficultyConfig config,
    required PackMix mix,
    required Set<String> excludeIds,
    Set<String> fallbackPackIds = const <String>{},
  }) async {
    final bucket = config.kind == LevelKind.rafale
        ? config.wordLengthBucket.clamp(1, rafaleMaxBucket)
        : config.wordLengthBucket;
    final drawn = <Devinette>[];
    final excluded = <String>{...excludeIds};

    Future<Devinette> next() async {
      final d = await _selection.nextDevinette(
        mix: mix,
        targetDifficulty: config.difficultyTier,
        wordLengthBucket: bucket,
        excludeIds: excluded,
        fallbackPackIds: fallbackPackIds,
      );
      excluded.add(d.id);
      return d;
    }

    drawn.add(await next());
    for (var i = 1; i < config.kind.devinetteCount; i++) {
      var candidate = await next();
      // Duo : deux longueurs différentes rendent les deux rangées de cases
      // lisibles d'un coup d'œil. Un seul retirage — au-delà, on accepte.
      if (config.kind == LevelKind.duo &&
          candidate.answer.length == drawn.first.answer.length) {
        final retry = await next();
        if (retry.answer.length != drawn.first.answer.length) {
          candidate = retry;
        }
      }
      drawn.add(candidate);
    }
    return drawn;
  }
}
