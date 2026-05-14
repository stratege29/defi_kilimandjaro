import 'package:defi_kilimandjaro/data/repositories/submission_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// État de l'écran de soumission UGC.
class SubmitDevinetteState {
  const SubmitDevinetteState({
    this.submitting = false,
    this.success,
    this.errorCode,
    this.errorMessage,
  });

  final bool submitting;

  /// `submissionId` retourné par le backend en cas de succès.
  final String? success;

  final String? errorCode;
  final String? errorMessage;

  SubmitDevinetteState copyWith({
    bool? submitting,
    String? success,
    String? errorCode,
    String? errorMessage,
    bool clearSuccess = false,
    bool clearError = false,
  }) {
    return SubmitDevinetteState(
      submitting: submitting ?? this.submitting,
      success: clearSuccess ? null : (success ?? this.success),
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class SubmitDevinetteController extends Notifier<SubmitDevinetteState> {
  @override
  SubmitDevinetteState build() => const SubmitDevinetteState();

  /// Validation client-side avant l'appel Cloud Function. Toutes ces règles
  /// sont aussi répliquées côté serveur (zod) — la duplication est volontaire
  /// pour l'UX (feedback instantané).
  String? validateDraft(SubmissionDraft d) {
    if (d.answer.length < 3 || d.answer.length > 20) {
      return 'La réponse doit faire entre 3 et 20 caractères.';
    }
    if (d.riddle.length < 20 || d.riddle.length > 280) {
      return 'La devinette doit faire entre 20 et 280 caractères.';
    }
    if (d.explanation.length < 30 || d.explanation.length > 500) {
      return "L'explication doit faire entre 30 et 500 caractères.";
    }
    if (d.proverb.length < 5 || d.proverb.length > 140) {
      return 'Le proverbe doit faire entre 5 et 140 caractères.';
    }
    if (d.difficulty < 1 || d.difficulty > 5) {
      return 'Difficulté entre 1 et 5.';
    }
    if (d.tags.length > 5) {
      return 'Maximum 5 tags.';
    }
    return null;
  }

  Future<void> submit(SubmissionDraft draft) async {
    final issue = validateDraft(draft);
    if (issue != null) {
      state = state.copyWith(
        errorCode: 'invalid-argument',
        errorMessage: issue,
        clearSuccess: true,
      );
      return;
    }

    state = state.copyWith(submitting: true, clearError: true, clearSuccess: true);
    try {
      final res = await ref
          .read(submissionRepositoryProvider)
          .submit(draft);
      state = SubmitDevinetteState(success: res.submissionId);
    } on SubmissionException catch (e) {
      state = SubmitDevinetteState(
        errorCode: e.code,
        errorMessage: e.message,
      );
    } on Exception catch (e) {
      state = SubmitDevinetteState(
        errorCode: 'unknown',
        errorMessage: e.toString(),
      );
    }
  }

  void reset() {
    state = const SubmitDevinetteState();
  }
}

final submitDevinetteControllerProvider =
    NotifierProvider<SubmitDevinetteController, SubmitDevinetteState>(
  SubmitDevinetteController.new,
);
