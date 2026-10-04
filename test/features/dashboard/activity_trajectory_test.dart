import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/planning/work_calendar.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/tasks/task.dart';
import 'package:quadrant_planner/domain/tasks/task_activity_event.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/tasks/workload.dart';
import 'package:quadrant_planner/features/dashboard/application/activity_trajectory.dart';

void main() {
  test(
    'trajectory restores before values then applies recorded score changes',
    () {
      final start = DateTime(2026, 9, 28);
      final changed = DateTime(2026, 9, 30, 9);
      final task = Task.create(
        id: 't',
        title: 'Trajectory',
        description: '',
        status: TaskStatus.planned,
        projectId: null,
        importance: 80,
        baseUrgency: 70,
        baseUrgencyAnchorAt: changed,
        deadline: null,
        estimatedMinutes: 30,
        workload: Workload.small,
        progress: 0,
        includeInWeeklyReport: true,
        createdAt: start,
        updatedAt: changed,
      );
      final events = [
        TaskActivityEvent(
          id: 'e1',
          taskId: 't',
          type: 'task_updated',
          occurredAt: changed,
          payload: {
            'changes': {
              'importance': {'before': 30, 'after': 80},
              'baseUrgency': {'before': 20, 'after': 70},
              'baseUrgencyAnchorAt': {
                'before': start.toUtc().toIso8601String(),
                'after': changed.toUtc().toIso8601String(),
              },
            },
          },
        ),
      ];
      final points = ActivityTrajectory(
        calendar: WorkCalendar(
          schedule: WorkSchedule.standard(),
          coveredYears: const {2026},
          holidays: const {},
        ),
      ).build(task: task, events: events, from: start, to: changed);
      expect(points.map((p) => p.importance), [30, 30, 80]);
      expect(points.first.urgency, 20);
      expect(points.last.urgency, 70);
    },
  );
}
