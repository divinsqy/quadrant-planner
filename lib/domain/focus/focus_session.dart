enum FocusSessionState { running, paused, completed, blocked }

class FocusInterval {
  final DateTime start;
  final DateTime? end;
  const FocusInterval({required this.start, this.end});
}

class FocusSession {
  final String id;
  final String taskId;
  final String? planBlockId;
  final FocusSessionState state;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<FocusInterval> intervals;
  FocusSession({
    required this.id,
    required this.taskId,
    this.planBlockId,
    required this.state,
    required this.startedAt,
    this.endedAt,
    required List<FocusInterval> intervals,
  }) : intervals = List.unmodifiable(intervals);

  bool get isActive =>
      state == FocusSessionState.running || state == FocusSessionState.paused;
  Duration elapsed(DateTime at) {
    var micros = 0;
    for (final interval in intervals) {
      final delta = (interval.end ?? at)
          .difference(interval.start)
          .inMicroseconds;
      if (delta > 0) micros += delta;
    }
    return Duration(microseconds: micros);
  }
}
