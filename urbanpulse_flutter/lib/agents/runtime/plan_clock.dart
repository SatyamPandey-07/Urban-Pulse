/// The planning stopwatch. The 45-60 s target counts only the time the system
/// itself spends, so the clock is paused while the user is answering a
/// question.
class PlanClock {
  PlanClock({
    DateTime Function()? now,
    this.degradeAfter = const Duration(seconds: 35),
    this.deadline = const Duration(seconds: 60),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// After this much active time the planner stops optional work (extra
  /// verification, second-opinion lookups) so a result is always produced.
  final Duration degradeAfter;

  /// The hard target.
  final Duration deadline;

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

  bool get degraded => elapsed >= degradeAfter;

  bool get expired => elapsed >= deadline;

  Duration get remaining {
    final r = deadline - elapsed;
    return r.isNegative ? Duration.zero : r;
  }
}
