import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/first_encounter_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests du bandeau compact de première rencontre : repli automatique après
/// 3 s, tap = repli anticipé, `onDismissed` appelé une seule fois, filtre des
/// modificateurs sans description joueur.

Future<void> _pump(
  WidgetTester tester, {
  required Set<LevelModifier> modifiers,
  required VoidCallback onDismissed,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: FirstEncounterBanner(
            modifiers: modifiers,
            onDismissed: onDismissed,
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('describable ne garde que les modificateurs décrits côté joueur', () {
    final result = FirstEncounterBanner.describable(<LevelModifier>{
      LevelModifier.wind,
      LevelModifier.fog,
      LevelModifier.mirage,
      LevelModifier.lava, // déclaré dans l'enum, sans runtime ni i18n
    });
    expect(result, <LevelModifier>{
      LevelModifier.wind,
      LevelModifier.fog,
      LevelModifier.mirage,
    });
  });

  testWidgets('affiche nom + description et se replie seul après 3 s', (
    tester,
  ) async {
    var dismissed = 0;
    await _pump(
      tester,
      modifiers: <LevelModifier>{LevelModifier.wind},
      onDismissed: () => dismissed++,
    );
    await tester.pump(const Duration(milliseconds: 250));

    // Sans EasyLocalization, `.tr()` retourne la clé : on vérifie que le
    // nom et la description sont bien composés dans la même ligne.
    expect(
      find.textContaining(
        'game.briefing.modifier.wind.name',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'game.briefing.modifier.wind.desc',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(dismissed, 0);

    await tester.pump(const Duration(milliseconds: 2900)); // t ≈ 3,15 s
    await tester.pumpAndSettle(); // fondu de sortie (220 ms)
    expect(dismissed, 1);
  });

  testWidgets('tap replie plus tôt ; onDismissed une seule fois', (
    tester,
  ) async {
    var dismissed = 0;
    await _pump(
      tester,
      modifiers: <LevelModifier>{LevelModifier.fog, LevelModifier.shuffle},
      onDismissed: () => dismissed++,
    );
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byType(FirstEncounterBanner));
    await tester.pumpAndSettle();
    expect(dismissed, 1);

    // Le timer de 3 s ne rappelle pas onDismissed.
    await tester.pump(const Duration(seconds: 4));
    expect(dismissed, 1);
  });
}
