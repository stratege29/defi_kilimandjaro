import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Service Dart qui wrappe les Cloud Functions admin déployées en
/// `europe-west1`.
///
/// Cf `functions/src/admin/` et `docs/backoffice_schema.md` §10.
///
/// Toutes les méthodes lèvent `AdminFunctionException` en cas d'erreur,
/// avec un code typé pour différencier les cas d'usage UI (validation,
/// permission, network).
class AdminFunctionsService {
  AdminFunctionsService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFunctions _functions;

  // ---- validatePackDraft -------------------------------------------------

  /// Valide le contenu d'un pack en draft. Retourne un rapport détaillé.
  /// N'écrit rien.
  Future<ValidatePackDraftResult> validatePackDraft({
    required String packId,
  }) async {
    final raw = await _call<Map<String, dynamic>>(
      'validatePackDraft',
      {'packId': packId},
    );
    return ValidatePackDraftResult.fromMap(raw);
  }

  // ---- publishPack -------------------------------------------------------

  /// Publie une nouvelle version du pack. Si `forceVersion` est null, la
  /// version est auto-incrémentée à partir de `meta.latest_published_version`.
  ///
  /// La CF appelle d'abord `validatePackDraft` en interne et lève
  /// `failed-precondition` si le pack n'est pas valide.
  Future<PublishPackResult> publishPack({
    required String packId,
    int? forceVersion,
  }) async {
    final raw = await _call<Map<String, dynamic>>('publishPack', {
      'packId': packId,
      if (forceVersion != null) 'forceVersion': forceVersion,
    });
    return PublishPackResult.fromMap(raw);
  }

  // ---- rollbackPack ------------------------------------------------------

  /// Repointe `content_packs/<id>` sur une version archivée.
  Future<RollbackPackResult> rollbackPack({
    required String packId,
    required int toVersion,
  }) async {
    final raw = await _call<Map<String, dynamic>>('rollbackPack', {
      'packId': packId,
      'toVersion': toVersion,
    });
    return RollbackPackResult.fromMap(raw);
  }

  // ---- upsertDevinette ---------------------------------------------------

  /// Crée ou met à jour une devinette unitaire (en draft).
  Future<UpsertDevinetteResult> upsertDevinette({
    required String packId,
    required Map<String, dynamic> devinette,
  }) async {
    final raw = await _call<Map<String, dynamic>>('upsertDevinette', {
      'packId': packId,
      'devinette': devinette,
    });
    return UpsertDevinetteResult.fromMap(raw);
  }

  // ---- bulkImportDevinettes ----------------------------------------------

  /// Import en masse (jusqu'à 1000 devinettes par appel).
  Future<BulkImportResult> bulkImportDevinettes({
    required String packId,
    required List<Map<String, dynamic>> devinettes,
    BulkImportMode mode = BulkImportMode.append,
  }) async {
    final raw = await _call<Map<String, dynamic>>('bulkImportDevinettes', {
      'packId': packId,
      'mode': mode.name,
      'devinettes': devinettes,
    });
    return BulkImportResult.fromMap(raw);
  }

  // ---- internal helpers --------------------------------------------------

  Future<T> _call<T>(String name, Map<String, dynamic> data) async {
    try {
      final result = await _functions.httpsCallable(name).call<dynamic>(data);
      final raw = result.data;
      if (raw is T) return raw;
      if (raw is Map<dynamic, dynamic>) {
        return Map<String, dynamic>.from(raw) as T;
      }
      throw AdminFunctionException(
        code: 'unknown-shape',
        message: 'Réponse de $name inattendue: ${raw.runtimeType}',
      );
    } on FirebaseFunctionsException catch (e) {
      throw AdminFunctionException.fromFirebase(e);
    }
  }
}

// ===========================================================================
// Exceptions typées
// ===========================================================================

class AdminFunctionException implements Exception {
  AdminFunctionException({
    required this.code,
    required this.message,
    this.details,
  });

  factory AdminFunctionException.fromFirebase(FirebaseFunctionsException e) {
    return AdminFunctionException(
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

  /// Vrai si l'erreur est `permission-denied` ou `unauthenticated`.
  bool get isAuth => code == 'permission-denied' || code == 'unauthenticated';

  /// Vrai si l'erreur est `failed-precondition` (typiquement validation).
  bool get isValidation => code == 'failed-precondition';

  /// Vrai si l'erreur est `invalid-argument` (input mal formé).
  bool get isInvalidArgument => code == 'invalid-argument';

  /// Si la CF a renvoyé `validationErrors` dans les `details`, les extrait.
  List<ValidationIssue> get validationErrors {
    final raw = details?['validationErrors'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => ValidationIssue.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  @override
  String toString() => 'AdminFunctionException($code): $message';
}

// ===========================================================================
// DTOs
// ===========================================================================

class ValidationIssue {
  const ValidationIssue({
    required this.deviId,
    required this.code,
    required this.message,
  });

  factory ValidationIssue.fromMap(Map<String, dynamic> m) {
    return ValidationIssue(
      deviId: m['deviId'] as String? ?? '?',
      code: m['code'] as String? ?? '?',
      message: m['message'] as String? ?? '',
    );
  }

  final String deviId;
  final String code;
  final String message;
}

class ValidatePackDraftResult {
  const ValidatePackDraftResult({
    required this.valid,
    required this.total,
    required this.errors,
    required this.warnings,
  });

  factory ValidatePackDraftResult.fromMap(Map<String, dynamic> m) {
    return ValidatePackDraftResult(
      valid: m['valid'] as bool? ?? false,
      total: (m['total'] as num?)?.toInt() ?? 0,
      errors: (m['errors'] as List<dynamic>?)
              ?.whereType<Map<dynamic, dynamic>>()
              .map((e) => ValidationIssue.fromMap(
                  Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      warnings: (m['warnings'] as List<dynamic>?)
              ?.whereType<Map<dynamic, dynamic>>()
              .map((e) => ValidationIssue.fromMap(
                  Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
    );
  }

  final bool valid;
  final int total;
  final List<ValidationIssue> errors;
  final List<ValidationIssue> warnings;
}

class PublishPackResult {
  const PublishPackResult({
    required this.packId,
    required this.version,
    required this.count,
    required this.hashSha256,
    required this.sizeBytes,
    required this.storagePath,
    required this.downloadUrl,
    required this.catalogVersion,
  });

  factory PublishPackResult.fromMap(Map<String, dynamic> m) {
    return PublishPackResult(
      packId: m['packId'] as String,
      version: (m['version'] as num).toInt(),
      count: (m['count'] as num).toInt(),
      hashSha256: m['hashSha256'] as String,
      sizeBytes: (m['sizeBytes'] as num).toInt(),
      storagePath: m['storagePath'] as String,
      downloadUrl: m['downloadUrl'] as String,
      catalogVersion: (m['catalogVersion'] as num).toInt(),
    );
  }

  final String packId;
  final int version;
  final int count;
  final String hashSha256;
  final int sizeBytes;
  final String storagePath;
  final String downloadUrl;
  final int catalogVersion;
}

class RollbackPackResult {
  const RollbackPackResult({
    required this.packId,
    required this.fromVersion,
    required this.toVersion,
    required this.catalogVersion,
    required this.hashSha256,
  });

  factory RollbackPackResult.fromMap(Map<String, dynamic> m) {
    return RollbackPackResult(
      packId: m['packId'] as String,
      fromVersion: (m['fromVersion'] as num).toInt(),
      toVersion: (m['toVersion'] as num).toInt(),
      catalogVersion: (m['catalogVersion'] as num).toInt(),
      hashSha256: m['hashSha256'] as String,
    );
  }

  final String packId;
  final int fromVersion;
  final int toVersion;
  final int catalogVersion;
  final String hashSha256;
}

class UpsertDevinetteResult {
  const UpsertDevinetteResult({
    required this.packId,
    required this.deviId,
    required this.created,
    required this.status,
  });

  factory UpsertDevinetteResult.fromMap(Map<String, dynamic> m) {
    return UpsertDevinetteResult(
      packId: m['packId'] as String,
      deviId: m['deviId'] as String,
      created: m['created'] as bool? ?? false,
      status: m['status'] as String? ?? 'draft',
    );
  }

  final String packId;
  final String deviId;
  final bool created;
  final String status;
}

enum BulkImportMode { append, replace }

class BulkImportResult {
  const BulkImportResult({
    required this.packId,
    required this.mode,
    required this.accepted,
    required this.rejected,
    required this.draftVersion,
  });

  factory BulkImportResult.fromMap(Map<String, dynamic> m) {
    return BulkImportResult(
      packId: m['packId'] as String,
      mode: m['mode'] as String,
      accepted: (m['accepted'] as num).toInt(),
      rejected: (m['rejected'] as List<dynamic>?)
              ?.whereType<Map<dynamic, dynamic>>()
              .map((r) => BulkImportRejection.fromMap(
                  Map<String, dynamic>.from(r)))
              .toList() ??
          const [],
      draftVersion: (m['draftVersion'] as num).toInt(),
    );
  }

  final String packId;
  final String mode;
  final int accepted;
  final List<BulkImportRejection> rejected;
  final int draftVersion;
}

class BulkImportRejection {
  const BulkImportRejection({
    required this.index,
    this.id,
    required this.error,
  });

  factory BulkImportRejection.fromMap(Map<String, dynamic> m) {
    return BulkImportRejection(
      index: (m['index'] as num).toInt(),
      id: m['id'] as String?,
      error: m['error'] as String? ?? '',
    );
  }

  final int index;
  final String? id;
  final String error;
}

// ===========================================================================
// Provider Riverpod
// ===========================================================================

final adminFunctionsServiceProvider = Provider<AdminFunctionsService>((ref) {
  return AdminFunctionsService();
});
