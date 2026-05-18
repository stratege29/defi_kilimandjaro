// Controller Riverpod pour le widget `PackImageCard` — gère le pipeline
// pick → optimize → upload sans BuildContext.
// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kilimandjaro_admin/src/packs/data/pack_image_optimizer.dart';
import 'package:kilimandjaro_admin/src/packs/data/pack_image_uploader.dart';

/// État de la carte d'upload d'image — machine à 4 phases :
/// `idle` → `optimizing` → `previewing` → `uploading` → `idle` (success) /
/// `idle` (with errorMessage).
enum PackImagePhase { idle, optimizing, previewing, uploading }

class PackImageState {
  const PackImageState({
    this.phase = PackImagePhase.idle,
    this.preview,
    this.errorMessage,
    this.lastUploadedSizeBytes,
  });

  final PackImagePhase phase;
  final OptimizedImage? preview;
  final String? errorMessage;
  final int? lastUploadedSizeBytes;

  bool get isBusy =>
      phase == PackImagePhase.optimizing || phase == PackImagePhase.uploading;

  PackImageState copyWith({
    PackImagePhase? phase,
    OptimizedImage? preview,
    String? errorMessage,
    int? lastUploadedSizeBytes,
    bool clearPreview = false,
    bool clearError = false,
    bool clearLastUploaded = false,
  }) {
    return PackImageState(
      phase: phase ?? this.phase,
      preview: clearPreview ? null : (preview ?? this.preview),
      errorMessage:
          clearError ? null : (errorMessage ?? this.errorMessage),
      lastUploadedSizeBytes: clearLastUploaded
          ? null
          : (lastUploadedSizeBytes ?? this.lastUploadedSizeBytes),
    );
  }
}

/// Controller — pas de `BuildContext`, on retourne les erreurs via `state`.
class PackImageController extends StateNotifier<PackImageState> {
  PackImageController(this._ref) : super(const PackImageState());

  final Ref _ref;

  /// Ouvre le file picker, valide le format, lance la pipeline d'optimisation.
  Future<void> pickAndOptimize() async {
    state = state.copyWith(
      phase: PackImagePhase.optimizing,
      clearError: true,
      clearPreview: true,
    );

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        // Cancel utilisateur — retour idle silencieux.
        state = state.copyWith(phase: PackImagePhase.idle);
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        state = state.copyWith(
          phase: PackImagePhase.idle,
          errorMessage:
              'Impossible de lire le fichier (pas de bytes — restriction '
              'navigateur ?).',
        );
        return;
      }

      final optimizer = _ref.read(packImageOptimizerProvider);
      final optimized = await optimizer.optimize(Uint8List.fromList(bytes));

      state = PackImageState(
        phase: PackImagePhase.previewing,
        preview: optimized,
      );
    } on PackImageOptimizationException catch (e) {
      state = state.copyWith(
        phase: PackImagePhase.idle,
        errorMessage: e.userMessage,
        clearPreview: true,
      );
    } on Object catch (e) {
      state = state.copyWith(
        phase: PackImagePhase.idle,
        errorMessage: 'Erreur inattendue : $e',
        clearPreview: true,
      );
    }
  }

  /// Annule la prévisualisation et revient à l'état idle.
  void cancelPreview() {
    state = const PackImageState();
  }

  /// Confirme l'upload de la preview courante vers Storage + Firestore.
  Future<bool> confirmUpload(String packId) async {
    final preview = state.preview;
    if (preview == null) return false;

    state = state.copyWith(phase: PackImagePhase.uploading);

    try {
      final uploader = _ref.read(packImageUploaderProvider);
      final result = await uploader.uploadOptimized(
        packId: packId,
        optimized: preview,
      );
      state = PackImageState(
        lastUploadedSizeBytes: result.sizeBytes,
      );
      return true;
    } on Object catch (e) {
      state = state.copyWith(
        phase: PackImagePhase.previewing,
        errorMessage: "Échec de l'upload : $e",
      );
      return false;
    }
  }

  /// Supprime l'image existante du pack.
  Future<bool> deleteExistingImage({
    required String packId,
    required String storagePath,
  }) async {
    state = state.copyWith(
      phase: PackImagePhase.uploading,
      clearError: true,
    );
    try {
      final uploader = _ref.read(packImageUploaderProvider);
      await uploader.deleteImage(packId: packId, storagePath: storagePath);
      state = const PackImageState();
      return true;
    } on Object catch (e) {
      state = state.copyWith(
        phase: PackImagePhase.idle,
        errorMessage: 'Échec de la suppression : $e',
      );
      return false;
    }
  }
}

final packImageControllerProvider = StateNotifierProvider.autoDispose
    .family<PackImageController, PackImageState, String>(
  (ref, _) => PackImageController(ref),
);
