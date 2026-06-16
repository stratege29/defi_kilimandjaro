import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:defi_kilimandjaro/audio/audio_engine.dart';
import 'package:defi_kilimandjaro/audio/tempo_scheduler.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// État immutable de l'audio (mute + volume + feedback haptique + politique
/// vis-à-vis du switch silencieux iOS).
class AudioState {
  const AudioState({
    required this.muted,
    required this.volume,
    required this.hapticsEnabled,
    required this.respectSilentSwitch,
  });

  /// Préférences par défaut (utilisées avant chargement de SharedPreferences).
  ///
  /// - [hapticsEnabled] = true : le feedback haptique est couplé aux sons.
  /// - [respectSilentSwitch] = false : on conserve la catégorie `.playback`
  ///   éprouvée (coexistence avec les pubs AdMob). L'utilisateur peut activer
  ///   le respect du mode silencieux (`.ambient`) dans les réglages.
  factory AudioState.defaults() => const AudioState(
        muted: false,
        volume: 0.8,
        hapticsEnabled: true,
        respectSilentSwitch: false,
      );

  final bool muted;
  final double volume;
  final bool hapticsEnabled;
  final bool respectSilentSwitch;

  AudioState copyWith({
    bool? muted,
    double? volume,
    bool? hapticsEnabled,
    bool? respectSilentSwitch,
  }) =>
      AudioState(
        muted: muted ?? this.muted,
        volume: volume ?? this.volume,
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
        respectSilentSwitch: respectSilentSwitch ?? this.respectSilentSwitch,
      );
}

/// Intensités haptiques couplées aux cues audio du gameplay.
enum GameHaptic {
  /// Tick discret (sélection/désélection de lettre).
  select,

  /// Impact léger (indice).
  light,

  /// Impact moyen (mot complété).
  medium,

  /// Impact fort (victoire, mauvaise réponse, échec).
  heavy,
}

/// API publique du système audio, exposée via [audioControllerProvider].
///
/// **Toutes les méthodes `play*` sont fire-and-forget** : asynchrones,
/// non-bloquantes, et ignorent silencieusement les erreurs (cf. spec p.12).
class AudioController extends StateNotifier<AudioState>
    with WidgetsBindingObserver {
  AudioController(this._engine) : super(AudioState.defaults()) {
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
    unawaited(_subscribeBecomingNoisy());
  }

  static const String _keyMuted = 'audio_muted';
  static const String _keyVolume = 'audio_volume';
  static const String _keyHaptics = 'audio_haptics';
  static const String _keyRespectSilent = 'audio_respect_silent';

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

  /// Intention de boucler la recherche lobby : permet de relancer le loop
  /// au retour de l'arrière-plan sans le ressusciter après un match/arrêt.
  bool _lobbyLoopWanted = false;

  /// Abonnement « sortie audio débranchée » (casque/BT).
  StreamSubscription<void>? _noisySub;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_noisySub?.cancel());
    _cancelLobbyLoop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Annule le Timer du loop lobby : stoppe les réveils toutes les
        // 278 ms en arrière-plan (économie batterie). L'intention
        // [_lobbyLoopWanted] est conservée pour reprise au resume.
        _cancelLobbyLoop();
      case AppLifecycleState.resumed:
        if (_lobbyLoopWanted) unawaited(playLobbySearchLoop());
      case AppLifecycleState.inactive:
        break;
    }
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

  /// Active/désactive le feedback haptique (persisté). Indépendant du mute
  /// sonore — un joueur peut couper le son et garder les vibrations.
  Future<void> setHapticsEnabled({required bool enabled}) async {
    state = state.copyWith(hapticsEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHaptics, enabled);
  }

  /// Bascule le feedback haptique (persisté).
  Future<void> toggleHaptics() => setHapticsEnabled(enabled: !state.hapticsEnabled);

  /// Active/désactive le respect du switch silencieux iOS (persisté).
  ///
  /// - `true`  → catégorie `.ambient` : les SFX se taisent en mode silencieux.
  /// - `false` → catégorie `.playback` (défaut) : le son joue toujours, et la
  ///   session coexiste avec les pubs AdMob sans rester muette (comportement
  ///   historique éprouvé).
  Future<void> setRespectSilentSwitch({required bool respect}) async {
    state = state.copyWith(respectSilentSwitch: respect);
    await _engine.setRespectSilentSwitch(respect: respect);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRespectSilent, respect);
  }

  /// Bascule le respect du switch silencieux (persisté).
  Future<void> toggleRespectSilentSwitch() =>
      setRespectSilentSwitch(respect: !state.respectSilentSwitch);

  /// Déclenche le feedback haptique [kind] si activé. Couplé aux cues audio
  /// du gameplay — source unique pour garantir la synchro son↔vibration.
  void _fireHaptic(GameHaptic kind) {
    if (!state.hapticsEnabled) return;
    switch (kind) {
      case GameHaptic.select:
        unawaited(HapticFeedback.selectionClick());
      case GameHaptic.light:
        unawaited(HapticFeedback.lightImpact());
      case GameHaptic.medium:
        unawaited(HapticFeedback.mediumImpact());
      case GameHaptic.heavy:
        unawaited(HapticFeedback.heavyImpact());
    }
  }

  /// Feedback haptique seul (sans son) — désélection d'une lettre.
  void hapticDeselect() => _fireHaptic(GameHaptic.select);

  /// Suspend le moteur (entre niveaux — cf. maquette p.12).
  /// Arrête également le loop lobby si actif.
  void suspend() {
    _cancelLobbyLoop();
    _engine.suspend();
  }

  /// Reprend le moteur après [suspend].
  void resume() => _engine.resume();

  // ─── API ludique (cf. maquette p.12) ────────────────────────────────────

  /// Sélection d'une lettre — balafon pentatonique ascendant + tick haptique.
  Future<void> playLetterSelect(int letterIdx) {
    _fireHaptic(GameHaptic.select);
    final cue = switch (letterIdx % 5) {
      0 => AudioCue.letterSelect0,
      1 => AudioCue.letterSelect1,
      2 => AudioCue.letterSelect2,
      3 => AudioCue.letterSelect3,
      _ => AudioCue.letterSelect4,
    };
    return _engine.play(cue);
  }

  /// Mot complété — accord balafon ascendant 5 notes + impact moyen.
  Future<void> playWordComplete() {
    _fireHaptic(GameHaptic.medium);
    return _engine.play(AudioCue.wordComplete);
  }

  /// Indice utilisé — kora 2 notes descendantes douces + impact léger.
  Future<void> playHintUsed() {
    _fireHaptic(GameHaptic.light);
    return _engine.play(AudioCue.hintUsed);
  }

  /// Victoire — fanfare griot (balafon + kora + tam-tam) + impact fort.
  Future<void> playVictory() {
    _fireHaptic(GameHaptic.heavy);
    return _engine.play(AudioCue.victory);
  }

  /// Victoire BOSS — fanfare enrichie (intro djembé grave + griot
  /// élargi + queue tam-tam, ~2.8 s) + impact fort.
  Future<void> playBossVictory() {
    _fireHaptic(GameHaptic.heavy);
    return _engine.play(AudioCue.bossVictory);
  }

  /// Échec — balafon descendant + tam-tam lent + impact fort.
  Future<void> playFailure() {
    _fireHaptic(GameHaptic.heavy);
    return _engine.play(AudioCue.failure);
  }

  /// Mauvaise réponse — djembé x2 + impact fort.
  Future<void> playWrongAnswer() {
    _fireHaptic(GameHaptic.heavy);
    return _engine.play(AudioCue.wrongAnswer);
  }

  /// Tick timer — sweep tam-tam 160→60 Hz. **Pas d'haptique** : à 140 BPM le
  /// tic-tac est trop rapide pour des vibrations (gêne + batterie).
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
    _lobbyLoopWanted = true;
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
    _lobbyLoopWanted = false;
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
    // Match trouvé : la recherche est terminée — on lève l'intention pour
    // qu'un retour d'arrière-plan ne relance pas le loop.
    _lobbyLoopWanted = false;
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

  /// S'abonne à l'événement « sortie audio débranchée » (casque/Bluetooth).
  /// Best practice mobile : ne pas continuer à diffuser le loop continu sur
  /// le haut-parleur. On stoppe la recherche lobby (les SFX ponctuels, eux,
  /// restent permis — ils sont courts et déclenchés par l'utilisateur).
  Future<void> _subscribeBecomingNoisy() async {
    try {
      final session = await AudioSession.instance;
      _noisySub = session.becomingNoisyEventStream.listen((_) {
        unawaited(stopLobbySearchLoop());
      });
    } on Object catch (e) {
      _log.w('AudioController: becomingNoisy subscription failed: $e');
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final muted = prefs.getBool(_keyMuted) ?? false;
      final volume = prefs.getDouble(_keyVolume) ?? 0.8;
      final haptics = prefs.getBool(_keyHaptics) ?? true;
      final respectSilent = prefs.getBool(_keyRespectSilent) ?? false;
      state = AudioState(
        muted: muted,
        volume: volume,
        hapticsEnabled: haptics,
        respectSilentSwitch: respectSilent,
      );
      _engine
        ..setMuted(muted: muted)
        ..setVolume(volume);
      // N'impose la reconfiguration de session que si l'utilisateur a opté
      // pour le respect du silencieux (sinon on garde la config `.playback`
      // déjà posée par AudioEngine.init() — pas de reconfig inutile).
      if (respectSilent) {
        await _engine.setRespectSilentSwitch(respect: true);
      }
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
    // `Timer.cancel()` n'empêche pas un tick déjà mis en file de s'exécuter.
    // Lire `state` après dispose lève `StateNotifierDisposedException`.
    if (!mounted) return;
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
