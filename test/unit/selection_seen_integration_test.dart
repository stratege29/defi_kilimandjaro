import 'package:defi_kilimandjaro/data/local/seen_devinette_store.dart';
import 'package:defi_kilimandjaro/data/services/devinette_selection_service_impl.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:defi_kilimandjaro/domain/repositories/devinette_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Test d'intégration tirage ↔ anti-répétition (Features A+B câblées).
///
/// On branche un vrai [SeenDevinetteStore] dans le service de tirage et on
/// marque chaque devinette tirée comme « vue ». Invariant produit : tant que
/// le pool « jamais vu » reste ≥ 20 % du pack, aucune devinette ne doit se
/// répéter — le joueur ne retombe jamais sur un mot frais déjà résolu.
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

Devinette _make({required String id, required String pack}) {
  final ans = id.toUpperCase();
  return Devinette(
    id: id,
    pack: pack,
    country: 'ci',
    answer: ans,
    lettersPool: ans.split(''),
    riddleByLang: <String, String>{'fr': 'riddle-$id'},
    explanationByLang: <String, String>{'fr': 'expl-$id'},
    difficulty: 1,
    estimatedTimeS: 20,
    tags: const <String>[],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'le tracker câblé empêche toute répétition tant que pool frais ≥ 20%',
    () async {
      const packId = 'culture_ci';
      const total = 180;
      final pack = <Devinette>[
        for (var i = 0; i < total; i++)
          _make(id: 'd${i.toString().padLeft(3, '0')}', pack: packId),
      ];
      final repo = _FakeDevinetteRepository(<String, List<Devinette>>{
        packId: pack,
      });

      final prefs = await SharedPreferences.getInstance();
      final tracker = SeenDevinetteStore(prefs);
      final service = WeightedDevinetteSelectionService(
        repository: repo,
        seenTracker: tracker,
      );
      final mix = PackMix.single(packId);

      // maxExcluded = floor(180 * 0.8) = 144. Tant que ≤ 144 vues, le tracker
      // exclut tout le vu → zéro répétition garantie. On tire 144 fois.
      const drawsBeforeRecycle = 144;
      final seenIds = <String>{};
      for (var i = 0; i < drawsBeforeRecycle; i++) {
        final d = await service.nextDevinette(
          mix: mix,
          targetDifficulty: 1,
          excludeIds: const <String>{},
          seed: i,
        );
        expect(
          seenIds.contains(d.id),
          isFalse,
          reason: 'répétition au tirage #$i (id=${d.id}) alors que le pool '
              'frais est encore ≥ 20 %',
        );
        seenIds.add(d.id);
        await tracker.markSolved(packId: packId, devinetteId: d.id);
      }

      expect(seenIds.length, drawsBeforeRecycle);
    },
  );

  test(
    'dégradation gracieuse : sur-exclusion totale → sert une répétition, '
    'jamais de StateError',
    () async {
      const packId = 'culture_ci';
      final pack = <Devinette>[
        for (var i = 0; i < 5; i++) _make(id: 'd$i', pack: packId),
      ];
      final repo = _FakeDevinetteRepository(<String, List<Devinette>>{
        packId: pack,
      });
      final prefs = await SharedPreferences.getInstance();
      final tracker = SeenDevinetteStore(prefs);
      for (final d in pack) {
        await tracker.markSolved(packId: packId, devinetteId: d.id);
      }
      final service = WeightedDevinetteSelectionService(
        repository: repo,
        seenTracker: tracker,
      );

      // Toutes les ids vues ET passées en excludeIds : les paliers 0 et 1
      // s'épuisent ; le palier 2 (aucune exclusion) doit servir un mot —
      // une répétition est préférable à un crash.
      final d = await service.nextDevinette(
        mix: PackMix.single(packId),
        targetDifficulty: 1,
        excludeIds: <String>{for (final x in pack) x.id},
        seed: 0,
      );
      expect(pack.map((e) => e.id), contains(d.id));
    },
  );

  test('pack réellement vide → StateError (vraie erreur de config)', () async {
    final repo = _FakeDevinetteRepository(<String, List<Devinette>>{
      'culture_ci': const <Devinette>[],
    });
    final prefs = await SharedPreferences.getInstance();
    final service = WeightedDevinetteSelectionService(
      repository: repo,
      seenTracker: SeenDevinetteStore(prefs),
    );
    expect(
      () => service.nextDevinette(
        mix: PackMix.single('culture_ci'),
        targetDifficulty: 1,
        excludeIds: const <String>{},
        seed: 0,
      ),
      throwsStateError,
    );
  });
}
