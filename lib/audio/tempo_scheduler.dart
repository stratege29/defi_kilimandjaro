import 'dart:async';

/// Émet des ticks au rythme d'un BPM ajustable, utilisé pour cadencer
/// `AudioController.playTimerTick` pendant la partie (cf. maquette p.12).
///
/// Phases recommandées :
/// - 30s → 15s : 60 BPM
/// - 15s → 8s  : 90 BPM
/// - 8s → 0    : 140 BPM
class TempoScheduler {
  TempoScheduler({int bpm = 60}) : _bpm = bpm;

  final StreamController<int> _controller = StreamController<int>.broadcast();
  Timer? _timer;
  int _bpm;
  int _tickCount = 0;

  /// Stream des ticks (chaque event = numéro de tick incrémental).
  Stream<int> get ticks => _controller.stream;

  int get bpm => _bpm;

  /// Démarre l'émission des ticks au BPM courant.
  void start() {
    if (_timer != null) return;
    _scheduleNext();
  }

  /// Met à jour le BPM et reprogramme immédiatement le prochain tick.
  void setBpm(int bpm) {
    if (bpm <= 0 || bpm == _bpm) return;
    _bpm = bpm;
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
      _scheduleNext();
    }
  }

  /// Adapte automatiquement le BPM en fonction du temps restant (s).
  void updateForTimeLeft(int secondsLeft) {
    if (secondsLeft > 15) {
      setBpm(60);
    } else if (secondsLeft > 8) {
      setBpm(90);
    } else {
      setBpm(140);
    }
  }

  /// Stoppe l'émission. Le scheduler peut être redémarré via [start].
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Libère les ressources. Le scheduler n'est plus utilisable ensuite.
  Future<void> dispose() async {
    stop();
    await _controller.close();
  }

  void _scheduleNext() {
    final intervalMs = (60000 / _bpm).round();
    _timer = Timer(Duration(milliseconds: intervalMs), () {
      if (_controller.isClosed) return;
      _tickCount++;
      _controller.add(_tickCount);
      _timer = null;
      _scheduleNext();
    });
  }
}
