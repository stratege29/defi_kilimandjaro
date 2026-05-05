import 'dart:async';
import 'dart:math';

import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// État local de l'écran de duel pour le joueur courant.
class DuelLocalState {
  const DuelLocalState({
    required this.selectedIndices,
    required this.timeLeft,
    this.submitted = false,
  });

  factory DuelLocalState.initial() =>
      const DuelLocalState(selectedIndices: <int>[], timeLeft: 30);

  final List<int> selectedIndices;
  final int timeLeft;
  final bool submitted;

  DuelLocalState copyWith({
    List<int>? selectedIndices,
    int? timeLeft,
    bool? submitted,
  }) {
    return DuelLocalState(
      selectedIndices: selectedIndices ?? this.selectedIndices,
      timeLeft: timeLeft ?? this.timeLeft,
      submitted: submitted ?? this.submitted,
    );
  }
}

/// Contrôleur local d'un duel.
///
/// - Maintient la sélection des tuiles côté client.
/// - Pousse la progression à RTDB sur chaque changement.
/// - Submit la victoire au serveur quand le mot est valide.
class DuelController extends StateNotifier<DuelLocalState> {
  DuelController({
    required this.session,
    required this.repository,
  }) : super(DuelLocalState.initial()) {
    _startTimer();
  }

  final DuelSession session;
  final DuelRepository repository;
  Timer? _timer;

  void selectTile(int gridIndex) {
    if (state.submitted) return;
    if (state.timeLeft == 0) return;

    final selected = List<int>.from(state.selectedIndices);

    // Slide-back.
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

    // Auto-validate when length matches.
    if (selected.length == session.answer.length) {
      _validate();
    }
  }

  void clearSelection() {
    if (state.submitted) return;
    state = state.copyWith(selectedIndices: const <int>[]);
    _pushProgress();
  }

  void _validate() {
    final formed = state.selectedIndices
        .map((i) => session.lettersPool[i])
        .join();
    if (formed == session.answer) {
      state = state.copyWith(submitted: true);
      unawaited(repository.submitWin(session.matchId));
    } else {
      // Mauvaise réponse → effacer.
      state = state.copyWith(selectedIndices: const <int>[]);
      _pushProgress();
    }
  }

  void _pushProgress() {
    final p = min<double>(
      state.selectedIndices.length / max(session.answer.length, 1),
      1,
    );
    unawaited(repository.updateMyProgress(session.matchId, p));
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
        // Forfait local — l'autre joueur peut gagner.
        unawaited(repository.forfeit(session.matchId));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final duelControllerProvider = StateNotifierProvider.autoDispose
    .family<DuelController, DuelLocalState, DuelSession>(
  (ref, session) => DuelController(
    session: session,
    repository: ref.watch(duelRepositoryProvider),
  ),
);
