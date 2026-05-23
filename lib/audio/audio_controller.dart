import 'dart:async';

import 'package:defi_kilimandjaro/audio/audio_engine.dart';
import 'package:defi_kilimandjaro/audio/tempo_scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// État immutable de l'audio (mute + volume).
class AudioState {
  const AudioState({required this.muted, required this.volume});

  /// Préférences par défaut (utilisées avant chargement de SharedPreferences).
  factory AudioState.defaults() => const AudioState(muted: false, volume: 0.8);

  final bool muted;
  final double volume;

  AudioState copyWith({bool? muted, double? volume}) =>
      AudioState(muted: muted ?? this.muted, volume: volume ?? this.volume);
}

/// API publique du système audio, exposée via [audioControllerProvider].
///
/// **Toutes les méthodes `play*` sont fire-and-forget** : asynchrones,
/// non-bloquantes, et ignorent silencieusement les erreurs (cf. spec p.12).
class AudioController extends StateNotifier<AudioState> {
  AudioController(this._engine) : super(AudioState.defaults()) {
    _loadPrefs();
  }

  static const String _keyMuted = 'audio_muted';
  static const String _keyVolume = 'audio_volume';

  final AudioEngine _engine;
  final Logger _log = Logger();

  // ─── Lobby loop state ────────────────────────────────────────────────────
  //
  // Pattern "DOUM . . tac . DOUM . tac" en 8/8 à 108 BPM.
  //
  // 108 BPM → beat = 556 ms → croche (1/2 beat) = 278 ms.
  // 8 croches par mesure :
  //   step 0 : DOUM (frappe grave, accent fort)
  //   step 1 : rest
  //   step 2 : rest
  //   step 3 : tac  (frappe légère)
  //   step 4 : rest
  //   step 5 : DOUM (frappe grave, même sample)
  //   step 6 : rest
  //   step 7 : tac  (frappe légère)
  //
  // Choix Timer.periodic plutôt que SoLoud native loop :
  // flutter_soloud 3.x ne propose pas de boucle native par AudioSource depuis
  // l'API Dart publique. Le scheduling côté Dart à 278 ms est compatible avec
  // le UI thread mobile (largement au-dessus du quantum de 16 ms). Un seul
  // Timer actif à la fois (guard _lobbyLoopTimer != null → idempotent).
  static const int _lobbyStepMs = 278;
  static const List<int> _lobbyPattern = <int>[
    0, //  step 0 : DOUM fort
    -1, // step 1 : rest
    -1, // step 2 : rest
    1, //  step 3 : tac
    -1, // step 4 : rest
    0, //  step 5 : DOUM (même sample — variation de velocity perçue via
    //           le hasard de superposition avec la décroissance du précédent)
    -1, // step 6 : rest
    1, //  step 7 : tac
  ];

  Timer? _lobbyLoopTimer;
  int _lobbyStep = 0;

  @override
  void dispose() {
    _cancelLobbyLoop();
    super.dispose();
  }

  /// Active/désactive le mute (persisté).
  Future<void> toggleMute() => setMuted(muted: !state.muted);

  /// Définit le mute (persisté).
  Future<void> setMuted({required bool muted}) async {
    state = state.copyWith(muted: muted);
    _engine.setMuted(muted: muted);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMuted, muted);
  }

  /// Définit le volume [0,1] (persisté).
  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    state = state.copyWith(volume: v);
    _engine.setVolume(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyVolume, v);
  }

  /// Suspend le moteur (entre niveaux — cf. maquette p.12).
  /// Arrête également le loop lobby si actif.
  void suspend() {
    _cancelLobbyLoop();
    _engine.suspend();
  }

  /// Reprend le moteur après [suspend].
  void resume() => _engine.resume();

  // ─── API ludique (cf. maquette p.12) ────────────────────────────────────

  /// Sélection d'une lettre — balafon pentatonique ascendant.
  Future<void> playLetterSelect(int letterIdx) {
    final cue = switch (letterIdx % 5) {
      0 => AudioCue.letterSelect0,
      1 => AudioCue.letterSelect1,
      2 => AudioCue.letterSelect2,
      3 => AudioCue.letterSelect3,
      _ => AudioCue.letterSelect4,
    };
    return _engine.play(cue);
  }

  /// Mot complété — accord balafon ascendant 5 notes (70 ms espace).
  Future<void> playWordComplete() => _engine.play(AudioCue.wordComplete);

  /// Indice utilisé — kora 2 notes descendantes douces.
  Future<void> playHintUsed() => _engine.play(AudioCue.hintUsed);

  /// Victoire — fanfare griot (balafon + kora + tam-tam).
  Future<void> playVictory() => _engine.play(AudioCue.victory);

  /// Échec — balafon descendant + tam-tam lent.
  Future<void> playFailure() => _engine.play(AudioCue.failure);

  /// Mauvaise réponse — djembé x2.
  Future<void> playWrongAnswer() => _engine.play(AudioCue.wrongAnswer);

  /// Tick timer — sweep tam-tam 160→60 Hz.
  ///
  /// [bpm] est ignoré ici (le BPM est piloté par [TempoScheduler]) ; le
  /// paramètre est conservé pour respecter la signature de la maquette p.12.
  Future<void> playTimerTick(int bpm) => _engine.play(AudioCue.timerTick);

  // ─── Lobby matchmaking (PR #2) ─────────────────────────────────────────

  /// Démarre le loop pulsé de recherche lobby à 108 BPM.
  ///
  /// **Idempotent** : si un loop est déjà actif, l'appel est ignoré.
  /// Appeler dès l'entrée dans l'écran Lobby. Stopper via
  /// [stopLobbySearchLoop] quand match trouvé, annulé ou timeout.
  ///
  /// Respecte le mute global : no-op silencieux si `state.muted == true`.
  Future<void> playLobbySearchLoop() async {
    if (state.muted) return;
    if (_lobbyLoopTimer != null) return; // idempotent
    _lobbyStep = 0;
    // Première frappe immédiate avant le premier délai du Timer.
    unawaited(_fireLobbyStep());
    _lobbyLoopTimer = Timer.periodic(
      const Duration(milliseconds: _lobbyStepMs),
      (_) {
        _lobbyStep = (_lobbyStep + 1) % _lobbyPattern.length;
        unawaited(_fireLobbyStep());
      },
    );
    _log.d(
      'AudioController: lobby loop started — 108 BPM, step=$_lobbyStepMs ms',
    );
  }

  /// Arrête le loop de recherche lobby proprement.
  ///
  /// **Safe** : peut être appelé même si aucun loop n'est actif.
  Future<void> stopLobbySearchLoop() async {
    _cancelLobbyLoop();
    _log.d('AudioController: lobby loop stopped');
  }

  /// Ding! joyeux quand l'adversaire est trouvé (~620 ms).
  ///
  /// Arrête le loop automatiquement si encore actif. L'arrêt est synchrone
  /// (annulation du Timer avant le play), donc aucun sample du loop ne peut
  /// se superposer après l'appel.
  ///
  /// Respecte le mute global.
  Future<void> playLobbyMatchFound() async {
    if (state.muted) return;
    // Arrêt synchrone pour éviter superposition brutale avec le loop.
    _cancelLobbyLoop();
    await _engine.play(AudioCue.lobbyMatchFound);
  }

  /// Gong cérémoniel d'ouverture du duel ranked (~820 ms).
  ///
  /// L'UI décide si la méthode est appelée (ex. uniquement si
  /// `session.isRanked`). Fire-and-forget, respecte le mute global.
  Future<void> playDuelStart() async {
    if (state.muted) return;
    await _engine.play(AudioCue.duelStart);
  }

  // ─── Duel — fin de manche (3-manches) ──────────────────────────────────

  /// Cue "manche gagnée" — arpège kora ascendant + roulement djembé (~950 ms).
  /// À appeler depuis l'overlay de fin de manche quand le joueur l'emporte.
  /// Fire-and-forget, respecte le mute global.
  Future<void> playRoundWon() async {
    if (state.muted) return;
    await _engine.play(AudioCue.roundWon);
  }

  /// Cue "manche perdue" — balafon grave descendant + ride courte (~800 ms).
  /// Fire-and-forget, respecte le mute global.
  Future<void> playRoundLost() async {
    if (state.muted) return;
    await _engine.play(AudioCue.roundLost);
  }

  /// Cue "manche nulle" — accord kora suspendu sans tierce (~750 ms).
  /// Fire-and-forget, respecte le mute global.
  Future<void> playRoundDraw() async {
    if (state.muted) return;
    await _engine.play(AudioCue.roundDraw);
  }

  // ─── Privé ──────────────────────────────────────────────────────────────

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final muted = prefs.getBool(_keyMuted) ?? false;
      final volume = prefs.getDouble(_keyVolume) ?? 0.8;
      state = AudioState(muted: muted, volume: volume);
      _engine
        ..setMuted(muted: muted)
        ..setVolume(volume);
    } on Object catch (e) {
      _log.w('AudioController._loadPrefs failed: $e');
    }
  }

  /// Annule le timer du loop lobby. Sans effet si inactif.
  void _cancelLobbyLoop() {
    _lobbyLoopTimer?.cancel();
    _lobbyLoopTimer = null;
    _lobbyStep = 0;
  }

  /// Déclenche le cue correspondant au [_lobbyStep] courant.
  Future<void> _fireLobbyStep() async {
    if (state.muted) return;
    final hit = _lobbyPattern[_lobbyStep];
    if (hit == 0) {
      await _engine.play(AudioCue.lobbyLoopDoum);
    } else if (hit == 1) {
      await _engine.play(AudioCue.lobbyLoopTac);
    }
    // hit == -1 → rest, rien à jouer
  }
}

/// Provider exposant l'instance unique de [AudioController].
final audioControllerProvider =
    StateNotifierProvider<AudioController, AudioState>((ref) {
  final controller = AudioController(AudioEngine.instance);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Provider exposant un [TempoScheduler] partagé pour la cadence du timer.
final tempoSchedulerProvider = Provider<TempoScheduler>((ref) {
  final scheduler = TempoScheduler();
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
