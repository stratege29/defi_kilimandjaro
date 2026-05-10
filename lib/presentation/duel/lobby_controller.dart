import 'dart:async';

import 'package:defi_kilimandjaro/data/repositories/matchmaking_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:defi_kilimandjaro/domain/entities/player_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

/// Phases de l'écran lobby.
enum LobbyPhase {
  /// Recherche d'adversaire en cours.
  searching,

  /// Match trouvé — transition vers le jeu imminente.
  matched,

  /// Timeout ou erreur — aucun adversaire disponible.
  noOpponent,
}

/// État du lobby de matchmaking.
class LobbyState {
  const LobbyState({
    required this.phase,
    required this.expansionStep,
    required this.secondsElapsed,
    this.matchedSession,
    this.errorMessage,
  });

  factory LobbyState.initial() => const LobbyState(
        phase: LobbyPhase.searching,
        expansionStep: 0,
        secondsElapsed: 0,
      );

  final LobbyPhase phase;

  /// Étape d'expansion de la bande ELO (0 = ±150 m, 1 = ±225 m, …).
  final int expansionStep;

  /// Secondes écoulées depuis le début de la recherche.
  final int secondsElapsed;

  /// Rayon ELO courant en mètres.
  int get bandRadius => 150 + expansionStep * 75;

  /// Session de duel trouvée (disponible quand phase == matched).
  final DuelSession? matchedSession;

  final String? errorMessage;

  LobbyState copyWith({
    LobbyPhase? phase,
    int? expansionStep,
    int? secondsElapsed,
    DuelSession? matchedSession,
    String? errorMessage,
  }) {
    return LobbyState(
      phase: phase ?? this.phase,
      expansionStep: expansionStep ?? this.expansionStep,
      secondsElapsed: secondsElapsed ?? this.secondsElapsed,
      matchedSession: matchedSession ?? this.matchedSession,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Contrôleur du lobby matchmaking.
///
/// - Appelle `requestMatch` toutes les 5 s avec expansion progressive.
/// - Timeout à 30 s → état noOpponent.
/// - Annule proprement via [cancelSearch].
class LobbyController extends StateNotifier<LobbyState> {
  LobbyController({
    required this.matchmakingRepo,
    required this.profile,
  }) : super(LobbyState.initial()) {
    _requestId = const Uuid().v4();
    _startSearch();
  }

  final MatchmakingRepository matchmakingRepo;
  final PlayerProfile profile;
  final Logger _log = Logger();

  static const int _timeoutSeconds = 30;
  static const int _pollIntervalSeconds = 5;

  late String _requestId;
  Timer? _pollTimer;
  Timer? _tickTimer;
  bool _cancelled = false;

  void _startSearch() {
    // Tick toutes les secondes pour mettre à jour l'UI.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_cancelled || state.phase != LobbyPhase.searching) return;
      state = state.copyWith(secondsElapsed: state.secondsElapsed + 1);
      if (state.secondsElapsed >= _timeoutSeconds) {
        _onTimeout();
      }
    });

    // Poll toutes les 5 s.
    _poll(); // Premier poll immédiat.
    _pollTimer = Timer.periodic(
      const Duration(seconds: _pollIntervalSeconds),
      (_) => _poll(),
    );
  }

  Future<void> _poll() async {
    if (_cancelled || state.phase != LobbyPhase.searching) return;

    final expansionStep = state.secondsElapsed ~/ _pollIntervalSeconds;
    _log.d('Polling matchmaking — step $expansionStep, '
        'band ±${150 + expansionStep * 75} m');

    state = state.copyWith(expansionStep: expansionStep);

    try {
      final result = await matchmakingRepo.requestMatch(
        requestId: _requestId,
        expansionStep: expansionStep,
      );

      if (_cancelled) return;

      if (result is MatchmakingMatched) {
        _pollTimer?.cancel();
        _tickTimer?.cancel();
        state = state.copyWith(
          phase: LobbyPhase.matched,
          matchedSession: result.session,
        );
      }
      // MatchmakingWaiting → continuer à attendre.
    } on Exception catch (e) {
      _log.e('Erreur matchmaking poll', error: e);
      // Ne pas afficher d'erreur tant que le timeout n'est pas atteint —
      // les erreurs réseau transitoires sont normales.
    }
  }

  void _onTimeout() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    if (!_cancelled && state.phase == LobbyPhase.searching) {
      state = state.copyWith(phase: LobbyPhase.noOpponent);
      // Annuler l'entrée lobby côté serveur (fire-and-forget).
      matchmakingRepo.cancelMatch().ignore();
    }
  }

  /// Annule la recherche manuellement (bouton "ANNULER").
  Future<void> cancelSearch() async {
    if (_cancelled) return;
    _cancelled = true;
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    await matchmakingRepo.cancelMatch();
  }

  /// Relance une nouvelle recherche depuis zéro.
  void retry() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _cancelled = false;
    _requestId = const Uuid().v4();
    state = LobbyState.initial();
    _startSearch();
  }

  @override
  void dispose() {
    _cancelled = true;
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }
}

final lobbyControllerProvider =
    StateNotifierProvider.autoDispose<LobbyController, LobbyState>(
  (ref) {
    final profile = ref.watch(
      playerProfileStreamProvider.select((v) => v.value),
    );
    return LobbyController(
      matchmakingRepo: ref.watch(matchmakingRepositoryProvider),
      profile: profile ?? PlayerProfile.initial('anonymous'),
    );
  },
);
