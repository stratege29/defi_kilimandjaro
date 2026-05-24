import 'package:flutter/widgets.dart';

/// État de la synchronisation OTA exposée à l'UI via `manifestSyncStateProvider`.
///
/// Transitions valides :
/// - `Idle` → `Syncing` (tap sur le bouton refresh)
/// - `Syncing` → `Syncing` (progression intermédiaire)
/// - `Syncing` → `Success` (sync terminée sans crash)
/// - `Syncing` → `Error` (exception non-récupérable)
/// - `Success` / `Error` → `Syncing` (relance manuelle)
sealed class SyncState {
  const SyncState();
}

class SyncStateIdle extends SyncState {
  const SyncStateIdle();
}

class SyncStateSyncing extends SyncState {
  const SyncStateSyncing({required this.progress, required this.currentPackId});

  /// Fraction 0..1 de la progression globale (nbPacksTraités / nbPacksTotal).
  final double progress;

  /// Identifiant du pack en cours de download, ou `null` si on n'est pas
  /// encore dans la boucle (fetch manifests).
  final String? currentPackId;
}

class SyncStateSuccess extends SyncState {
  const SyncStateSuccess(this.report);
  final SyncReport report;
}

class SyncStateError extends SyncState {
  const SyncStateError(this.message);
  final String message;
}

/// Snapshot émis à chaque tour de boucle dans `ManifestSyncService.refresh`.
class SyncProgress {
  const SyncProgress({
    required this.packIndex,
    required this.packTotal,
    required this.currentPackId,
  });

  /// 1-indexed nombre de packs traités (skip ou update inclus).
  final int packIndex;
  final int packTotal;
  final String currentPackId;

  double get overallFraction => packTotal == 0 ? 0 : packIndex / packTotal;
}

/// Rapport final d'une sync, retourné par `ManifestSyncService.refresh`.
class SyncReport {
  const SyncReport({
    required this.updated,
    required this.skipped,
    required this.errors,
    this.abortedByMemoryPressure = false,
  });

  /// Nombre de packs effectivement re-téléchargés et écrits en cache.
  final int updated;

  /// Nombre de packs déjà à jour (idempotence — pas de network call).
  final int skipped;

  /// Nombre de packs qui ont échoué (download, hash, parse).
  final int errors;

  /// `true` si la boucle a été interrompue par `didHaveMemoryPressure` iOS.
  /// La sync est partielle ; l'utilisateur peut retenter plus tard.
  final bool abortedByMemoryPressure;

  bool get hasChanges => updated > 0;
  int get totalProcessed => updated + skipped + errors;
}

/// Abstraction sur la pression mémoire iOS/Android. Injectée dans
/// `ManifestSyncService` pour permettre des tests sans `WidgetsBinding`.
abstract class MemoryPressureSignal {
  bool get isUnderPressure;

  /// Réinitialise le flag avant une nouvelle sync — un warning passé
  /// pendant le boot ne doit pas empoisonner les syncs ultérieures.
  void reset();
  void dispose();
}

/// Implémentation par défaut adossée à `WidgetsBindingObserver.didHaveMemoryPressure`.
/// iOS appelle ce hook quand le système est sous pression — on flippe le
/// flag pour que la boucle de sync abort proprement au prochain pack.
class WidgetsBindingMemoryPressureSignal
    with WidgetsBindingObserver
    implements MemoryPressureSignal {
  WidgetsBindingMemoryPressureSignal() {
    WidgetsBinding.instance.addObserver(this);
  }

  bool _underPressure = false;

  @override
  bool get isUnderPressure => _underPressure;

  @override
  void reset() {
    _underPressure = false;
  }

  @override
  void didHaveMemoryPressure() {
    _underPressure = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
