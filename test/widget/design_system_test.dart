import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/section_label.dart';
import 'package:defi_kilimandjaro/presentation/widgets/stat_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('AppButton', () {
    testWidgets('affiche le label et déclenche onPressed au tap',
        (tester) async {
      var tapped = false;
      await _pump(
        tester,
        AppButton(label: 'GRIMPER', onPressed: () => tapped = true),
      );

      expect(find.text('GRIMPER'), findsOneWidget);
      await tester.tap(find.text('GRIMPER'));
      expect(tapped, isTrue);
    });

    testWidgets('désactivé (onPressed null) : pas de tap', (tester) async {
      await _pump(tester, const AppButton(label: 'DÉSACTIVÉ', onPressed: null));

      // Opacity réduite à l'état désactivé.
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('DÉSACTIVÉ'), matching: find.byType(Opacity)),
      );
      expect(opacity.opacity, lessThan(1));
    });

    testWidgets('loading : remplace le label par un spinner', (tester) async {
      await _pump(
        tester,
        AppButton(label: 'CHARGE', loading: true, onPressed: () {}),
      );

      expect(find.text('CHARGE'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('rend chaque variante avec son label', (tester) async {
      for (final v in AppButtonVariant.values) {
        await _pump(
          tester,
          AppButton(label: v.name, variant: v, onPressed: () {}),
        );
        expect(find.text(v.name), findsOneWidget);
      }
    });
  });

  group('StatTile', () {
    testWidgets('affiche la valeur et le label en capitales', (tester) async {
      await _pump(tester, const StatTile(value: '24', label: 'Victoires'));

      expect(find.text('24'), findsOneWidget);
      expect(find.text('VICTOIRES'), findsOneWidget);
    });
  });

  group('SectionLabel', () {
    testWidgets('affiche le titre en capitales', (tester) async {
      await _pump(tester, const SectionLabel('Derniers duels'));

      expect(find.text('DERNIERS DUELS'), findsOneWidget);
    });
  });
}
