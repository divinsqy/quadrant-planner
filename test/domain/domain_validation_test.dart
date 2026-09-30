import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/settings/app_preferences.dart';
import 'package:quadrant_planner/domain/tasks/task.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/tasks/workload.dart';

Task buildTask({
  String title = '  DMA task  ',
  int importance = 50,
  int baseUrgency = 50,
  int progress = 0,
}) {
  final now = DateTime.utc(2026, 9, 30, 2);
  return Task.create(
    id: 'task-1',
    title: title,
    description: 'note',
    status: TaskStatus.planned,
    projectId: null,
    importance: importance,
    baseUrgency: baseUrgency,
    baseUrgencyAnchorAt: now,
    deadline: null,
    estimatedMinutes: 60,
    workload: Workload.medium,
    progress: progress,
    includeInWeeklyReport: true,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('Task.create trims title and accepts 0 and 100 score boundaries', () {
    final low = buildTask(title: '  DMA task  ', importance: 0, baseUrgency: 0);
    final high = buildTask(importance: 100, baseUrgency: 100, progress: 100);

    expect(low.title, 'DMA task');
    expect(low.importance, 0);
    expect(low.baseUrgency, 0);
    expect(high.importance, 100);
    expect(high.baseUrgency, 100);
    expect(high.progress, 100);
  });

  test('Task.create rejects empty title', () {
    expect(() => buildTask(title: '   '), throwsArgumentError);
  });

  test('Task.create rejects scores and progress outside 0 to 100', () {
    expect(() => buildTask(importance: -1), throwsArgumentError);
    expect(() => buildTask(importance: 101), throwsArgumentError);
    expect(() => buildTask(baseUrgency: -1), throwsArgumentError);
    expect(() => buildTask(baseUrgency: 101), throwsArgumentError);
    expect(() => buildTask(progress: -1), throwsArgumentError);
    expect(() => buildTask(progress: 101), throwsArgumentError);
  });

  test('Task.copyWith preserves identity while applying explicit updates', () {
    final original = buildTask();
    final changed = original.copyWith(title: 'Updated', progress: 40);

    expect(changed.id, original.id);
    expect(changed.title, 'Updated');
    expect(changed.progress, 40);
    expect(changed.baseUrgency, original.baseUrgency);
    expect(changed.createdAt, original.createdAt);
  });

  test('default app preferences use midpoint quadrant thresholds and blank nickname', () {
    final settings = AppPreferences.defaults();

    expect(settings.importanceThreshold, 50);
    expect(settings.urgencyThreshold, 50);
    expect(settings.nickname, '');
  });
}
