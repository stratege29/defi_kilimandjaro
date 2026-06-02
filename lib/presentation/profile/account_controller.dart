import 'package:defi_kilimandjaro/data/local/seen_devinette_store.dart';
import 'package:defi_kilimandjaro/data/repositories/auth_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/sync/progress_sync_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// État UI transient des actions de compte (liaison, déconnexion, suppression).
///
/// Le fournisseur lié et le flag anonyme proviennent de [authStateProvider] —
/// cet état ne porte que le statut d'action en cours et les messages.
class AccountUiState {
  const AccountUiState({this.isBusy = false, this.error, this.notice});

  /// Action réseau en cours (désactive les boutons + spinner).
  final bool isBusy;

  /// Message d'erreur à afficher, ou `null`.
  final String? error;

  /// Notice informative (ex: bascule vers un compte existant), ou `null`.
  final String? notice;

  AccountUiState copyWith({
    bool? isBusy,
    String? Function()? error,
    String? Function()? notice,
  }) {
    return AccountUiState(
      isBusy: isBusy ?? this.isBusy,
      error: error != null ? error() : this.error,
      notice: notice != null ? notice() : this.notice,
    );
  }
}

/// Pilote les flux de compte au-dessus de [AuthRepository].
///
/// Les clés i18n (`profile.account.*`) sont résolues côté vue ; ce contrôleur
/// expose des clés brutes dans `AccountUiState.notice`/`error` pour rester
/// sans dépendance UI/localization.
class AccountController extends StateNotifier<AccountUiState> {
  AccountController({required AuthRepository auth, required Ref ref})
      : _auth = auth,
        _ref = ref,
        super(const AccountUiState());

  final AuthRepository _auth;
  final Ref _ref;

  Future<void> linkWithGoogle() => _runLink(_auth.linkWithGoogle);

  Future<void> linkWithApple() => _runLink(_auth.linkWithApple);

  Future<void> _runLink(Future<LinkOutcome> Function() action) async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, error: () => null, notice: () => null);
    try {
      final outcome = await action();
      switch (outcome) {
        case LinkOutcome.linked:
          // Compte fraîchement lié (même uid) : sauvegarde l'état local
          // sous l'identité désormais pérenne.
          await _restoreCloudProgress();
          state = state.copyWith(
            isBusy: false,
            notice: () => 'profile.account.linked_success',
          );
        case LinkOutcome.switchedToExisting:
          // Bascule vers un compte existant (uid différent) : on récupère
          // sa sauvegarde cloud et on la fusionne (best-of-both) avec la
          // progression du device courant.
          await _restoreCloudProgress();
          state = state.copyWith(
            isBusy: false,
            notice: () => 'profile.account.switched_notice',
          );
        case LinkOutcome.cancelled:
          state = state.copyWith(isBusy: false);
      }
    } on AuthException {
      state = state.copyWith(
        isBusy: false,
        error: () => 'profile.account.link_error',
      );
    } on Object {
      state = state.copyWith(
        isBusy: false,
        error: () => 'profile.account.link_error',
      );
    }
  }

  Future<void> signOut() async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, error: () => null, notice: () => null);
    try {
      await _auth.signOut();
      state = state.copyWith(isBusy: false);
    } on Object {
      state = state.copyWith(
        isBusy: false,
        error: () => 'profile.account.signout_error',
      );
    }
  }

  Future<void> deleteAccount() async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, error: () => null, notice: () => null);
    try {
      await _auth.deleteAccount();
      // Efface la progression locale (cauris/niveaux/streaks) du device.
      await _ref.read(playerProgressProvider.notifier).reset();
      // RGPD : efface aussi le journal anti-répétition « déjà vu ».
      await _ref.read(seenDevinetteTrackerProvider).clearAll();
      state = state.copyWith(isBusy: false);
    } on Object {
      state = state.copyWith(
        isBusy: false,
        error: () => 'profile.account.delete_error',
      );
    }
  }

  /// Récupère + fusionne la progression cloud du compte courant, *fail-soft*.
  /// Une erreur de sync ne doit jamais transformer une liaison réussie en
  /// échec côté UI.
  Future<void> _restoreCloudProgress() async {
    try {
      await _ref.read(progressSyncCoordinatorProvider).restoreAndBackup();
    } on Object {
      // best-effort : la sauvegarde debouncée re-tentera au prochain gain.
    }
  }

  void clearMessages() {
    state = state.copyWith(error: () => null, notice: () => null);
  }
}

final accountControllerProvider =
    StateNotifierProvider<AccountController, AccountUiState>((ref) {
  return AccountController(
    auth: ref.watch(authRepositoryProvider),
    ref: ref,
  );
});
