import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/projects/project_progress.dart';
import 'package:quadrant_planner/domain/tasks/task.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/tasks/workload.dart';

void main() {
  test('five completed minutes do not equal three unfinished workdays', () {
    expect(
      calculateProjectProgress([
        _task('quick', minutes: 5, status: TaskStatus.completed),
        _task('large', minutes: 1260),
      ]),
      closeTo(0.3952569, 0.000001),
    );
  });

  test('missing estimates use 30, 60 and 120 minute workload weights', () {
    expect(
      calculateProjectProgress([
        _task('small', workload: Workload.small, status: TaskStatus.completed),
        _task('medium', workload: Workload.medium, progress: 50),
        _task('large', workload: Workload.large),
      ]),
      closeTo(14.2857143, 0.000001),
    );
  });

  test(
    'only completed tasks contribute their duration to project completion',
    () {
      expect(
        calculateProjectProgress([
          _task('partial', minutes: 20, progress: 50),
          _task('completed', minutes: 60, status: TaskStatus.completed),
        ]),
        75,
      );
      expect(
        calculateProjectProgress([_task('partial', minutes: 20, progress: 99)]),
        0,
      );
    },
  );

  test('cancelled and deleted tasks do not affect progress', () {
    expect(
      calculateProjectProgress([
        _task('done', minutes: 30, status: TaskStatus.completed),
        _task('cancelled', minutes: 300, status: TaskStatus.cancelled),
        _task('deleted', minutes: 300, deleted: true),
      ]),
      100,
    );
    expect(calculateProjectProgress([]), 0);
    expect(
      calculateProjectProgress([
        _task('cancelled', status: TaskStatus.cancelled),
      ]),
      0,
    );
  });
}

Task _task(
  String id, {
  int? minutes,
  Workload workload = Workload.medium,
  TaskStatus status = TaskStatus.planned,
  int progress = 0,
  bool deleted = false,
}) {
  final now = DateTime.utc(2026, 10, 1);
  return Task.create(
    id: id,
    title: id,
    description: '',
    status: status,
    projectId: 'project',
    importance: 50,
    baseUrgency: 50,
    baseUrgencyAnchorAt: now,
    deadline: null,
    estimatedMinutes: minutes,
    workload: workload,
    progress: progress,
    includeInWeeklyReport: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: deleted ? now : null,
  );
}
