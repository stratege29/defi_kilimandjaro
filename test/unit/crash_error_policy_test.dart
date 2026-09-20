import 'package:defi_kilimandjaro/core/crash_error_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isNonFatalFlutterError', () {
    test('erreur silent → non-fatal', () {
      final details = FlutterErrorDetails(
        exception: Exception('Unable to load asset'),
        silent: true,
      );
      expect(isNonFatalFlutterError(details), isTrue);
    });

    test('erreur du service image → non-fatal même si non silent', () {
      final details = FlutterErrorDetails(
        exception: Exception('Unable to load asset'),
        library: imageResourceServiceLibrary,
      );
      expect(isNonFatalFlutterError(details), isTrue);
    });

    test('erreur classique (widgets library) → fatal', () {
      final details = FlutterErrorDetails(
        exception: StateError('boom'),
        library: 'widgets library',
      );
      expect(isNonFatalFlutterError(details), isFalse);
    });
  });
}
