import 'package:defi_kilimandjaro/presentation/widgets/flag_roundel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    // En test, pas de fetch réseau des polices Google : fallback silencieux.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('FlagRoundel', () {
    testWidgets('affiche le code pays en capitales', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FlagRoundel(countryCode: 'ci')),
        ),
      );

      expect(find.text('CI'), findsOneWidget);
    });

    testWidgets('rend un disque de la taille demandée', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FlagRoundel(countryCode: 'TZ', size: 40)),
        ),
      );

      expect(tester.getSize(find.byType(FlagRoundel)), const Size(40, 40));
    });
  });
}
