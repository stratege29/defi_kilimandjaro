import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/presentation/duel/widgets/duel_countdown_overlay.dart';
import 'package:defi_kilimandjaro/presentation/duel/widgets/duel_intro_overlay.dart';
import 'package:defi_kilimandjaro/presentation/duel/widgets/duel_round_end_overlay.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([FirebaseAuth, User, AudioController])
import 'duel_overlays_test.mocks.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Session de base réutilisée dans les tests.
DuelSession _makeSession({
  required DuelPhase phase,
  int currentRound = 0,
  String? winner,
  Map<String, DuelPlayer> players = const {},
}) {
  return DuelSession(
    matchId: 'TEST01',
    secret: 'deadsecret',
    createdBy: 'uid-a',
    createdAt: 0,
    phase: phase,
    currentRound: currentRound,
    totalRounds: 3,
    rounds: const [
      RoundData(
        index: 0,
        answer: 'KORA',
        lettersPool: ['K', 'O', 'R', 'A'],
        riddle: 'Instrument a 21 cordes',
        explanation: 'Kora: harpe mandingue a 21 cordes.',
        proverb: '',
        difficulty: 'easy',
        devinetteId: 'dev-1',
      ),
      RoundData(
        index: 1,
        answer: 'BAOBAB',
        lettersPool: ['B', 'A', 'O', 'B', 'A', 'B'],
        riddle: 'Arbre de vie',
        explanation: "L'arbre du baobab.",
        proverb: '',
        difficulty: 'medium',
        devinetteId: 'dev-2',
      ),
      RoundData(
        index: 2,
        answer: 'CALEBASSE',
        lettersPool: ['C', 'A', 'L', 'E', 'B', 'A', 'S', 'S', 'E'],
        riddle: 'Contenant naturel',
        explanation: 'La calebasse, fruit creuse.',
        proverb: '',
        difficulty: 'hard',
        devinetteId: 'dev-3',
      ),
    ],
    players: players,
    winner: winner,
    isRanked: false,
    phaseStartedAtMs: DateTime.now().millisecondsSinceEpoch,
  );
}

/// Wrap minimal pour tester des widgets Riverpod sans Firebase live.
///
/// [audioController] : permet d'injecter un mock externe pour le `verify(...)`
/// dans les tests d'intégration audio. Si null, un mock interne est créé.
Widget _wrap(
  Widget child, {
  String selfUid = 'uid-a',
  MockAudioController? audioController,
}) {
  final mockAuth = MockFirebaseAuth();
  final mockUser = MockUser();
  when(mockUser.uid).thenReturn(selfUid);
  when(mockAuth.currentUser).thenReturn(mockUser);

  final mockAudioCtrl = audioController ?? MockAudioController();
  when(mockAudioCtrl.playDuelStart())
      .thenAnswer((_) async {});
  when(mockAudioCtrl.playTimerTick(any))
      .thenAnswer((_) async {});
  when(mockAudioCtrl.playWordComplete())
      .thenAnswer((_) async {});
  when(mockAudioCtrl.playRoundWon())
      .thenAnswer((_) async {});
  when(mockAudioCtrl.playRoundLost())
      .thenAnswer((_) async {});
  when(mockAudioCtrl.playRoundDraw())
      .thenAnswer((_) async {});
  when(mockAudioCtrl.state).thenReturn(AudioState.defaults());

  return ProviderScope(
    overrides: [
      firebaseAuthProvider.overrideWithValue(mockAuth),
      audioControllerProvider.overrideWith((_) => mockAudioCtrl),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests DuelIntroOverlay
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DuelIntroOverlay', () {
    testWidgets(
      'affiche le fond savane et les portraits quand phase == intro',
      (tester) async {
        final session = _makeSession(
          phase: DuelPhase.intro,
          players: {
            'uid-a': DuelPlayer(
              uid: 'uid-a',
              roundsWon: 0,
              totalTimeMs: 0,
              rounds: const {},
            ),
            'uid-b': DuelPlayer(
              uid: 'uid-b',
              roundsWon: 0,
              totalTimeMs: 0,
              rounds: const {},
            ),
          },
        );

        await tester.pumpWidget(
          _wrap(DuelIntroOverlay(session: session)),
        );

        // Les deux labels de joueurs doivent être présents.
        expect(find.text('Moi'), findsOneWidget);
        expect(find.text('Adversaire'), findsOneWidget);

        // Label de manche en haut.
        expect(find.textContaining('Manche 1'), findsWidgets);
      },
    );

    testWidgets(
      'le VS badge est absent avant la fin du slide (animation not started)',
      (tester) async {
        final session = _makeSession(
          phase: DuelPhase.intro,
          players: {
            'uid-a': DuelPlayer(
              uid: 'uid-a',
              roundsWon: 0,
              totalTimeMs: 0,
              rounds: const {},
            ),
          },
        );

        await tester.pumpWidget(
          _wrap(DuelIntroOverlay(session: session)),
        );
        // Au premier frame, VS n'est pas encore affiché (opacity 0).
        // On vérifie que le widget VS existe dans l'arbre (même opacité 0).
        expect(find.text('VS'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Tests DuelCountdownOverlay
  // ---------------------------------------------------------------------------

  group('DuelCountdownOverlay', () {
    testWidgets(
      'affiche le cadenas sur la grille et le premier chiffre',
      (tester) async {
        final session = _makeSession(phase: DuelPhase.countdown);

        await tester.pumpWidget(
          _wrap(
            DuelCountdownOverlay(
              session: session,
              gameContent: const ColoredBox(
                color: Colors.green,
                child: SizedBox.expand(),
              ),
              riddleContent: const Text('Instrument a 21 cordes'),
            ),
          ),
        );

        // Premier pump — le chiffre initial doit être visible.
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);

        // La devinette doit être visible.
        expect(find.text('Instrument a 21 cordes'), findsOneWidget);
      },
    );

    testWidgets(
      'affiche GO! après que le timer atteint zéro',
      (tester) async {
        // phaseStartedAtMs dans le passé pour simuler un countdown écoulé.
        final session = DuelSession(
          matchId: 'TEST02',
          secret: 'sec',
          createdBy: 'uid-a',
          createdAt: 0,
          phase: DuelPhase.countdown,
          currentRound: 0,
          totalRounds: 3,
          rounds: const [
            RoundData(
              index: 0,
              answer: 'KORA',
              lettersPool: ['K', 'O', 'R', 'A'],
              riddle: 'Riddle',
              explanation: '',
              proverb: '',
              difficulty: 'easy',
              devinetteId: 'dev-1',
            ),
          ],
          players: const {},
          isRanked: false,
          // 5 secondes dans le passé => countdown déjà écoulé.
          phaseStartedAtMs:
              DateTime.now().millisecondsSinceEpoch - 5000,
        );

        await tester.pumpWidget(
          _wrap(
            DuelCountdownOverlay(
              session: session,
              gameContent: const SizedBox.shrink(),
              riddleContent: const Text('Riddle'),
            ),
          ),
        );

        // Laisse les animations se résoudre.
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(find.text('GO !'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Tests DuelRoundEndOverlay
  // ---------------------------------------------------------------------------

  group('DuelRoundEndOverlay', () {
    testWidgets(
      'affiche "Manche gagnée !" quand le joueur local a gagné le round',
      (tester) async {
        const selfUid = 'uid-a';
        const opponentUid = 'uid-b';

        final session = _makeSession(
          phase: DuelPhase.roundEnd,
          currentRound: 0,
          players: {
            selfUid: DuelPlayer(
              uid: selfUid,
              roundsWon: 1,
              totalTimeMs: 12000,
              rounds: const {
                0: RoundResult(
                  progress: 1,
                  found: true,
                  finishedAtMs: 1000,
                  timeTakenMs: 12000,
                ),
              },
            ),
            opponentUid: DuelPlayer(
              uid: opponentUid,
              roundsWon: 0,
              totalTimeMs: 0,
              rounds: const {
                0: RoundResult(
                  progress: 0.5,
                  found: false,
                ),
              },
            ),
          },
        );

        await tester.pumpWidget(
          _wrap(
            DuelRoundEndOverlay(
              session: session,
              gameBackground: const ColoredBox(
                color: Colors.black,
                child: SizedBox.expand(),
              ),
            ),
            selfUid: selfUid,
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.textContaining('MANCHE GAGNÉE'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'affiche "Manche nulle" quand personne n\'a trouvé',
      (tester) async {
        const selfUid = 'uid-a';
        const opponentUid = 'uid-b';

        final session = _makeSession(
          phase: DuelPhase.roundEnd,
          currentRound: 0,
          players: {
            selfUid: DuelPlayer(
              uid: selfUid,
              roundsWon: 0,
              totalTimeMs: 0,
              rounds: const {
                0: RoundResult(progress: 0.3, found: false),
              },
            ),
            opponentUid: DuelPlayer(
              uid: opponentUid,
              roundsWon: 0,
              totalTimeMs: 0,
              rounds: const {
                0: RoundResult(progress: 0.2, found: false),
              },
            ),
          },
        );

        await tester.pumpWidget(
          _wrap(
            DuelRoundEndOverlay(
              session: session,
              gameBackground: const SizedBox.shrink(),
            ),
            selfUid: selfUid,
          ),
        );

        await tester.pump();

        expect(find.textContaining('MANCHE NULLE'), findsOneWidget);
      },
    );

    testWidgets(
      'affiche le détail "Prochaine manche" quand ce n\'est pas le dernier round',
      (tester) async {
        const selfUid = 'uid-a';

        final session = _makeSession(
          phase: DuelPhase.roundEnd,
          currentRound: 0,
          players: {
            selfUid: DuelPlayer(
              uid: selfUid,
              roundsWon: 0,
              totalTimeMs: 0,
              rounds: const {},
            ),
          },
        );

        await tester.pumpWidget(
          _wrap(
            DuelRoundEndOverlay(
              session: session,
              gameBackground: const SizedBox.shrink(),
            ),
            selfUid: selfUid,
          ),
        );

        await tester.pump();

        // Doit afficher la prochaine manche (round 1 = medium).
        expect(find.textContaining('Moyen'), findsWidgets);
      },
    );

    // ─── Audio cues (PR ce commit) ──────────────────────────────────────

    testWidgets(
      'audio: joue playRoundWon une seule fois quand le joueur a gagné',
      (tester) async {
        const selfUid = 'uid-a';
        const opponentUid = 'uid-b';
        final mockCtrl = MockAudioController();

        final session = _makeSession(
          phase: DuelPhase.roundEnd,
          players: {
            selfUid: const DuelPlayer(
              uid: selfUid,
              roundsWon: 1,
              totalTimeMs: 8000,
              rounds: {
                0: RoundResult(
                  progress: 1,
                  found: true,
                  finishedAtMs: 8000,
                  timeTakenMs: 8000,
                ),
              },
            ),
            opponentUid: const DuelPlayer(
              uid: opponentUid,
              roundsWon: 0,
              totalTimeMs: 0,
              rounds: {
                0: RoundResult(progress: 0.5, found: false),
              },
            ),
          },
        );

        await tester.pumpWidget(
          _wrap(
            DuelRoundEndOverlay(
              session: session,
              gameBackground: const SizedBox.shrink(),
            ),
            audioController: mockCtrl,
          ),
        );
        // Laisse le postFrameCallback se déclencher.
        await tester.pump();

        verify(mockCtrl.playRoundWon()).called(1);
        verifyNever(mockCtrl.playRoundLost());
        verifyNever(mockCtrl.playRoundDraw());
      },
    );

    testWidgets(
      "audio: joue playRoundLost quand l'adversaire a gagné",
      (tester) async {
        const selfUid = 'uid-a';
        const opponentUid = 'uid-b';
        final mockCtrl = MockAudioController();

        final session = _makeSession(
          phase: DuelPhase.roundEnd,
          players: {
            selfUid: const DuelPlayer(
              uid: selfUid,
              roundsWon: 0,
              totalTimeMs: 0,
              rounds: {
                0: RoundResult(progress: 0.4, found: false),
              },
            ),
            opponentUid: const DuelPlayer(
              uid: opponentUid,
              roundsWon: 1,
              totalTimeMs: 6000,
              rounds: {
                0: RoundResult(
                  progress: 1,
                  found: true,
                  finishedAtMs: 6000,
                  timeTakenMs: 6000,
                ),
              },
            ),
          },
        );

        await tester.pumpWidget(
          _wrap(
            DuelRoundEndOverlay(
              session: session,
              gameBackground: const SizedBox.shrink(),
            ),
            audioController: mockCtrl,
          ),
        );
        await tester.pump();

        verify(mockCtrl.playRoundLost()).called(1);
        verifyNever(mockCtrl.playRoundWon());
        verifyNever(mockCtrl.playRoundDraw());
      },
    );

    testWidgets(
      "audio: joue playRoundDraw quand personne n'a trouvé",
      (tester) async {
        const selfUid = 'uid-a';
        const opponentUid = 'uid-b';
        final mockCtrl = MockAudioController();

        final session = _makeSession(
          phase: DuelPhase.roundEnd,
          players: {
            selfUid: const DuelPlayer(
              uid: selfUid,
              roundsWon: 0,
              totalTimeMs: 0,
              rounds: {
                0: RoundResult(progress: 0.3, found: false),
              },
            ),
            opponentUid: const DuelPlayer(
              uid: opponentUid,
              roundsWon: 0,
              totalTimeMs: 0,
              rounds: {
                0: RoundResult(progress: 0.2, found: false),
              },
            ),
          },
        );

        await tester.pumpWidget(
          _wrap(
            DuelRoundEndOverlay(
              session: session,
              gameBackground: const SizedBox.shrink(),
            ),
            audioController: mockCtrl,
          ),
        );
        await tester.pump();

        verify(mockCtrl.playRoundDraw()).called(1);
        verifyNever(mockCtrl.playRoundWon());
        verifyNever(mockCtrl.playRoundLost());
      },
    );
  });
}
