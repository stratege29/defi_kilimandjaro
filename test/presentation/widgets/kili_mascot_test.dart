import 'package:defi_kilimandjaro/presentation/widgets/kili_mascot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool disableAnimations = false}) {
  return ProviderScope(
    // Pas de runtime natif Rive en test : on force le chemin de repli.
    overrides: [kiliRiveFileProvider.overrideWith((ref) async => null)],
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(home: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('sans Rive : rig pur Flutter à deux calques', (tester) async {
    await tester.pumpWidget(_host(const KiliMascot()));
    await tester.pump();

    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets("garde l'emprise du PNG (ratio 757/1024)", (tester) async {
    await tester.pumpWidget(_host(const KiliMascot(size: 200)));
    await tester.pump();

    expect(tester.getSize(find.byType(KiliMascot)), const Size(200, 200 * 757 / 1024));
  });

  testWidgets('animations désactivées : image fixe unique', (tester) async {
    await tester.pumpWidget(
      _host(const KiliMascot(), disableAnimations: true),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('nod/cheer/tap sur le repli ne lèvent rien', (tester) async {
    final kili = KiliController();
    await tester.pumpWidget(_host(KiliMascot(controller: kili)));
    await tester.pump();

    kili
      ..nod()
      ..cheer();
    await tester.tap(find.byType(KiliMascot));
    await tester.pump(const Duration(milliseconds: 800));

    expect(tester.takeException(), isNull);
  });

  testWidgets('contrôleur détaché après démontage : no-op', (tester) async {
    final kili = KiliController();
    await tester.pumpWidget(_host(KiliMascot(controller: kili)));
    await tester.pump();
    await tester.pumpWidget(_host(const SizedBox()));

    kili
      ..nod()
      ..cheer();
    expect(tester.takeException(), isNull);
  });
}
