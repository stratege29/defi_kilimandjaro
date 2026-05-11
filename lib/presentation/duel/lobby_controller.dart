import 'dart:async';

import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
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
    this.rematchOpponentUid,
    this.previousMatchId,
  });

  factory LobbyState.initial({
    String? rematchOpponentUid,
    String? previousMatchId,
  }) =>
      LobbyState(
        phase: LobbyPhase.searching,
        expansionStep: 0,
        secondsElapsed: 0,
        rematchOpponentUid: rematchOpponentUid,
        previousMatchId: previousMatchId,
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

  /// UID de l'adversaire ciblé pour un rematch (null = matchmaking standard).
  ///
  /// Quand présent, le lobby appelle `requestRematch` (CF ciblée) au lieu de
  /// `requestMatch` standard. L'adversaire reçoit une notif FCM avec le matchId.
  final String? rematchOpponentUid;

  /// matchId du duel précédent — requis pour le flow requestRematch.
  final String? previousMatchId;

  bool get isRematch => rematchOpponentUid != null;

  LobbyState copyWith({
    LobbyPhase? phase,
    int? expansionStep,
    int? secondsElapsed,
    DuelSession? matchedSession,
    String? errorMessage,
    String? rematchOpponentUid,
    String? previousMatchId,
  }) {
    return LobbyState(
      phase: phase ?? this.phase,
      expansionStep: expansionStep ?? this.expansionStep,
      secondsElapsed: secondsElapsed ?? this.secondsElapsed,
      matchedSession: matchedSession ?? this.matchedSession,
      errorMessage: errorMessage ?? this.errorMessage,
      rematchOpponentUid: rematchOpponentUid ?? this.rematchOpponentUid,
      previousMatchId: previousMatchId ?? this.previousMatchId,
    );
  }
}

/// Paramètres du lobby passés via `state.extra` dans go_router.
///
/// [rematchOpponentUid] : UID de l'adversaire du dernier duel.
/// [previousMatchId] : matchId du duel précédent (requis pour requestRematch).
class LobbyArgs {
  const LobbyArgs({
    this.rematchOpponentUid,
    this.previousMatchId,
  });
  final String? rematchOpponentUid;
  final String? previousMatchId;
}

/// Contrôleur du lobby matchmaking.
///
/// - Mode standard : appelle `requestMatch` toutes les 5 s avec expansion ELO.
/// - Mode rematch : appelle `requestRematch` une seule fois (pas de polling),
///   puis observe /matches/{matchId} en stream RTDB jusqu'à ce que l'adversaire
///   rejoigne (phase passe à "active") ou que le timeout expire.
/// - Timeout à 30 s → état noOpponent.
/// - Annule proprement via [cancelSearch].
/// - Wire audio : loop tam-tam au démarrage, stop + ding au match.
class LobbyController extends StateNotifier<LobbyState> {
  LobbyController({
    required this.matchmakingRepo,
    required this.duelRepository,
    required this.audioController,
    required this.profile,
    String? rematchOpponentUid,
    String? previousMatchId,
  }) : super(
          LobbyState.initial(
            rematchOpponentUid: rematchOpponentUid,
            previousMatchId: previousMatchId,
          ),
        ) {
    _requestId = const Uuid().v4();
    _startSearch();
    // Audio — démarre la loop tam-tam 108 BPM dès l'entrée en recherche.
    unawaited(audioController.playLobbySearchLoop());
  }

  final MatchmakingRepository matchmakingRepo;
  final DuelRepository duelRepository;
  final AudioController audioController;
  final PlayerProfile profile;
  final Logger _log = Logger();

  static const int _timeoutSeconds = 30;
  static const int _pollIntervalSeconds = 5;

  late String _requestId;
  Timer? _pollTimer;
  Timer? _tickTimer;
  StreamSubscription<DuelSession?>? _rematchWatchSub;
  bool _cancelled = false;

  void _startSearch() {
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_cancelled || state.phase != LobbyPhase.searching) return;
      state = state.copyWith(secondsElapsed: state.secondsElapsed + 1);
      if (state.secondsElapsed >= _timeoutSeconds) {
        _onTimeout();
      }
    });

    if (state.isRematch &&
        state.rematchOpponentUid != null &&
        state.previousMatchId != null) {
      // Mode rematch ciblé — appel unique à la CF requestRematch.
      _startRematchFlow();
    } else {
      // Mode matchmaking ELO standard — polling toutes les 5 s.
      _poll();
      _pollTimer = Timer.periodic(
        const Duration(seconds: _pollIntervalSeconds),
        (_) => _poll(),
      );
    }
  }

  /// Lance le flow rematch :
  /// 1. Appelle requestRematch CF (une seule fois).
  /// 2. Observe /matches/{newMatchId} en stream RTDB.
  /// 3. Quand phase passe à "active" ou "waiting" avec 2 joueurs → matched.
  Future<void> _startRematchFlow() async {
    if (_cancelled) return;
    _log.i(
      '[Rematch] Envoi CF requestRematch vers ${state.rematchOpponentUid}',
    );

    try {
      final result = await matchmakingRepo.requestRematch(
        previousMatchId: state.previousMatchId!,
        opponentUid: state.rematchOpponentUid!,
      );

      if (_cancelled) return;

      final newMatchId = result.matchId;
      _log.i('[Rematch] Nouveau match créé: $newMatchId');

      // Observer le match en temps réel via RTDB stream.
      _rematchWatchSub =
          duelRepository.watch(newMatchId).listen(_onRematchSessionUpdate);
    } on Exception catch (e) {
      _log.e('[Rematch] requestRematch failed', error: e);
      if (!_cancelled && state.phase == LobbyPhase.searching) {
        state = state.copyWith(
          phase: LobbyPhase.noOpponent,
          errorMessage: 'Impossible de créer le rematch. Réessaie.',
        );
        unawaited(audioController.stopLobbySearchLoop());
      }
    }
  }

  void _onRematchSessionUpdate(DuelSession? session) {
    if (_cancelled || state.phase != LobbyPhase.searching) return;
    if (session == null) return;

    // Le match est prêt dès que l'adversaire a rejoint (2 joueurs présents)
    // ou que la phase est active.
    final hasOpponent = session.players.length >= 2;
    final isActive = session.phase == DuelPhase.active;

    if (hasOpponent || isActive) {
      unawaited(_rematchWatchSub?.cancel());
      _pollTimer?.cancel();
      _tickTimer?.cancel();
      unawaited(audioController.stopLobbySearchLoop());
      unawaited(audioController.playLobbyMatchFound());
      state = state.copyWith(
        phase: LobbyPhase.matched,
        matchedSession: session,
      );
    }
  }

  Future<void> _poll() async {
    if (_cancelled || state.phase != LobbyPhase.searching) return;

    final expansionStep = state.secondsElapsed ~/ _pollIntervalSeconds;
    _log.d(
      'Polling matchmaking — step $expansionStep, '
      'band +-${150 + expansionStep * 75} m',
    );

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
        unawaited(audioController.stopLobbySearchLoop());
        unawaited(audioController.playLobbyMatchFound());
        state = state.copyWith(
          phase: LobbyPhase.matched,
          matchedSession: result.session,
        );
      }
      // MatchmakingWaiting → continuer a attendre.
    } on Exception catch (e) {
      _log.e('Erreur matchmaking poll', error: e);
    }
  }

  void _onTimeout() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    unawaited(_rematchWatchSub?.cancel());
    if (!_cancelled && state.phase == LobbyPhase.searching) {
      unawaited(audioController.stopLobbySearchLoop());
      state = state.copyWith(phase: LobbyPhase.noOpponent);
      // Annuler l'entrée lobby cote serveur (fire-and-forget).
      if (!state.isRematch) {
        matchmakingRepo.cancelMatch().ignore();
      }
    }
  }

  /// Annule la recherche manuellement (bouton "ANNULER").
  Future<void> cancelSearch() async {
    if (_cancelled) return;
    _cancelled = true;
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    unawaited(_rematchWatchSub?.cancel());
    unawaited(audioController.stopLobbySearchLoop());
    if (!state.isRematch) {
      await matchmakingRepo.cancelMatch();
    }
  }

  /// Relance une nouvelle recherche depuis zero.
  void retry() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    unawaited(_rematchWatchSub?.cancel());
    _cancelled = false;
    _requestId = const Uuid().v4();
    state = LobbyState.initial(
      rematchOpponentUid: state.rematchOpponentUid,
      previousMatchId: state.previousMatchId,
    );
    _startSearch();
    unawaited(audioController.playLobbySearchLoop());
  }

  @override
  void dispose() {
    _cancelled = true;
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    unawaited(_rematchWatchSub?.cancel());
    unawaited(audioController.stopLobbySearchLoop());
    super.dispose();
  }
}

final lobbyControllerProvider =
    StateNotifierProvider.autoDispose<LobbyController, LobbyState>(
  (ref) {
    final profile = ref.watch(
      playerProfileStreamProvider.select((v) => v.value),
    );
    final rematchUid = ref.watch(_lobbyRematchUidProvider);
    final previousMatchId = ref.watch(_lobbyPreviousMatchIdProvider);
    return LobbyController(
      matchmakingRepo: ref.watch(matchmakingRepositoryProvider),
      duelRepository: ref.watch(duelRepositoryProvider),
      audioController: ref.read(audioControllerProvider.notifier),
      profile: profile ?? PlayerProfile.initial('anonymous'),
      rematchOpponentUid: rematchUid,
      previousMatchId: previousMatchId,
    );
  },
);

/// Provider intermediaire pour l'UID de rematch.
/// Surcharger depuis la vue avant d'accéder a lobbyControllerProvider.
final _lobbyRematchUidProvider = StateProvider<String?>((ref) => null);

/// Provider intermediaire pour le matchId precedent (flow rematch).
/// Surcharger depuis DuelResultView avant de naviguer vers le lobby.
final _lobbyPreviousMatchIdProvider = StateProvider<String?>((ref) => null);

/// Provider public : UID de l'adversaire du dernier duel.
final lobbyRematchUidProvider = _lobbyRematchUidProvider;

/// Provider public : matchId du duel precedent.
final lobbyPreviousMatchIdProvider = _lobbyPreviousMatchIdProvider;
