import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/quadrant/quadrant.dart';
import 'package:quadrant_planner/domain/quadrant/quadrant_engine.dart';
import 'package:quadrant_planner/domain/tasks/task.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/tasks/workload.dart';

void main() {
  const engine = QuadrantEngine();

  test('values exactly on both thresholds are classified on the high side', () {
    expect(
      engine.classify(
        importance: 50,
        urgency: 50,
        importanceThreshold: 50,
        urgencyThreshold: 50,
      ),
      Quadrant.doNow,
    );
  });

  test('classifies all four sides of the threshold boundary', () {
    expect(
      engine.classify(
        importance: 50,
        urgency: 49,
        importanceThreshold: 50,
        urgencyThreshold: 50,
      ),
      Quadrant.plan,
    );
    expect(
      engine.classify(
        importance: 49,
        urgency: 50,
        importanceThreshold: 50,
        urgencyThreshold: 50,
      ),
      Quadrant.expedite,
    );
    expect(
      engine.classify(
        importance: 49,
        urgency: 49,
        importanceThreshold: 50,
        urgencyThreshold: 50,
      ),
      Quadrant.lowPriority,
    );
  });

  test('moving thresholds changes classification without changing task values', () {
    final task = Task.create(
      id: 'task',
      title: 'Task',
      description: '',
      status: TaskStatus.planned,
      projectId: null,
      importance: 65,
      baseUrgency: 65,
      baseUrgencyAnchorAt: DateTime.utc(2026, 9, 30),
      deadline: null,
      estimatedMinutes: 60,
      workload: Workload.medium,
      progress: 0,
      includeInWeeklyReport: true,
      createdAt: DateTime.utc(2026, 9, 30),
      updatedAt: DateTime.utc(2026, 9, 30),
    );

    final stricter = engine.classify(
      importance: task.importance,
      urgency: task.baseUrgency,
      importanceThreshold: 70,
      urgencyThreshold: 60,
    );
    final looser = engine.classify(
      importance: task.importance,
      urgency: task.baseUrgency,
      importanceThreshold: 60,
      urgencyThreshold: 60,
    );

    expect(stricter, Quadrant.expedite);
    expect(looser, Quadrant.doNow);
    expect(task.importance, 65);
    expect(task.baseUrgency, 65);
  });

  test('rejects values or thresholds outside 0 to 100', () {
    expect(
      () => engine.classify(
        importance: -1,
        urgency: 50,
        importanceThreshold: 50,
        urgencyThreshold: 50,
      ),
      throwsArgumentError,
    );
    expect(
      () => engine.classify(
        importance: 50,
        urgency: 50,
        importanceThreshold: 101,
        urgencyThreshold: 50,
      ),
      throwsArgumentError,
    );
  });
}
