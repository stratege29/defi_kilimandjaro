import 'dart:typed_data';

import 'package:defi_kilimandjaro/audio/instruments/balafon.dart';
import 'package:defi_kilimandjaro/audio/instruments/djembe.dart';
import 'package:defi_kilimandjaro/audio/instruments/griot_fanfare.dart';
import 'package:defi_kilimandjaro/audio/instruments/kora.dart';
import 'package:defi_kilimandjaro/audio/instruments/lobby_duel.dart';
import 'package:defi_kilimandjaro/audio/instruments/tam_tam.dart';
import 'package:defi_kilimandjaro/audio/wav_buffer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:logger/logger.dart';

/// Identifiants logiques des sons pré-rendus.
///
/// Référence : maquette p.12 (instruments + spec synthèse procédurale).
enum AudioCue {
  /// Sélection lettre — 5 variantes (pentatonique).
  letterSelect0,
  letterSelect1,
  letterSelect2,
  letterSelect3,
  letterSelect4,

  /// Mot complété correctement — accord ascendant balafon.
  wordComplete,

  /// Indice utilisé — 2 notes kora descendantes.
  hintUsed,

  /// Victoire — fanfare griot.
  victory,

  /// Échec — balafon descendant + tam-tam lent.
  failure,

  /// Mauvaise réponse — djembé x2.
  wrongAnswer,

  /// Tick timer — sweep tam-tam.
  timerTick,

  // ─── Lobby matchmaking (Phase 6 — PR #2) ────────────────────────────────

  /// Frappe grave "DOUM" 108 BPM — sample unitaire utilisé par le loop lobby.
  lobbyLoopDoum,

  /// Frappe sèche "tac" — sample unitaire utilisé par le loop lobby.
  lobbyLoopTac,

  /// Ding! balafon G5→C6 + roulement djembé — adversaire trouvé (~620 ms).
  lobbyMatchFound,

  /// Gong kora C3 + frappe tam-tam très grave — démarrage du duel ranked (~820 ms).
  duelStart,
}

/// Singleton du moteur audio. Gère :
/// - lifecycle SoLoud (`init` / `deinit`)
/// - rendu et chargement en mémoire de tous les `AudioCue` (cf. maquette p.12)
/// - suspension globale entre niveaux + reprise
/// - réaction à `AppLifecycleState` (background → pause)
///
/// **Synthèse procédurale** : aucun fichier audio bundle, tout généré
/// à l'init via les instruments dans `lib/audio/instruments/`.
class AudioEngine with WidgetsBindingObserver {
  AudioEngine._();

  static final AudioEngine _instance = AudioEngine._();

  /// Instance unique.
  static AudioEngine get instance => _instance;

  final Logger _log = Logger();
  final Map<AudioCue, AudioSource> _sources = <AudioCue, AudioSource>{};

  bool _initialized = false;
  bool _suspended = false;
  bool _muted = false;
  double _volume = 0.8;

  /// Vrai après [init] et tant que [dispose] n'a pas été appelé.
  bool get isInitialized => _initialized;

  /// Vrai si l'audio est suspendu globalement (mute différé entre niveaux).
  bool get isSuspended => _suspended;

  /// Initialise SoLoud, synthétise et charge tous les cues en mémoire.
  ///
  /// **Doit être appelée une seule fois** avant `runApp` dans `main.dart`.
  /// Idempotente — appels multiples ignorés.
  Future<void> init() async {
    if (_initialized) return;
    try {
      await SoLoud.instance.init();
      WidgetsBinding.instance.addObserver(this);
      await _preloadAll();
      _initialized = true;
      _log.i('AudioEngine initialized — ${_sources.length} cues loaded');
    } on Object catch (e, st) {
      _log.e('AudioEngine init failed', error: e, stackTrace: st);
      // On reste utilisable en mode silencieux : tous les `play*` deviennent
      // des no-ops car `_initialized` reste false.
    }
  }

  /// Libère toutes les ressources audio. Le moteur n'est plus utilisable.
  Future<void> dispose() async {
    if (!_initialized) return;
    WidgetsBinding.instance.removeObserver(this);
    for (final src in _sources.values) {
      try {
        await SoLoud.instance.disposeSource(src);
      } on Object catch (_) {}
    }
    _sources.clear();
    SoLoud.instance.deinit();
    _initialized = false;
  }

  /// Suspend la lecture (mute différé) — typiquement appelé entre niveaux
  /// (cf. maquette p.12). Les `play*` deviennent des no-ops jusqu'à [resume].
  void suspend() => _suspended = true;

  /// Reprend la lecture après [suspend].
  void resume() => _suspended = false;

  /// Mute global piloté par `AudioController` (persisté).
  void setMuted({required bool muted}) {
    _muted = muted;
    if (_initialized) {
      SoLoud.instance.setGlobalVolume(_effectiveVolume);
    }
  }

  /// Volume global piloté par `AudioController` (persisté, [0,1]).
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    if (_initialized) {
      SoLoud.instance.setGlobalVolume(_effectiveVolume);
    }
  }

  /// Joue un cue de manière fire-and-forget. Aucune attente, aucune exception
  /// remontée — toute erreur est logguée puis avalée.
  Future<void> play(AudioCue cue) async {
    if (!_initialized || _suspended || _muted) return;
    final src = _sources[cue];
    if (src == null) {
      _log.w('AudioEngine.play: cue $cue not loaded');
      return;
    }
    try {
      await SoLoud.instance.play(src);
    } on Object catch (e) {
      _log.w('AudioEngine.play($cue) failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_initialized) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        SoLoud.instance.setGlobalVolume(0);
      case AppLifecycleState.resumed:
        SoLoud.instance.setGlobalVolume(_effectiveVolume);
    }
  }

  double get _effectiveVolume => _muted ? 0.0 : _volume;

  Future<void> _preloadAll() async {
    final cues = <AudioCue, Uint8List>{
      AudioCue.letterSelect0: Balafon.renderLetterNote(0),
      AudioCue.letterSelect1: Balafon.renderLetterNote(1),
      AudioCue.letterSelect2: Balafon.renderLetterNote(2),
      AudioCue.letterSelect3: Balafon.renderLetterNote(3),
      AudioCue.letterSelect4: Balafon.renderLetterNote(4),
      AudioCue.wordComplete: Balafon.renderAscendingChord(),
      AudioCue.hintUsed: Kora.renderHint(),
      AudioCue.victory: GriotFanfare.render(),
      AudioCue.failure: _renderFailure(),
      AudioCue.wrongAnswer: Djembe.renderWrongDouble(),
      AudioCue.timerTick: TamTam.renderTick(),
      // Lobby / duel cues (PR #2)
      AudioCue.lobbyLoopDoum: LobbyDuel.renderLoopDoum(),
      AudioCue.lobbyLoopTac: LobbyDuel.renderLoopTac(),
      AudioCue.lobbyMatchFound: LobbyDuel.renderMatchFound(),
      AudioCue.duelStart: LobbyDuel.renderDuelStart(),
    };
    for (final entry in cues.entries) {
      try {
        final src = await SoLoud.instance.loadMem(
          'kilimandjaro_${entry.key.name}.wav',
          entry.value,
        );
        _sources[entry.key] = src;
      } on Object catch (e) {
        _log.w('Failed to load cue ${entry.key}: $e');
      }
    }
  }

  /// Mix balafon descendant + tam-tam lent pour `playFailure` (maquette p.12).
  Uint8List _renderFailure() {
    final balafon = Balafon.renderDescendingGraveBuffer();
    final tam = TamTam.renderSlowDouble();
    final out = WavBuffer.silence(2);
    WavBuffer.mixInto(out, balafon, gain: 0.75);
    WavBuffer.mixInto(out, tam, gain: 0.5);
    WavBuffer.normalize(out, target: 0.9);
    return WavBuffer.encodeMono16(out);
  }
}
