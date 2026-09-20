import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_kind.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:defi_kilimandjaro/domain/services/devinette_selection_service.dart';
import 'package:defi_kilimandjaro/domain/services/level_devinette_drawer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake déterministe : sert les devinettes dans l'ordre, en sautant les
/// exclues, et journalise le bucket demandé à chaque tirage.
class _FakeSelection implements DevinetteSelectionService {
  _FakeSelection(this.pool);

  final List<Devinette> pool;
  final List<int?> bucketsAsked = <int?>[];

  @override
  Future<Devinette> nextDevinette({
    required PackMix mix,
    required int targetDifficulty,
    required Set<String> excludeIds,
    int? wordLengthBucket,
    int? seed,
    Set<String> fallbackPackIds = const <String>{},
  }) async {
    bucketsAsked.add(wordLengthBucket);
    return pool.firstWhere((d) => !excludeIds.contains(d.id));
  }
}

Devinette _d(String answer) => Devinette(
  id: 'id_$answer',
  pack: 'culture_ci',
  country: 'ci',
  answer: answer,
  lettersPool: answer.split(''),
  riddleByLang: const <String, String>{'fr': 'Énigme'},
  explanationByLang: const <String, String>{'fr': 'Explication'},
  difficulty: 2,
  estimatedTimeS: 15,
  tags: const <String>[],
);

LevelDifficultyConfig _config(LevelKind kind, {int bucket = 4}) =>
    LevelDifficultyConfig(
      difficultyTier: 3,
      wordLengthBucket: bucket,
      timerSeconds: 40,
      caurisMultiplier: 1.6,
      kind: kind,
    );

void main() {
  final mix = PackMix.uniform(const <String>{'culture_ci'});

  test('classic : une devinette au bucket de la config', () async {
    final fake = _FakeSelection([_d('KORA'), _d('BOLI')]);
    final drawn = await LevelDevinetteDrawer(fake).draw(
      config: _config(LevelKind.classic),
      mix: mix,
      excludeIds: const <String>{},
    );
    expect(drawn.map((d) => d.answer), ['KORA']);
    expect(fake.bucketsAsked, [4]);
  });

  test('rafale : trois ids distincts, bucket ramené à 2 quelle que soit la '
      'config, exclusions du caller respectées', () async {
    final fake = _FakeSelection([
      _d('KORA'),
      _d('BOLI'),
      _d('DAMA'),
      _d('TAM'),
    ]);
    final drawn = await LevelDevinetteDrawer(fake).draw(
      config: _config(LevelKind.rafale, bucket: 5),
      mix: mix,
      excludeIds: const <String>{'id_KORA'},
    );
    expect(drawn.map((d) => d.answer), ['BOLI', 'DAMA', 'TAM']);
    expect(fake.bucketsAsked, [2, 2, 2]);
  });

  test('rafale : bucket 1 conservé (jamais relevé)', () async {
    final fake = _FakeSelection([_d('A'), _d('B'), _d('C')]);
    await LevelDevinetteDrawer(fake).draw(
      config: _config(LevelKind.rafale, bucket: 1),
      mix: mix,
      excludeIds: const <String>{},
    );
    expect(fake.bucketsAsked, [1, 1, 1]);
  });

  test('duo : deux ids distincts au bucket de la config, longueur différente '
      'préférée (un retirage)', () async {
    final fake = _FakeSelection([_d('KORA'), _d('BOLI'), _d('DJEMBE')]);
    final drawn = await LevelDevinetteDrawer(fake).draw(
      config: _config(LevelKind.duo),
      mix: mix,
      excludeIds: const <String>{},
    );
    expect(drawn.map((d) => d.answer), ['KORA', 'DJEMBE']);
    expect(fake.bucketsAsked, [4, 4, 4]);
  });

  test('duo : même longueur acceptée si le retirage échoue aussi', () async {
    final fake = _FakeSelection([_d('KORA'), _d('BOLI'), _d('DAMA')]);
    final drawn = await LevelDevinetteDrawer(fake).draw(
      config: _config(LevelKind.duo),
      mix: mix,
      excludeIds: const <String>{},
    );
    expect(drawn.map((d) => d.answer), ['KORA', 'BOLI']);
  });
}
