import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/presentation/result/victory_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests du comportement de la bannière de victoire compacte : auto-avance,
/// tap = avance immédiate, chevron / ×2 = reprise en main (SUIVANT), et
/// garantie « onNext appelé une seule fois ».
///
/// Sans `EasyLocalization` monté, `.tr()` retourne la clé — les finders
/// ciblent donc les clés i18n littérales.

final _devinette = Devinette(
  id: 'test_kora',
  pack: 'culture_ci',
  country: 'ci',
  answer: 'KORA',
  lettersPool: 'KORA'.split(''),
  riddleByLang: const <String, String>{'fr': 'Énigme test'},
  explanationByLang: const <String, String>{'fr': 'Harpe-luth mandingue.'},
  difficulty: 1,
  estimatedTimeS: 15,
  tags: const <String>[],
);

Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback onNext,
  Future<bool> Function()? doubleReward,
  int comboStreak = 0,
  double comboMultiplier = 1.0,
  int perfectBonus = 0,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: VictoryBanner(
          devinette: _devinette,
          caurisAwarded: 50,
          starsEarned: 2,
          comboStreak: comboStreak,
          comboMultiplier: comboMultiplier,
          perfectBonus: perfectBonus,
          doubleReward: doubleReward,
          onNext: onNext,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('affiche le mot-réponse et avance seule après 1,8 s',
      (tester) async {
    var next = 0;
    await _pump(tester, onNext: () => next++);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('KORA'), findsOneWidget);
    expect(next, 0);

    await tester.pump(const Duration(milliseconds: 1400)); // t = 1,7 s
    expect(next, 0);
    await tester.pump(const Duration(milliseconds: 200)); // t = 1,9 s
    expect(next, 1);
  });

  testWidgets("tap n'importe où avance tout de suite, une seule fois",
      (tester) async {
    var next = 0;
    await _pump(tester, onNext: () => next++);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tapAt(const Offset(20, 20)); // hors bandeau
    expect(next, 1);

    // Ni un second tap ni l'auto-avance ne rappellent onNext.
    await tester.tapAt(const Offset(20, 20));
    await tester.pump(const Duration(seconds: 3));
    expect(next, 1);
  });

  testWidgets(
      "chevron : déplie l'explication, annule l'auto-avance, SUIVANT avance",
      (tester) async {
    var next = 0;
    await _pump(tester, onNext: () => next++);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey<String>('victory_banner_explain')));
    await tester.pumpAndSettle();

    expect(find.text('Harpe-luth mandingue.'), findsOneWidget);
    expect(find.text('result.victory.next'), findsOneWidget);

    // L'auto-avance est annulée…
    await tester.pump(const Duration(seconds: 3));
    expect(next, 0);
    // …et un tap hors bouton n'avance plus : le joueur lit.
    await tester.tapAt(const Offset(20, 20));
    expect(next, 0);

    await tester.tap(find.text('result.victory.next'));
    expect(next, 1);
  });

  testWidgets(
      '×2 : absent si non éligible, sinon déclenche le rewarded et annule '
      "l'auto-avance", (tester) async {
    var next = 0;
    await _pump(tester, onNext: () => next++);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('victory_banner_double')),
      findsNothing,
    );

    var rewarded = 0;
    await _pump(
      tester,
      onNext: () => next++,
      doubleReward: () async {
        rewarded++;
        return true;
      },
    );
    await tester.pump(const Duration(milliseconds: 300));
    final double = find.byKey(const ValueKey<String>('victory_banner_double'));
    expect(double, findsOneWidget);

    await tester.tap(double);
    await tester.pumpAndSettle();
    expect(rewarded, 1);
    // Bonus crédité : le bouton disparaît, SUIVANT prend le relais.
    expect(double, findsNothing);
    expect(find.text('result.victory.next'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(next, 0);

    await tester.tap(find.text('result.victory.next'));
    expect(next, 1);
  });

  testWidgets('lignes série et sans faute quand applicables', (tester) async {
    await _pump(
      tester,
      onNext: () {},
      comboStreak: 3,
      comboMultiplier: 1.5,
      perfectBonus: 10,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Série ×3 · cauris ×1,5'), findsOneWidget);
    expect(find.text('Sans faute +10'), findsOneWidget);
    // Neutralise l'auto-avance en attente avant la fin du test.
    await tester.pump(const Duration(seconds: 2));
  });
}
