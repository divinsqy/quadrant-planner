import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/planning/work_calendar.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/tasks/task.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/tasks/workload.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/task_trajectory_builder.dart';

void main() {
  test('reconstructs daily positions across base urgency and deadline changes', () {
    final calendar = WorkCalendar(
      schedule: WorkSchedule.standard(),
      coveredYears: const {2026},
      holidays: const {},
    );
    final builder = TaskTrajectoryBuilder(calendar: calendar);
    final base = task(
      importance: 60,
      baseUrgency: 30,
      anchor: DateTime(2026, 9, 28, 9),
      deadline: null,
    );

    final points = builder.build(
      task: base,
      snapshots: [
        TaskTrajectorySnapshot(
          occurredAt: DateTime(2026, 9, 30, 9),
          importance: 80,
          baseUrgency: 70,
          baseUrgencyAnchorAt: DateTime(2026, 9, 30, 9),
          deadline: DateTime(2026, 10, 5, 18),
        ),
      ],
      from: DateTime(2026, 9, 28),
      to: DateTime(2026, 10, 1),
    );

    expect(points, hasLength(4));
    expect(points.first.importance, 60);
    expect(points.first.urgency, 30);
    expect(points[1].urgency, greaterThan(30));

    expect(points[2].localDate, DateTime(2026, 9, 30));
    expect(points[2].importance, 80);
    expect(points[2].urgency, greaterThanOrEqualTo(70));
    expect(points.last.importance, 80);
    expect(points.last.urgency, greaterThanOrEqualTo(points[2].urgency));
  });

  test('later snapshots win without mutating the input task', () {
    final calendar = WorkCalendar(
      schedule: WorkSchedule.standard(),
      coveredYears: const {2026},
      holidays: const {},
    );
    final builder = TaskTrajectoryBuilder(calendar: calendar);
    final base = task(
      importance: 40,
      baseUrgency: 20,
      anchor: DateTime(2026, 9, 28),
      deadline: null,
    );

    final points = builder.build(
      task: base,
      snapshots: [
        TaskTrajectorySnapshot(
          occurredAt: DateTime(2026, 9, 29, 8),
          importance: 55,
          baseUrgency: 25,
          baseUrgencyAnchorAt: DateTime(2026, 9, 29, 8),
          deadline: null,
        ),
        TaskTrajectorySnapshot(
          occurredAt: DateTime(2026, 9, 29, 16),
          importance: 75,
          baseUrgency: 60,
          baseUrgencyAnchorAt: DateTime(2026, 9, 29, 16),
          deadline: null,
        ),
      ],
      from: DateTime(2026, 9, 29),
      to: DateTime(2026, 9, 29),
    );

    expect(points.single.importance, 75);
    expect(points.single.urgency, 60);
    expect(base.importance, 40);
    expect(base.baseUrgency, 20);
  });
}

Task task({
  required int importance,
  required int baseUrgency,
  required DateTime anchor,
  required DateTime? deadline,
}) {
  return Task.create(
    id: 'task',
    title: 'Trajectory task',
    description: '',
    status: TaskStatus.planned,
    projectId: null,
    importance: importance,
    baseUrgency: baseUrgency,
    baseUrgencyAnchorAt: anchor,
    deadline: deadline,
    estimatedMinutes: 60,
    workload: Workload.medium,
    progress: 0,
    includeInWeeklyReport: true,
    createdAt: DateTime(2026, 9, 28),
    updatedAt: anchor,
  );
}
