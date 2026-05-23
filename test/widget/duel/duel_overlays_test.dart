import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/player_profile.dart';
import 'package:defi_kilimandjaro/presentation/duel/widgets/duel_intro_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const selfUid = 'self-uid-AAAAA';
  const opponentUid = 'opp-uid-BBBBB';

  PlayerProfile profile({
    required String uid,
    String? displayName,
    int elo = 1000,
    String? avatarId,
  }) {
    return PlayerProfile(
      uid: uid,
      elo: elo,
      peakElo: elo,
      totalDuels: 0,
      wins: 0,
      losses: 0,
      displayName: displayName,
      avatarId: avatarId,
    );
  }

  Widget harness({
    required List<Override> overrides,
    bool isRanked = true,
    String? opponent = opponentUid,
  }) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(
          body: DuelIntroOverlay(
            selfUid: selfUid,
            opponentUid: opponent,
            isRanked: isRanked,
          ),
        ),
      ),
    );
  }

  testWidgets('affiche pseudo + ELO depuis le ProfileRepository (ranked)',
      (tester) async {
    await tester.pumpWidget(
      harness(
        overrides: [
          playerProfileProvider(selfUid).overrideWith(
            (ref) => Stream.value(
              profile(uid: selfUid, displayName: 'Yao', elo: 1250),
            ),
          ),
          playerProfileProvider(opponentUid).overrideWith(
            (ref) => Stream.value(
              profile(uid: opponentUid, displayName: 'Akwaba', elo: 1430),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Moi'), findsOneWidget);
    expect(find.text('Adversaire'), findsOneWidget);
    expect(find.text('Yao'), findsOneWidget);
    expect(find.text('Akwaba'), findsOneWidget);
    expect(find.text('1250 m'), findsOneWidget);
    expect(find.text('1430 m'), findsOneWidget);

    expect(find.text('Y'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets("masque l'ELO en mode non-ranked", (tester) async {
    await tester.pumpWidget(
      harness(
        isRanked: false,
        overrides: [
          playerProfileProvider(selfUid).overrideWith(
            (ref) => Stream.value(
              profile(uid: selfUid, displayName: 'Yao', elo: 1250),
            ),
          ),
          playerProfileProvider(opponentUid).overrideWith(
            (ref) => Stream.value(
              profile(uid: opponentUid, displayName: 'Akwaba', elo: 1430),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Yao'), findsOneWidget);
    expect(find.text('Akwaba'), findsOneWidget);
    expect(find.text('1250 m'), findsNothing);
    expect(find.text('1430 m'), findsNothing);
  });

  testWidgets('fallback "Joueur" + initiale UID si profil null',
      (tester) async {
    await tester.pumpWidget(
      harness(
        overrides: [
          playerProfileProvider(selfUid)
              .overrideWith((ref) => Stream<PlayerProfile?>.value(null)),
          playerProfileProvider(opponentUid)
              .overrideWith((ref) => Stream<PlayerProfile?>.value(null)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Joueur'), findsNWidgets(2));
    expect(find.text('S'), findsOneWidget);
    expect(find.text('O'), findsOneWidget);
  });

  testWidgets('fallback si displayName est vide', (tester) async {
    await tester.pumpWidget(
      harness(
        overrides: [
          playerProfileProvider(selfUid).overrideWith(
            (ref) => Stream.value(profile(uid: selfUid, displayName: '')),
          ),
          playerProfileProvider(opponentUid).overrideWith(
            (ref) => Stream.value(profile(uid: opponentUid)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Joueur'), findsNWidgets(2));
    expect(find.text('S'), findsOneWidget);
    expect(find.text('O'), findsOneWidget);
  });

  testWidgets("placeholder \"En attente...\" si pas encore d'adversaire",
      (tester) async {
    await tester.pumpWidget(
      harness(
        opponent: null,
        overrides: [
          playerProfileProvider(selfUid).overrideWith(
            (ref) => Stream.value(
              profile(uid: selfUid, displayName: 'Yao', elo: 1250),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Yao'), findsOneWidget);
    expect(find.text('En attente...'), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);
  });

  testWidgets('skeleton pendant le chargement initial', (tester) async {
    await tester.pumpWidget(
      harness(
        overrides: [
          playerProfileProvider(selfUid).overrideWith(
            (ref) => const Stream<PlayerProfile?>.empty(),
          ),
          playerProfileProvider(opponentUid).overrideWith(
            (ref) => const Stream<PlayerProfile?>.empty(),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Moi'), findsOneWidget);
    expect(find.text('Adversaire'), findsOneWidget);
    expect(find.text('Joueur'), findsNothing);
    expect(find.text('VS'), findsOneWidget);
  });

  testWidgets("rend l'asset avatar quand avatarId est défini", (tester) async {
    // Suppress asset-load errors in the test (PNGs not yet delivered by
    // designer — errorBuilder will kick in, but we verify the Image widget
    // IS instantiated with the right path).
    FlutterError.onError = (_) {};

    await tester.pumpWidget(
      harness(
        overrides: [
          playerProfileProvider(selfUid).overrideWith(
            (ref) => Stream.value(
              profile(
                uid: selfUid,
                displayName: 'Yao',
                elo: 1250,
                avatarId: 'griot_classique',
              ),
            ),
          ),
          playerProfileProvider(opponentUid).overrideWith(
            (ref) => Stream.value(
              profile(
                uid: opponentUid,
                displayName: 'Akwaba',
                elo: 1430,
                avatarId: 'panthere_royale',
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Les pseudos restent affichés.
    expect(find.text('Yao'), findsOneWidget);
    expect(find.text('Akwaba'), findsOneWidget);

    // Vérifier que les SvgPicture sont créés avec les bons assets —
    // peu importe si le SVG parse ou tombe sur placeholderBuilder.
    expect(
      find.byWidgetPredicate(
        (w) => w is SvgPicture && w.toString().contains('griot_classique.svg'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is SvgPicture && w.toString().contains('panthere_royale.svg'),
      ),
      findsOneWidget,
    );
  });

  testWidgets("avatarId inconnu (legacy) retombe sur l'initiale",
      (tester) async {
    await tester.pumpWidget(
      harness(
        overrides: [
          playerProfileProvider(selfUid).overrideWith(
            (ref) => Stream.value(
              profile(
                uid: selfUid,
                displayName: 'Yao',
                avatarId: 'avatar_supprime_v1',
              ),
            ),
          ),
          playerProfileProvider(opponentUid).overrideWith(
            (ref) => Stream.value(
              profile(uid: opponentUid, displayName: 'Akwaba'),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // L'id n'existe pas → AvatarCatalog.byId == null → fallback initiale.
    expect(find.text('Y'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
  });
}
