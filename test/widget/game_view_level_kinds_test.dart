import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/audio/audio_engine.dart';
import 'package:defi_kilimandjaro/data/repositories/mountain_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/domain/entities/level_difficulty_config.dart';
import 'package:defi_kilimandjaro/domain/entities/level_kind.dart';
import 'package:defi_kilimandjaro/domain/entities/mountain.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_theme.dart';
import 'package:defi_kilimandjaro/presentation/game/game_args.dart';
import 'package:defi_kilimandjaro/presentation/game/game_view.dart';
import 'package:defi_kilimandjaro/presentation/game/widgets/answer_cells.dart';
import 'package:defi_kilimandjaro/presentation/theme/pack_theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rendu de [GameView] sur un petit écran (375×667 logique, iPhone SE /
/// 8) pour les trois structures de niveau non classiques. Un RenderFlex
/// overflow ou toute exception de rendu fait échouer le test (rapportés
/// par `FlutterError.onError` du binding de test).
///
/// Sans `EasyLocalization` monté, `.tr()` retourne la clé — les finders
/// ciblent donc les clés i18n littérales.

class _FakeAudio extends AudioController {
  _FakeAudio() : super(AudioEngine.instance);
  @override
  void hapticDeselect() {}
  @override
  Future<void> playLetterSelect(int letterIdx) async {}
  @override
  Future<void> playWordComplete() async {}
  @override
  Future<void> playHintUsed() async {}
  @override
  Future<void> playVictory() async {}
  @override
  Future<void> playBossVictory() async {}
  @override
  Future<void> playFailure() async {}
  @override
  Future<void> playWrongAnswer() async {}
  @override
  Future<void> playTimerTick(int bpm) async {}
}

Devinette _devinette(String answer, String riddle) => Devinette(
  id: 'test_$answer',
  pack: 'culture_ci',
  country: 'ci',
  answer: answer,
  lettersPool: answer.split(''),
  riddleByLang: <String, String>{'fr': riddle},
  explanationByLang: const <String, String>{'fr': 'Explication test'},
  difficulty: 3,
  estimatedTimeS: 30,
  tags: const <String>[],
);

GameArgs _args({
  required LevelKind kind,
  required List<Devinette> devinettes,
  int distractorCount = 2,
}) {
  return GameArgs(
    devinette: devinettes.first,
    extraDevinettes: devinettes.sublist(1),
    mountainId: 'mnt_test',
    levelIndex: 3,
    config: LevelDifficultyConfig(
      difficultyTier: 3,
      wordLengthBucket: 3,
      timerSeconds: 45,
      caurisMultiplier: 1.6,
      distractorCount: distractorCount,
      kind: kind,
      isBoss: kind == LevelKind.blindBoss,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Monte la vue sur 375×667 @1x avec les overrides minimaux : prefs
  /// mockées (progression, seen-tracker, cap rewarded), montagnes vides
  /// (en-tête sans contexte), audio no-op, skin par défaut.
  Future<void> pumpGame(WidgetTester tester, GameArgs args) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          mountainsProvider.overrideWith((ref) async => <Mountain>[]),
          audioControllerProvider.overrideWith((ref) => _FakeAudio()),
          activePackThemeProvider.overrideWithValue(PackThemes.defaultTheme),
        ],
        child: MaterialApp(home: GameView(args: args)),
      ),
    );
    await tester.pump();
  }

  /// Démonte l'arbre pour libérer les timers du controller (obligatoire
  /// sous FakeAsync : un `Timer.periodic` encore actif fait échouer le test).
  Future<void> tearDownGame(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('duo : deux énigmes + deux rangées de cases, mots de 7 et 9 '
      'lettres, sans overflow sur 375×667', (tester) async {
    await pumpGame(
      tester,
      _args(
        kind: LevelKind.duo,
        devinettes: <Devinette>[
          _devinette('ATTIEKE', 'Énigme du premier mot'),
          _devinette('MAQUISARD', 'Énigme du second mot'),
        ],
      ),
    );

    expect(find.text('Énigme du premier mot'), findsOneWidget);
    expect(find.text('Énigme du second mot'), findsOneWidget);
    expect(find.byType(AnswerCells), findsNWidgets(2));
    expect(find.text('game.rafale_progress'), findsNothing);

    // Les rangées tiennent dans la largeur de l'écran.
    for (final row in find.byType(AnswerCells).evaluate()) {
      expect(row.size!.width, lessThanOrEqualTo(375));
    }
    expect(tester.takeException(), isNull);
    await tearDownGame(tester);
  });

  testWidgets("rafale : compteur « Mot 1/3 » sous l'énigme du mot en cours, "
      'sans overflow', (tester) async {
    await pumpGame(
      tester,
      _args(
        kind: LevelKind.rafale,
        devinettes: <Devinette>[
          _devinette('BALAFON', 'Énigme balafon'),
          _devinette('KEDJENOU', 'Énigme kedjenou'),
          _devinette('ALLOCO', 'Énigme alloco'),
        ],
      ),
    );

    expect(find.text('Énigme balafon'), findsOneWidget);
    expect(find.text('Énigme kedjenou'), findsNothing);
    expect(find.text('game.rafale_progress'), findsOneWidget);
    expect(find.byType(AnswerCells), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tearDownGame(tester);
  });

  testWidgets('boss aveugle : énigme lisible au départ, bouton « Relire » '
      'après 8 s, énigme de nouveau lisible après relecture', (tester) async {
    await pumpGame(
      tester,
      _args(
        kind: LevelKind.blindBoss,
        devinettes: <Devinette>[_devinette('KPLEKPLE', 'Énigme du gardien')],
        distractorCount: 3,
      ),
    );

    expect(find.text('Énigme du gardien'), findsOneWidget);
    expect(find.text('game.blind_reread'), findsNothing);

    await tester.pump(const Duration(seconds: 7));
    expect(find.text('game.blind_reread'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('game.blind_reread'), findsOneWidget);
    expect(find.text('game.blind_hidden'), findsOneWidget);

    await tester.tap(find.text('game.blind_reread'));
    await tester.pump();
    expect(find.text('game.blind_reread'), findsNothing);
    // Le fondu ramène le texte à pleine opacité.
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Énigme du gardien'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tearDownGame(tester);
  });
}
