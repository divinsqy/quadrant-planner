import '../../../domain/planning/work_calendar.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/urgency/urgency_engine.dart';

class TaskTrajectorySnapshot {
  final DateTime occurredAt;
  final int importance;
  final int baseUrgency;
  final DateTime baseUrgencyAnchorAt;
  final DateTime? deadline;

  const TaskTrajectorySnapshot({
    required this.occurredAt,
    required this.importance,
    required this.baseUrgency,
    required this.baseUrgencyAnchorAt,
    required this.deadline,
  });
}

class TaskTrajectoryPoint {
  final DateTime localDate;
  final int importance;
  final int urgency;

  const TaskTrajectoryPoint({
    required this.localDate,
    required this.importance,
    required this.urgency,
  });
}

class TaskTrajectoryBuilder {
  final WorkCalendar calendar;

  const TaskTrajectoryBuilder({
    required this.calendar,
  });

  List<TaskTrajectoryPoint> build({
    required Task task,
    required List<TaskTrajectorySnapshot> snapshots,
    required DateTime from,
    required DateTime to,
  }) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) {
      throw ArgumentError('trajectory end must not precede start');
    }

    final sorted = [...snapshots]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    var snapshotIndex = 0;
    var importance = task.importance;
    var baseUrgency = task.baseUrgency;
    var anchor = task.baseUrgencyAnchorAt;
    DateTime? deadline = task.deadline;
    final engine = UrgencyEngine(calendar: calendar);
    final result = <TaskTrajectoryPoint>[];

    var cursor = start;
    while (!cursor.isAfter(end)) {
      final endOfDay = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        23,
        59,
        59,
        999,
      );

      while (snapshotIndex < sorted.length &&
          !sorted[snapshotIndex].occurredAt.toLocal().isAfter(endOfDay)) {
        final change = sorted[snapshotIndex];
        importance = change.importance;
        baseUrgency = change.baseUrgency;
        anchor = change.baseUrgencyAnchorAt;
        deadline = change.deadline;
        snapshotIndex += 1;
      }

      final derived = task.copyWith(
        importance: importance,
        baseUrgency: baseUrgency,
        baseUrgencyAnchorAt: anchor,
        deadline: deadline,
        updatedAt: endOfDay.toUtc(),
      );
      final urgency = engine.calculate(derived, endOfDay);

      result.add(
        TaskTrajectoryPoint(
          localDate: cursor,
          importance: importance,
          urgency: urgency.value,
        ),
      );
      cursor = cursor.add(const Duration(days: 1));
    }

    return List.unmodifiable(result);
  }
}
