import 'package:cloud_functions/cloud_functions.dart';
import 'package:defi_kilimandjaro/core/utils/network_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isDeviceNetworkError', () {
    test('true pour le message iOS "data connection not allowed"', () {
      final error = FirebaseFunctionsException(
        code: 'unknown',
        message: 'A data connection is not currently allowed.',
      );
      expect(isDeviceNetworkError(error), isTrue);
    });

    test('true pour code unavailable', () {
      final error = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Service indisponible',
      );
      expect(isDeviceNetworkError(error), isTrue);
    });

    test('true pour code deadline-exceeded', () {
      final error = FirebaseFunctionsException(
        code: 'deadline-exceeded',
        message: 'Timeout',
      );
      expect(isDeviceNetworkError(error), isTrue);
    });

    test('false pour une erreur métier serveur', () {
      final error = FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Mot incorrect',
      );
      expect(isDeviceNetworkError(error), isFalse);
    });

    test('false pour une erreur inattendue générique', () {
      expect(isDeviceNetworkError(StateError('Réponse invalide')), isFalse);
    });
  });
}
