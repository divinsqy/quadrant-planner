import '../../../domain/planning/work_calendar.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_activity_event.dart';
import '../quadrant/task_trajectory_builder.dart';

/// Rewinds the current scores using recorded before/after values. The resulting
/// daily positions are derived in memory; no daily snapshots are persisted.
class ActivityTrajectory {
  final WorkCalendar calendar;
  const ActivityTrajectory({required this.calendar});

  List<TaskTrajectoryPoint> build({
    required Task task,
    required List<TaskActivityEvent> events,
    required DateTime from,
    required DateTime to,
  }) {
    final ordered =
        events
            .where(
              (event) =>
                  !event.occurredAt.isBefore(from.toUtc()) &&
                  !event.occurredAt.isAfter(to.toUtc()),
            )
            .toList()
          ..sort((a, b) {
            final byTime = a.occurredAt.compareTo(b.occurredAt);
            return byTime == 0 ? a.id.compareTo(b.id) : byTime;
          });
    var historical = task;
    Task apply(Task current, TaskActivityEvent event, String side) {
      final changes = event.payload['changes'];
      if (changes is! Map) return current;
      Object? value(String key, Object? fallback) {
        final entry = changes[key];
        return entry is Map && entry.containsKey(side) ? entry[side] : fallback;
      }

      DateTime? date(Object? value) =>
          value is String ? DateTime.tryParse(value) : value as DateTime?;
      return current.copyWith(
        importance: value('importance', current.importance) as int,
        baseUrgency: value('baseUrgency', current.baseUrgency) as int,
        baseUrgencyAnchorAt: date(
          value('baseUrgencyAnchorAt', current.baseUrgencyAnchorAt),
        ),
        deadline: date(value('deadline', current.deadline)),
      );
    }

    for (final event in ordered.reversed) {
      historical = apply(historical, event, 'before');
    }
    TaskTrajectorySnapshot snapshot(Task value, DateTime at) =>
        TaskTrajectorySnapshot(
          occurredAt: at,
          importance: value.importance,
          baseUrgency: value.baseUrgency,
          baseUrgencyAnchorAt: value.baseUrgencyAnchorAt,
          deadline: value.deadline,
        );
    final snapshots = [snapshot(historical, from.toUtc())];
    for (final event in ordered) {
      historical = apply(historical, event, 'after');
      snapshots.add(snapshot(historical, event.occurredAt));
    }
    return TaskTrajectoryBuilder(calendar: calendar)
        .build(task: task, snapshots: snapshots, from: from, to: to);
  }
}
