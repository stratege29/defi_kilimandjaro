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
  // Re-signale le timeout du round tant que la phase n'a pas avance. Couvre le
  // cas d'un adversaire injoignable (deconnecte) : le serveur ne resout qu'au
  // bout de son delai de grace, donc un seul appel a 30s ne suffit pas.
  Timer? _timeoutRetry;

  /// Appele depuis l'UI quand la session RTDB est mise a jour.
  ///
  /// Si le round a change (nouveau round demarre par advanceRound CF),
  /// reset le state local et demarre un nouveau timer.
  void onSessionUpdated(DuelSession updated) {
    final roundChanged = updated.currentRound != state.currentRound;
    final isNowActive = updated.phase == DuelPhase.active;

    // Si la phase n'est plus active (roundEnd, countdown, finished),
    // arreter immediatement le timer local : on n'a plus rien a faire
    // pendant les animations inter-rounds. Evite que le perdant continue
    // a decrementer son timer pendant que le round est deja termine.
    if (!isNowActive) {
      _timer?.cancel();
      _timer = null;
      // La phase a avance (roundEnd/countdown/finished) : plus besoin de
      // re-signaler le timeout.
      _timeoutRetry?.cancel();
      _timeoutRetry = null;
    }

    if (roundChanged && isNowActive) {
      _timer?.cancel();
      _timeoutRetry?.cancel();
      _timeoutRetry = null;
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
      // Fire-and-forget : on swallow l'erreur (le serveur est idempotent,
      // si l'autre joueur a gagné en parallèle, ça retourne failed-precondition
      // et c'est normal).
      repository
          .submitRoundWin(session.matchId, state.currentRound, selfUid)
          .catchError((Object _) => '');
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
        // Timeout du round : signaler au serveur via submitRoundTimeout.
        // Si les 2 joueurs sont en timeout, le serveur :
        //   - rounds 0,1 : passe a roundEnd (personne ne gagne)
        //   - round 2 (dernier) : termine le match avec calcul du gagnant
        _timer?.cancel();
        _submitTimeoutWithRetry();
      }
    });
  }

  /// Signale le timeout du round, puis re-tente periodiquement tant que la
  /// phase reste active. Indispensable si l'adversaire est injoignable : le
  /// serveur ne resout qu'apres son delai de grace (~38s), donc le 1er appel
  /// a 30s repond "waiting_for_opponent". onSessionUpdated annule ce timer des
  /// que la phase avance (roundEnd/finished).
  void _submitTimeoutWithRetry() {
    final round = state.currentRound;
    void fire() => repository
        .submitRoundTimeout(session.matchId, round)
        .catchError((Object _) => null);
    fire();
    _timeoutRetry?.cancel();
    var attempts = 0;
    _timeoutRetry = Timer.periodic(const Duration(seconds: 4), (t) {
      attempts++;
      if (attempts > 10) {
        // Garde-fou : ~40s de retries. Au-dela on arrete (eviter le spam).
        t.cancel();
        _timeoutRetry = null;
        return;
      }
      fire();
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
    _timeoutRetry?.cancel();
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
