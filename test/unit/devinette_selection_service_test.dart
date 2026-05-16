import 'package:defi_kilimandjaro/data/services/devinette_selection_service_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:defi_kilimandjaro/domain/repositories/devinette_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake repo en mémoire — déterministe, pas de Drift ni Firestore.
/// Ordre d'itération préservé (LinkedHashMap), critique pour les tests
/// avec seed fixe.
class _FakeDevinetteRepository implements DevinetteRepository {
  _FakeDevinetteRepository(this._packs);
  final Map<String, List<Devinette>> _packs;

  @override
  Future<List<Devinette>> loadPack(String packId) async {
    return _packs[packId] ?? const <Devinette>[];
  }

  @override
  Future<Devinette> randomFromPack(String packId) async {
    throw UnimplementedError();
  }

  @override
  Future<Devinette> randomFromPackExcluding(
    String packId,
    Iterable<String> excludeIds,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<Devinette> atIndex(String packId, int index) async {
    throw UnimplementedError();
  }
}

Devinette _make({
  required String id,
  required String pack,
  int difficulty = 1,
}) {
  return Devinette(
    id: id,
    pack: pack,
    country: 'ci',
    answer: id.toUpperCase(),
    lettersPool: id.toUpperCase().split(''),
    riddleByLang: <String, String>{'fr': 'riddle-$id'},
    explanationByLang: <String, String>{'fr': 'expl-$id'},
    difficulty: difficulty,
    estimatedTimeS: 20,
    tags: const <String>[],
  );
}

void main() {
  group('WeightedDevinetteSelectionService — tirage simple', () {
    test('seed fixe → tirage déterministe', () async {
      final repo = _FakeDevinetteRepository({
        'culture_ci': [
          _make(id: 'd1', pack: 'culture_ci'),
          _make(id: 'd2', pack: 'culture_ci'),
          _make(id: 'd3', pack: 'culture_ci'),
        ],
      });
      final service = WeightedDevinetteSelectionService(repository: repo);
      final mix = PackMix.single('culture_ci');

      final first = await service.nextDevinette(
        mix: mix,
        targetDifficulty: 1,
        excludeIds: const <String>{},
        seed: 42,
      );
      final second = await service.nextDevinette(
        mix: mix,
        targetDifficulty: 1,
        excludeIds: const <String>{},
        seed: 42,
      );
      expect(first.id, second.id, reason: 'même seed → même résultat');
    });

    test('exclut les ids fournis', () async {
      final repo = _FakeDevinetteRepository({
        'culture_ci': [
          _make(id: 'd1', pack: 'culture_ci'),
          _make(id: 'd2', pack: 'culture_ci'),
        ],
      });
      final service = WeightedDevinetteSelectionService(repository: repo);

      // 50 tirages avec excludeIds={d1} : on ne doit jamais retomber sur d1.
      for (var i = 0; i < 50; i++) {
        final d = await service.nextDevinette(
          mix: PackMix.single('culture_ci'),
          targetDifficulty: 1,
          excludeIds: const <String>{'d1'},
          seed: i,
        );
        expect(d.id, 'd2');
      }
    });
  });

  group('Tirage pondéré 70/30', () {
    test('ratio ≈ 70/30 sur 10000 itérations (±3%)', () async {
      final repo = _FakeDevinetteRepository({
        'a': [_make(id: 'a1', pack: 'a')],
        'b': [_make(id: 'b1', pack: 'b')],
      });
      final service = WeightedDevinetteSelectionService(repository: repo);
      final mix = PackMix(
        weights: const <String, double>{'a': 0.7, 'b': 0.3},
      );

      var aCount = 0;
      var bCount = 0;
      const iterations = 10000;
      for (var i = 0; i < iterations; i++) {
        final d = await service.nextDevinette(
          mix: mix,
          targetDifficulty: 1,
          excludeIds: const <String>{},
          seed: i,
        );
        if (d.pack == 'a') {
          aCount++;
        } else {
          bCount++;
        }
      }
      final aRatio = aCount / iterations;
      final bRatio = bCount / iterations;
      // Tolérance 3% : très large mais robuste aux variations RNG.
      expect(aRatio, closeTo(0.7, 0.03));
      expect(bRatio, closeTo(0.3, 0.03));
    });
  });

  group('Fallback difficulté', () {
    test('pas de difficulté 5 → renvoie diff 4 (delta minimal)', () async {
      final repo = _FakeDevinetteRepository({
        'culture_ci': [
          _make(id: 'd_easy', pack: 'culture_ci'),
          _make(id: 'd_mid', pack: 'culture_ci', difficulty: 3),
          _make(id: 'd_hard', pack: 'culture_ci', difficulty: 4),
        ],
      });
      final service = WeightedDevinetteSelectionService(repository: repo);
      // target=5 ; |1-5|=4 ; |3-5|=2 ; |4-5|=1 → on doit tirer d_hard.
      final d = await service.nextDevinette(
        mix: PackMix.single('culture_ci'),
        targetDifficulty: 5,
        excludeIds: const <String>{},
      );
      expect(d.id, 'd_hard');
    });

    test('difficulté exacte est préférée au fallback', () async {
      final repo = _FakeDevinetteRepository({
        'culture_ci': [
          _make(id: 'easy', pack: 'culture_ci'),
          _make(id: 'exact', pack: 'culture_ci', difficulty: 3),
          _make(id: 'hard', pack: 'culture_ci', difficulty: 5),
        ],
      });
      final service = WeightedDevinetteSelectionService(repository: repo);
      final d = await service.nextDevinette(
        mix: PackMix.single('culture_ci'),
        targetDifficulty: 3,
        excludeIds: const <String>{},
        seed: 7,
      );
      expect(d.id, 'exact');
    });
  });

  group('Fallback pack', () {
    test('pack A vide → tire de pack B', () async {
      final repo = _FakeDevinetteRepository({
        'a': const <Devinette>[], // pack A vide
        'b': [_make(id: 'b1', pack: 'b'), _make(id: 'b2', pack: 'b')],
      });
      final service = WeightedDevinetteSelectionService(repository: repo);

      // Mix 90/10 : seed fixe → la roue tombera très probablement sur 'a'.
      // Le service doit basculer sur 'b' silencieusement.
      final mix = PackMix(
        weights: const <String, double>{'a': 0.9, 'b': 0.1},
      );
      for (var seed = 0; seed < 30; seed++) {
        final d = await service.nextDevinette(
          mix: mix,
          targetDifficulty: 1,
          excludeIds: const <String>{},
          seed: seed,
        );
        expect(d.pack, 'b');
      }
    });

    test('pack A : toutes les questions exclues → fallback sur B', () async {
      final repo = _FakeDevinetteRepository({
        'a': [_make(id: 'a1', pack: 'a'), _make(id: 'a2', pack: 'a')],
        'b': [_make(id: 'b1', pack: 'b')],
      });
      final service = WeightedDevinetteSelectionService(repository: repo);
      // Force la roue sur 'a' (poids écrasant) puis exclut tout 'a' → 'b'.
      final mix = PackMix(
        weights: const <String, double>{'a': 0.99, 'b': 0.01},
      );
      final d = await service.nextDevinette(
        mix: mix,
        targetDifficulty: 1,
        excludeIds: const <String>{'a1', 'a2'},
        seed: 0,
      );
      expect(d.id, 'b1');
    });

    test('tous les packs vides → StateError explicite', () async {
      final repo = _FakeDevinetteRepository({
        'a': const <Devinette>[],
        'b': const <Devinette>[],
      });
      final service = WeightedDevinetteSelectionService(repository: repo);
      expect(
        () => service.nextDevinette(
          mix: PackMix(
            weights: const <String, double>{'a': 0.5, 'b': 0.5},
          ),
          targetDifficulty: 1,
          excludeIds: const <String>{},
          seed: 0,
        ),
        throwsStateError,
      );
    });
  });
}
