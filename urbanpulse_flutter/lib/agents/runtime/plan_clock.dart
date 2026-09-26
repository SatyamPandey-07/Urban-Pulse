/// The planning stopwatch. It only measures: it counts the time the system
/// itself spends (paused while the traveller answers a question) for the
/// timings shown with the plan. Nothing in the planner is cut short by it:
/// a plan ends when its goal is met, never because time ran out.
class PlanClock {
  PlanClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  DateTime? _startedAt;
  DateTime? _pausedAt;
  Duration _paused = Duration.zero;
  int _pauseDepth = 0;

  bool get started => _startedAt != null;

  void start() {
    _startedAt ??= _now();
  }

  /// Pauses (re-entrant: several questions can be open at once). Returns
  /// nothing; call [resume] once per [pause].
  void pause() {
    if (!started) return;
    if (_pauseDepth == 0) _pausedAt = _now();
    _pauseDepth++;
  }

  void resume() {
    if (_pauseDepth == 0) return;
    _pauseDepth--;
    if (_pauseDepth == 0 && _pausedAt != null) {
      _paused += _now().difference(_pausedAt!);
      _pausedAt = null;
    }
  }

  bool get isPaused => _pauseDepth > 0;

  /// Time the system has actually spent, excluding waits on the user.
  Duration get elapsed {
    final s = _startedAt;
    if (s == null) return Duration.zero;
    final now = _now();
    final currentPause = _pausedAt == null ? Duration.zero : now.difference(_pausedAt!);
    final active = now.difference(s) - _paused - currentPause;
    return active.isNegative ? Duration.zero : active;
  }
}
