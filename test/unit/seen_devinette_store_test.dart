import 'package:defi_kilimandjaro/data/local/seen_devinette_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests du tracker anti-répétition [SeenDevinetteStore] (Feature B).
///
/// Invariants produit :
/// - ordre FIFO (le plus récent en queue, promotion idempotente) ;
/// - exclusion stricte tant que `seen.length <= total * 0.8` ;
/// - éviction progressive des plus anciennes sous le seuil de fraîcheur ;
/// - hardcap 1000 par pack ; `clearAll` vide tout ; persistance.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<SeenDevinetteStore> makeStore() async {
    final prefs = await SharedPreferences.getInstance();
    return SeenDevinetteStore(prefs);
  }

  group('markSolved — FIFO & idempotence', () {
    test("ordre d'insertion = ordre FIFO (plus récent en queue)", () async {
      final store = await makeStore();
      await store.markSolved(packId: 'p', devinetteId: 'a');
      await store.markSolved(packId: 'p', devinetteId: 'b');
      await store.markSolved(packId: 'p', devinetteId: 'c');

      expect(store.seenForPack('p'), <String>['a', 'b', 'c']);
    });

    test("re-marquer promeut l'id en queue sans dupliquer", () async {
      final store = await makeStore();
      await store.markSolved(packId: 'p', devinetteId: 'a');
      await store.markSolved(packId: 'p', devinetteId: 'b');
      await store.markSolved(packId: 'p', devinetteId: 'a');

      expect(store.seenForPack('p'), <String>['b', 'a']);
    });

    test('packs indépendants', () async {
      final store = await makeStore();
      await store.markSolved(packId: 'p1', devinetteId: 'a');
      await store.markSolved(packId: 'p2', devinetteId: 'b');

      expect(store.seenForPack('p1'), <String>['a']);
      expect(store.seenForPack('p2'), <String>['b']);
    });

    test('id ou pack vide est ignoré', () async {
      final store = await makeStore();
      await store.markSolved(packId: 'p', devinetteId: '');
      await store.markSolved(packId: '', devinetteId: 'a');
      expect(store.seenForPack('p'), isEmpty);
    });
  });

  group('effectiveExclusions — exclusion stricte + éviction', () {
    test('exclut tout tant que seen <= 80% du total (fraîcheur 20%)',
        () async {
      final store = await makeStore();
      // total = 10 → maxExcluded = floor(10 * 0.8) = 8.
      for (var i = 0; i < 8; i++) {
        await store.markSolved(packId: 'p', devinetteId: 'd$i');
      }
      final excl = store.effectiveExclusions(packId: 'p', packTotalCount: 10);
      expect(excl.length, 8);
      expect(excl, containsAll(<String>['d0', 'd7']));
    });

    test('évince les plus anciennes au-delà du seuil', () async {
      final store = await makeStore();
      // total = 10 → maxExcluded = 8. On marque 10 vues → on n'exclut que
      // les 8 plus récentes (d2..d9), d0/d1 redeviennent éligibles.
      for (var i = 0; i < 10; i++) {
        await store.markSolved(packId: 'p', devinetteId: 'd$i');
      }
      final excl = store.effectiveExclusions(packId: 'p', packTotalCount: 10);
      expect(excl.length, 8);
      expect(excl.contains('d0'), isFalse);
      expect(excl.contains('d1'), isFalse);
      expect(excl, containsAll(<String>['d2', 'd9']));
    });

    test('packTotalCount <= 0 → set vide (filet de sécurité)', () async {
      final store = await makeStore();
      await store.markSolved(packId: 'p', devinetteId: 'a');
      expect(
        store.effectiveExclusions(packId: 'p', packTotalCount: 0),
        isEmpty,
      );
    });

    test('pack jamais vu → set vide', () async {
      final store = await makeStore();
      expect(
        store.effectiveExclusions(packId: 'vide', packTotalCount: 100),
        isEmpty,
      );
    });
  });

  group('hardcap & clearAll', () {
    test('hardcap 1000 par pack — évince les plus anciennes', () async {
      final store = await makeStore();
      for (var i = 0; i < 1005; i++) {
        await store.markSolved(packId: 'p', devinetteId: 'd$i');
      }
      final seen = store.seenForPack('p');
      expect(seen.length, 1000);
      // Les 5 plus anciennes (d0..d4) ont été évincées.
      expect(seen.first, 'd5');
      expect(seen.last, 'd1004');
    });

    test('clearAll vide tous les packs', () async {
      final store = await makeStore();
      await store.markSolved(packId: 'p1', devinetteId: 'a');
      await store.markSolved(packId: 'p2', devinetteId: 'b');

      await store.clearAll();

      expect(store.seenForPack('p1'), isEmpty);
      expect(store.seenForPack('p2'), isEmpty);
    });
  });

  group('persistance', () {
    test('le journal survit à un redémarrage', () async {
      final prefs = await SharedPreferences.getInstance();
      final s1 = SeenDevinetteStore(prefs);
      await s1.markSolved(packId: 'p', devinetteId: 'a');
      await s1.markSolved(packId: 'p', devinetteId: 'b');

      final s2 = SeenDevinetteStore(prefs);
      expect(s2.seenForPack('p'), <String>['a', 'b']);
    });
  });
}
