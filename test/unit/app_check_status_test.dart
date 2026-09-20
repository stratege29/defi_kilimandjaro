import 'package:defi_kilimandjaro/data/firebase/app_check_status.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyAppCheckError', () {
    test('erreur -9 Play Integrity → playStoreOutdated', () {
      final error = FirebaseException(
        plugin: 'firebase_app_check',
        code: 'unknown',
        message: '-9: Integrity API error (-9): Binding to the service in '
            'the Play Store has failed. This can be due to having an old '
            'Play Store version installed on the device.',
      );
      expect(
        classifyAppCheckError(error),
        AppCheckFailure.playStoreOutdated,
      );
    });

    test('code symbolique CANNOT_BIND_TO_SERVICE → playStoreOutdated', () {
      expect(
        classifyAppCheckError(StateError('CANNOT_BIND_TO_SERVICE')),
        AppCheckFailure.playStoreOutdated,
      );
    });

    test('403 App attestation failed → attestationRejected', () {
      final error = FirebaseException(
        plugin: 'firebase_app_check',
        code: 'unknown',
        message: 'Error returned from API. code: 403 body: '
            'App attestation failed.',
      );
      expect(
        classifyAppCheckError(error),
        AppCheckFailure.attestationRejected,
      );
    });

    test('hôte injoignable → offline', () {
      final error = FirebaseException(
        plugin: 'firebase_app_check',
        code: 'unknown',
        message: 'Unable to resolve host "firebaseappcheck.googleapis.com": '
            'No address associated with hostname',
      );
      expect(classifyAppCheckError(error), AppCheckFailure.offline);
    });

    test('token null → unknown', () {
      expect(
        classifyAppCheckError(
          StateError('getTokenResult returned null (no token available)'),
        ),
        AppCheckFailure.unknown,
      );
    });
  });

  test('appCheckFailureProvider reflète AppCheckHealth.lastFailure', () {
    AppCheckHealth.lastFailure = AppCheckFailure.playStoreOutdated;
    addTearDown(() => AppCheckHealth.lastFailure = AppCheckFailure.none);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(appCheckFailureProvider),
      AppCheckFailure.playStoreOutdated,
    );
  });
}
