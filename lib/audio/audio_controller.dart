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
  void suspend() => _engine.suspend();

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
  /// [bpm] est ignoré ici (le BPM est piloté par [TempoScheduler]) ; le
  /// paramètre est conservé pour respecter la signature de la maquette p.12.
  Future<void> playTimerTick(int bpm) => _engine.play(AudioCue.timerTick);

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
}

/// Provider exposant l'instance unique de [AudioController].
final audioControllerProvider =
    StateNotifierProvider<AudioController, AudioState>((ref) {
  return AudioController(AudioEngine.instance);
});

/// Provider exposant un [TempoScheduler] partagé pour la cadence du timer.
final tempoSchedulerProvider = Provider<TempoScheduler>((ref) {
  final scheduler = TempoScheduler();
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
