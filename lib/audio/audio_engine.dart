import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:defi_kilimandjaro/audio/instruments/balafon.dart';
import 'package:defi_kilimandjaro/audio/instruments/boss_fanfare.dart';
import 'package:defi_kilimandjaro/audio/instruments/djembe.dart';
import 'package:defi_kilimandjaro/audio/instruments/duel_round_end.dart';
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

  /// Victoire BOSS — fanfare griot enrichie (intro djembé grave + queue
  /// tam-tam, ~2.8 s vs 2 s pour victoire standard).
  bossVictory,

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

  // ─── Duel — fin de manche (3-manches) ───────────────────────────────────

  /// Arpège kora ascendant C major + roulement djembé — manche gagnée (~950 ms).
  roundWon,

  /// Note balafon grave descendante + ride courte — manche perdue (~800 ms).
  roundLost,

  /// Accord kora suspendu sans tierce — manche nulle (~750 ms).
  roundDraw,
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
      // Configure AVAudioSession AVANT SoLoud — sans ça, miniaudio (sous
      // flutter_soloud) hérite de la category `.ambient` par défaut sur iOS,
      // qui se fait évincer dès que google_mobile_ads active `.playback`
      // exclusif pour une pub. Résultat : SoLoud reste muet jusqu'à un
      // deinit/init complet. `playback` + `mixWithOthers` laisse coexister
      // les pubs et la synthèse sans conflit de session.
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.game,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );
      await session.setActive(true);

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
  ///
  /// **Lazy-load** : si le cue n'est pas encore chargé en mémoire SoLoud,
  /// il est synthétisé et chargé à la volée. La 1ère lecture d'un cue
  /// donné prend ~50ms supplémentaires, ensuite cache.
  Future<void> play(AudioCue cue) async {
    if (!_initialized || _suspended || _muted) return;
    var src = _sources[cue];
    if (src == null) {
      src = await _loadCue(cue);
      if (src == null) return;
    }
    try {
      await SoLoud.instance.play(src);
    } on Object catch (e) {
      _log.w('AudioEngine.play($cue) failed: $e');
    }
  }

  /// Synthétise + charge UN cue dans SoLoud. Retourne null en cas d'échec.
  /// Idempotent : ne réalloue pas si déjà chargé.
  Future<AudioSource?> _loadCue(AudioCue cue) async {
    final existing = _sources[cue];
    if (existing != null) return existing;
    try {
      final pcm = _renderCue(cue);
      final src = await SoLoud.instance.loadMem(
        'kilimandjaro_${cue.name}.wav',
        pcm,
      );
      _sources[cue] = src;
      return src;
    } on Object catch (e) {
      _log.w('Lazy load $cue failed: $e');
      return null;
    }
  }

  /// Synthèse PCM à la demande — un seul cue à la fois pour ne pas saturer
  /// la mémoire (vs _preloadAll qui les rendait tous d'un coup).
  Uint8List _renderCue(AudioCue cue) {
    switch (cue) {
      case AudioCue.letterSelect0:
        return Balafon.renderLetterNote(0);
      case AudioCue.letterSelect1:
        return Balafon.renderLetterNote(1);
      case AudioCue.letterSelect2:
        return Balafon.renderLetterNote(2);
      case AudioCue.letterSelect3:
        return Balafon.renderLetterNote(3);
      case AudioCue.letterSelect4:
        return Balafon.renderLetterNote(4);
      case AudioCue.wordComplete:
        return Balafon.renderAscendingChord();
      case AudioCue.hintUsed:
        return Kora.renderHint();
      case AudioCue.victory:
        return GriotFanfare.render();
      case AudioCue.bossVictory:
        return BossFanfare.render();
      case AudioCue.failure:
        return _renderFailure();
      case AudioCue.wrongAnswer:
        return Djembe.renderWrongDouble();
      case AudioCue.timerTick:
        return TamTam.renderTick();
      case AudioCue.lobbyLoopDoum:
        return LobbyDuel.renderLoopDoum();
      case AudioCue.lobbyLoopTac:
        return LobbyDuel.renderLoopTac();
      case AudioCue.lobbyMatchFound:
        return LobbyDuel.renderMatchFound();
      case AudioCue.duelStart:
        return LobbyDuel.renderDuelStart();
      case AudioCue.roundWon:
        return DuelRoundEnd.renderRoundWon();
      case AudioCue.roundLost:
        return DuelRoundEnd.renderRoundLost();
      case AudioCue.roundDraw:
        return DuelRoundEnd.renderRoundDraw();
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
      AudioCue.bossVictory: BossFanfare.render(),
      AudioCue.failure: _renderFailure(),
      AudioCue.wrongAnswer: Djembe.renderWrongDouble(),
      AudioCue.timerTick: TamTam.renderTick(),
      // Lobby / duel cues (PR #2)
      AudioCue.lobbyLoopDoum: LobbyDuel.renderLoopDoum(),
      AudioCue.lobbyLoopTac: LobbyDuel.renderLoopTac(),
      AudioCue.lobbyMatchFound: LobbyDuel.renderMatchFound(),
      AudioCue.duelStart: LobbyDuel.renderDuelStart(),
      // Duel round-end cues (3-manches)
      AudioCue.roundWon: DuelRoundEnd.renderRoundWon(),
      AudioCue.roundLost: DuelRoundEnd.renderRoundLost(),
      AudioCue.roundDraw: DuelRoundEnd.renderRoundDraw(),
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
