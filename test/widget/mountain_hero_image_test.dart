import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/presentation/widgets/mountain_hero_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  group('MountainHeroImage', () {
    testWidgets('id sans visuel : fallback par défaut, aucun Image.asset',
        (tester) async {
      const id = 'gm_red_rocks';
      expect(AppAssets.hasMountainHero(id), isFalse, reason: 'prérequis');

      await _pump(
        tester,
        const MountainHeroImage(mountainId: id, width: 120, height: 80),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.terrain_rounded), findsOneWidget);
    });

    testWidgets('id sans visuel : fallback custom rendu tel quel',
        (tester) async {
      await _pump(
        tester,
        const MountainHeroImage(
          mountainId: 'xx_inconnu',
          fallback: Text('FALLBACK'),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('FALLBACK'), findsOneWidget);
    });

    testWidgets('id sans visuel + opacité < 1 : pas de wrapper Opacity inutile',
        (tester) async {
      await _pump(
        tester,
        const MountainHeroImage(mountainId: 'xx_inconnu', opacity: 0.3),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.terrain_rounded), findsOneWidget);
    });

    testWidgets('id avec visuel : passe par Image.asset avec le bon chemin',
        (tester) async {
      const id = 'tz_kilimanjaro';
      expect(AppAssets.hasMountainHero(id), isTrue, reason: 'prérequis');

      await _pump(tester, const MountainHeroImage(mountainId: id));

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<AssetImage>());
      expect(
        (image.image as AssetImage).assetName,
        AppAssets.mountainHero(id),
      );
    });
  });
}
