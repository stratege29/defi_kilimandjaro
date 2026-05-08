import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/presentation/onboarding/onboarding_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OnboardingView shows step 1 then advances on tap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: OnboardingView()),
      ),
    );

    // Step 1.
    expect(find.text('Bienvenue, voyageur'), findsOneWidget);
    expect(find.text('Suivant'), findsOneWidget);
    expect(find.text('Passer'), findsOneWidget);

    // Tap "Suivant" → advance to step 2.
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text("Gravis l'Afrique"), findsOneWidget);

    // Advance to step 3.
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Défie un ami'), findsOneWidget);
    expect(find.text("C'EST PARTI"), findsOneWidget);
  });

  test('isOnboardingSeen / markOnboardingSeen persistence', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    expect(isOnboardingSeen(prefs), isFalse);
    await markOnboardingSeen(prefs);
    expect(isOnboardingSeen(prefs), isTrue);
  });
}
