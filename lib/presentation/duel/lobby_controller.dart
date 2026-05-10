import 'dart:async';

import 'package:defi_kilimandjaro/audio/audio_controller.dart';
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
  });

  factory LobbyState.initial({String? rematchOpponentUid}) => LobbyState(
        phase: LobbyPhase.searching,
        expansionStep: 0,
        secondsElapsed: 0,
        rematchOpponentUid: rematchOpponentUid,
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
  /// TODO(PR-3 social): quand un vrai CF "rematch ciblé synchrone" sera ajouté,
  /// passer ce uid à la Cloud Function pour forcer le match avec cet adversaire.
  /// Pour l'instant le matchmaking standard s'applique et le champ sert
  /// uniquement à afficher un message informatif dans l'UI.
  final String? rematchOpponentUid;

  bool get isRematch => rematchOpponentUid != null;

  LobbyState copyWith({
    LobbyPhase? phase,
    int? expansionStep,
    int? secondsElapsed,
    DuelSession? matchedSession,
    String? errorMessage,
    String? rematchOpponentUid,
  }) {
    return LobbyState(
      phase: phase ?? this.phase,
      expansionStep: expansionStep ?? this.expansionStep,
      secondsElapsed: secondsElapsed ?? this.secondsElapsed,
      matchedSession: matchedSession ?? this.matchedSession,
      errorMessage: errorMessage ?? this.errorMessage,
      rematchOpponentUid: rematchOpponentUid ?? this.rematchOpponentUid,
    );
  }
}

/// Paramètres du lobby passés via `state.extra` dans go_router.
///
/// [rematchOpponentUid] : UID de l'adversaire du dernier duel. Si fourni,
/// le lobby affiche un message "rematch" mais utilise le matchmaking standard.
class LobbyArgs {
  const LobbyArgs({this.rematchOpponentUid});
  final String? rematchOpponentUid;
}

/// Contrôleur du lobby matchmaking.
///
/// - Appelle `requestMatch` toutes les 5 s avec expansion progressive.
/// - Timeout à 30 s → état noOpponent.
/// - Annule proprement via [cancelSearch].
/// - Wire audio : loop tam-tam au démarrage, stop + ding au match.
class LobbyController extends StateNotifier<LobbyState> {
  LobbyController({
    required this.matchmakingRepo,
    required this.audioController,
    required this.profile,
    String? rematchOpponentUid,
  }) : super(LobbyState.initial(rematchOpponentUid: rematchOpponentUid)) {
    _requestId = const Uuid().v4();
    _startSearch();
    // Audio — démarre la loop tam-tam 108 BPM dès l'entrée en recherche.
    unawaited(audioController.playLobbySearchLoop());
  }

  final MatchmakingRepository matchmakingRepo;
  final AudioController audioController;
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
        'band ±${150 + expansionStep * 75} m'
        '${state.isRematch ? " [rematch]" : ""}');

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
        // Audio — stop loop + ding match trouvé.
        unawaited(audioController.stopLobbySearchLoop());
        unawaited(audioController.playLobbyMatchFound());
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
      unawaited(audioController.stopLobbySearchLoop());
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
    unawaited(audioController.stopLobbySearchLoop());
    await matchmakingRepo.cancelMatch();
  }

  /// Relance une nouvelle recherche depuis zéro.
  void retry() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _cancelled = false;
    _requestId = const Uuid().v4();
    state = LobbyState.initial(rematchOpponentUid: state.rematchOpponentUid);
    _startSearch();
    // Relance la loop audio.
    unawaited(audioController.playLobbySearchLoop());
  }

  @override
  void dispose() {
    _cancelled = true;
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    // Arrêt sécurisé de la loop au cas où le widget est détruit en mid-search.
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
    // L'UID du rematch est passé via les args de la route (voir app_router.dart).
    final rematchUid = ref.watch(_lobbyRematchUidProvider);
    return LobbyController(
      matchmakingRepo: ref.watch(matchmakingRepositoryProvider),
      audioController: ref.read(audioControllerProvider.notifier),
      profile: profile ?? PlayerProfile.initial('anonymous'),
      rematchOpponentUid: rematchUid,
    );
  },
);

/// Provider intermédiaire permettant de passer l'UID de rematch sans
/// modifier la signature du provider principal (évite le family).
///
/// Surcharger ce provider depuis la vue avant d'accéder à lobbyControllerProvider.
final _lobbyRematchUidProvider = StateProvider<String?>((ref) => null);

/// Provider public permettant à la vue lobby et au router de setter
/// l'UID de rematch avant la navigation.
final lobbyRematchUidProvider = _lobbyRematchUidProvider;
