import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Service Dart qui wrappe les 4 Cloud Functions wallet déployées en
/// `europe-west1`.
///
/// Cf `functions/src/wallet/` et `docs/wallet_server_schema.md`.
///
/// Toutes les méthodes lèvent `WalletException` en cas d'erreur typée
/// pour permettre à l'UI de distinguer les cas (solde insuffisant, déjà
/// owned, wallet non bootstrapped, etc.).
class WalletService {
  WalletService({FirebaseFunctions? functions}) : _injected = functions;

  final FirebaseFunctions? _injected;
  FirebaseFunctions? _cached;

  /// Résolu **paresseusement** : `FirebaseFunctions.instanceFor` exige
  /// `Firebase.initializeApp`. Différer l'accès jusqu'au premier appel réseau
  /// permet de construire le service (et donc l'outbox + le notifier qui en
  /// dépend) sans Firebase initialisé — indispensable pour les tests widget
  /// qui montent l'arbre de providers sans backend.
  FirebaseFunctions get _functions =>
      _injected ??
      (_cached ??= FirebaseFunctions.instanceFor(region: 'europe-west1'));

  // ---- bootstrapWallet ----------------------------------------------------

  /// Crée le wallet serveur (ou retourne l'existant si déjà bootstrapped).
  /// À appeler une seule fois par user lors du premier sync post-Phase 4.
  Future<BootstrapWalletResult> bootstrap({
    required int cauris,
    required List<String> ownedPacks,
  }) async {
    final raw = await _call('bootstrapWallet', {
      'cauris': cauris,
      'ownedPacks': ownedPacks,
    });
    return BootstrapWalletResult.fromMap(raw);
  }

  // ---- unlockPack ---------------------------------------------------------

  /// Débloque un pack en débitant les cauris du wallet serveur.
  /// Throw `WalletException` :
  ///   - code `not-found` → packId pas dans catalog/index
  ///   - code `failed-precondition` → solde insuffisant OU pack pas visible
  ///   - code `already-exists` → pack déjà owned
  Future<UnlockPackResult> unlockPack({required String packId}) async {
    final raw = await _call('unlockPack', {'packId': packId});
    return UnlockPackResult.fromMap(raw);
  }

  // ---- creditCauris -------------------------------------------------------

  /// Crédite cauris au wallet (gains in-game).
  /// Validé serveur via cap `CAURIS_CREDIT_MAX_BY_SOURCE[source]`.
  ///
  /// [idempotencyKey] — clé UUID stable par crédit ; un retry avec la même
  /// clé est un no-op serveur (exactly-once). Indispensable pour l'outbox
  /// durable côté client. Cf `docs/wallet_server_schema.md` §3.
  Future<CreditCaurisResult> creditCauris({
    required int amount,
    required CaurisCreditSource source,
    String? reference,
    String? idempotencyKey,
  }) async {
    final raw = await _call('creditCauris', {
      'amount': amount,
      'source': source.name,
      if (reference != null) 'reference': reference,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    });
    return CreditCaurisResult.fromMap(raw);
  }

  // ---- syncWallet ---------------------------------------------------------

  /// Récupère l'état serveur courant pour pull-down client.
  /// Throw `WalletException(code: 'not-found')` si wallet pas bootstrapped.
  Future<SyncWalletResult> sync() async {
    final raw = await _call('syncWallet', const <String, dynamic>{});
    return SyncWalletResult.fromMap(raw);
  }

  // ---- internal -----------------------------------------------------------

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await _functions.httpsCallable(name).call<dynamic>(data);
      final raw = result.data;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      throw WalletException(
        code: 'unknown-shape',
        message: 'Réponse $name inattendue: ${raw.runtimeType}',
      );
    } on FirebaseFunctionsException catch (e) {
      throw WalletException.fromFirebase(e);
    }
  }
}

// ===========================================================================
// Exceptions typées
// ===========================================================================

class WalletException implements Exception {
  WalletException({required this.code, required this.message, this.details});

  factory WalletException.fromFirebase(FirebaseFunctionsException e) {
    return WalletException(
      code: e.code,
      message: e.message ?? 'Erreur inconnue',
      details: e.details is Map
          ? Map<String, dynamic>.from(e.details as Map)
          : null,
    );
  }

  final String code;
  final String message;
  final Map<String, dynamic>? details;

  bool get isInsufficientFunds =>
      code == 'failed-precondition' &&
      message.toLowerCase().contains('solde insuffisant');

  bool get isAlreadyOwned => code == 'already-exists';

  bool get isNotBootstrapped =>
      code == 'failed-precondition' &&
      message.toLowerCase().contains('wallet non initialisé');

  bool get isWalletNotFound => code == 'not-found';

  @override
  String toString() => 'WalletException($code): $message';
}

// ===========================================================================
// DTOs
// ===========================================================================

enum CaurisCreditSource {
  win,
  daily,
  rewarded,
  streak,
  iap,
  manual,
}

class BootstrapWalletResult {
  const BootstrapWalletResult({
    required this.created,
    required this.cauris,
    required this.ownedPacks,
    required this.version,
    required this.capped,
  });

  factory BootstrapWalletResult.fromMap(Map<String, dynamic> m) {
    return BootstrapWalletResult(
      created: m['created'] as bool? ?? false,
      cauris: (m['cauris'] as num).toInt(),
      ownedPacks: (m['ownedPacks'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      version: (m['version'] as num).toInt(),
      capped: m['capped'] as bool? ?? false,
    );
  }

  final bool created;
  final int cauris;
  final List<String> ownedPacks;
  final int version;
  final bool capped;
}

class UnlockPackResult {
  const UnlockPackResult({
    required this.packId,
    required this.cauris,
    required this.ownedPacks,
    required this.version,
    required this.cost,
  });

  factory UnlockPackResult.fromMap(Map<String, dynamic> m) {
    return UnlockPackResult(
      packId: m['packId'] as String,
      cauris: (m['cauris'] as num).toInt(),
      ownedPacks: (m['ownedPacks'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      version: (m['version'] as num).toInt(),
      cost: (m['cost'] as num).toInt(),
    );
  }

  final String packId;
  final int cauris;
  final List<String> ownedPacks;
  final int version;
  final int cost;
}

class CreditCaurisResult {
  const CreditCaurisResult({
    required this.cauris,
    required this.version,
    required this.amount,
  });

  factory CreditCaurisResult.fromMap(Map<String, dynamic> m) {
    return CreditCaurisResult(
      cauris: (m['cauris'] as num).toInt(),
      version: (m['version'] as num).toInt(),
      amount: (m['amount'] as num).toInt(),
    );
  }

  final int cauris;
  final int version;
  final int amount;
}

class SyncWalletResult {
  const SyncWalletResult({
    required this.cauris,
    required this.ownedPacks,
    required this.version,
    required this.updatedAtMs,
  });

  factory SyncWalletResult.fromMap(Map<String, dynamic> m) {
    return SyncWalletResult(
      cauris: (m['cauris'] as num).toInt(),
      ownedPacks: (m['ownedPacks'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      version: (m['version'] as num).toInt(),
      updatedAtMs: (m['updatedAtMs'] as num?)?.toInt(),
    );
  }

  final int cauris;
  final List<String> ownedPacks;
  final int version;
  final int? updatedAtMs;
}

// ===========================================================================
// Provider Riverpod
// ===========================================================================

final walletServiceProvider = Provider<WalletService>((ref) {
  return WalletService();
});
