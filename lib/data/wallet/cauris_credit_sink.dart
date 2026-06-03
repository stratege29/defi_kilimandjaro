import 'package:defi_kilimandjaro/data/wallet/wallet_service.dart';

/// Port d'émission de crédits cauris vers le wallet serveur.
///
/// Découple `PlayerProgressNotifier` de la mécanique réseau : le notifier
/// enfile un crédit (montant + source connus atomiquement au moment du gain)
/// sans savoir comment il sera poussé. L'implémentation durable
/// (`CaurisCreditOutbox`) garantit l'exactly-once via une clé d'idempotence.
///
/// Pourquoi un port : garde la couche data testable (les tests injectent le
/// no-op) et conforme au principe d'inversion de dépendance — le notifier ne
/// dépend que de cette interface, jamais de Firebase Functions.
// ignore: one_member_abstracts
abstract class CaurisCreditSink {
  /// Enfile un crédit à pousser au wallet serveur. Fire-and-forget : ne
  /// bloque jamais le gain local (offline-first). [reference] est une trace
  /// d'audit optionnelle (ex: `matchId`, date du daily, productId IAP).
  void enqueue({
    required int amount,
    required CaurisCreditSource source,
    String? reference,
  });
}

/// Implémentation no-op — défaut du notifier et des tests.
///
/// N'émet rien : utilisée quand aucun wallet serveur n'est câblé (tests
/// unitaires de progression) pour que la logique de gain reste isolée du
/// réseau.
class NoopCaurisCreditSink implements CaurisCreditSink {
  const NoopCaurisCreditSink();

  @override
  void enqueue({
    required int amount,
    required CaurisCreditSource source,
    String? reference,
  }) {
    // Intentionnellement vide.
  }
}
