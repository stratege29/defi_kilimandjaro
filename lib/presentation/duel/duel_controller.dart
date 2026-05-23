import 'dart:async';
import 'dart:math';

import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Etat local de l'ecran de duel pour le joueur courant.
class DuelLocalState {
  const DuelLocalState({
    required this.selectedIndices,
    required this.timeLeft,
    required this.currentRound,
    this.submitted = false,
  });

  factory DuelLocalState.initial() => const DuelLocalState(
        selectedIndices: <int>[],
        timeLeft: 30,
        currentRound: 0,
      );

  final List<int> selectedIndices;
  final int timeLeft;

  /// Round local observe : quand il change, le controller reset le state.
  final int currentRound;

  /// True si le joueur a valide le bon mot pour le round courant.
  final bool submitted;

  DuelLocalState copyWith({
    List<int>? selectedIndices,
    int? timeLeft,
    int? currentRound,
    bool? submitted,
  }) {
    return DuelLocalState(
      selectedIndices: selectedIndices ?? this.selectedIndices,
      timeLeft: timeLeft ?? this.timeLeft,
      currentRound: currentRound ?? this.currentRound,
      submitted: submitted ?? this.submitted,
    );
  }
}

/// Controleur local d'un duel multi-rounds.
///
/// Responsabilites :
/// - Maintient la selection des tuiles cote client.
/// - Pousse la progression a RTDB sur chaque changement (barre adverse).
/// - Detecte la fin du round (mot valide) et appelle submitRoundWin via repo.
/// - Observe [DuelSession.currentRound] : quand il change (signale par RTDB),
///   reset le state local pour le nouveau round.
/// - Gere le timer 30 s par round ; en cas de timeout appelle forfeit.
///
/// Phases ignorees par le controller (gerees par l'UI via phaseStartedAtMs) :
/// - intro, countdown, roundEnd.
class DuelController extends StateNotifier<DuelLocalState> {
  DuelController({
    required this.session,
    required this.selfUid,
    required this.repository,
  }) : super(DuelLocalState.initial()) {
    if (session.phase == DuelPhase.active) {
      _startTimer();
    }
  }

  final DuelSession session;
  final String selfUid;
  final DuelRepository repository;
  Timer? _timer;

  /// Appele depuis l'UI quand la session RTDB est mise a jour.
  ///
  /// Si le round a change (nouveau round demarre par advanceRound CF),
  /// reset le state local et demarre un nouveau timer.
  void onSessionUpdated(DuelSession updated) {
    final roundChanged = updated.currentRound != state.currentRound;
    final isNowActive = updated.phase == DuelPhase.active;

    if (roundChanged && isNowActive) {
      _timer?.cancel();
      state = DuelLocalState(
        selectedIndices: const <int>[],
        timeLeft: 30,
        currentRound: updated.currentRound,
      );
      _startTimer();
    } else if (!roundChanged && isNowActive && _timer == null) {
      // Phase active sans changement de round (ex: reconnexion).
      _startTimer();
    }
  }

  void selectTile(int gridIndex) {
    if (state.submitted) return;
    if (state.timeLeft == 0) return;

    final selected = List<int>.from(state.selectedIndices);

    // Slide-back : glisser en arriere sur l'avant-derniere tuile efface la derniere.
    if (selected.length >= 2 && selected[selected.length - 2] == gridIndex) {
      selected.removeLast();
      state = state.copyWith(selectedIndices: selected);
      _pushProgress();
      return;
    }
    if (selected.contains(gridIndex)) return;
    selected.add(gridIndex);
    state = state.copyWith(selectedIndices: selected);
    _pushProgress();

    final roundData = _currentRoundData();
    if (roundData != null && selected.length == roundData.answer.length) {
      _validate(roundData);
    }
  }

  void clearSelection() {
    if (state.submitted) return;
    state = state.copyWith(selectedIndices: const <int>[]);
    _pushProgress();
  }

  void _validate(RoundData roundData) {
    final formed =
        state.selectedIndices.map((i) => roundData.lettersPool[i]).join();
    if (formed == roundData.answer) {
      state = state.copyWith(submitted: true);
      unawaited(
        repository.submitRoundWin(
          session.matchId,
          state.currentRound,
          selfUid,
        ),
      );
    } else {
      state = state.copyWith(selectedIndices: const <int>[]);
      _pushProgress();
    }
  }

  void _pushProgress() {
    final roundData = _currentRoundData();
    if (roundData == null) return;
    final p = min<double>(
      state.selectedIndices.length / max(roundData.answer.length, 1),
      1,
    );
    unawaited(
      repository.updateProgress(session.matchId, state.currentRound, p),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.submitted || state.timeLeft <= 0) {
        _timer?.cancel();
        return;
      }
      state = state.copyWith(timeLeft: state.timeLeft - 1);
      if (state.timeLeft == 0) {
        // Timeout sur ce round : forfait global.
        unawaited(repository.forfeit(session.matchId));
        _timer?.cancel();
      }
    });
  }

  RoundData? _currentRoundData() {
    final idx = state.currentRound;
    if (idx < 0 || idx >= session.rounds.length) return null;
    return session.rounds[idx];
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final duelControllerProvider = StateNotifierProvider.autoDispose
    .family<DuelController, DuelLocalState, DuelSession>(
  (ref, session) {
    final repo = ref.watch(duelRepositoryProvider);
    return DuelController(
      session: session,
      selfUid: repo.currentUid,
      repository: repo,
    );
  },
);
