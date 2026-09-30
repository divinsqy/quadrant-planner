import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/planning/work_calendar.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/tasks/task.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/tasks/workload.dart';
import 'package:quadrant_planner/domain/urgency/urgency_engine.dart';

void main() {
  late WorkCalendar calendar;
  late UrgencyEngine engine;

  setUp(() {
    calendar = WorkCalendar(
      schedule: WorkSchedule.standard(),
      coveredYears: const {2026},
      holidays: const {},
    );
    engine = UrgencyEngine(calendar: calendar);
  });

  test('base 35 gains 1.5 urgency per elapsed workday', () {
    final task = _task(
      baseUrgency: 35,
      anchor: DateTime(2026, 9, 14),
    );

    final result = engine.calculate(task, DateTime(2026, 9, 28, 15));

    expect(result.ageComponent, 50);
    expect(result.deadlineComponent, isNull);
    expect(result.value, 50);
    expect(result.calendarEstimated, isFalse);
  });

  test('deadline pressure is 50 with three remaining workdays', () {
    final task = _task(
      baseUrgency: 10,
      anchor: DateTime(2026, 9, 28),
      deadline: DateTime(2026, 10, 1, 18),
    );

    final result = engine.calculate(task, DateTime(2026, 9, 28, 9));

    expect(result.deadlineComponent, closeTo(50, 0.0001));
    expect(result.value, 50);
  });

  test('due today and overdue tasks clamp deadline pressure to 100', () {
    final dueToday = _task(
      baseUrgency: 5,
      anchor: DateTime(2026, 9, 28),
      deadline: DateTime(2026, 9, 28, 18),
    );
    final overdue = _task(
      baseUrgency: 5,
      anchor: DateTime(2026, 9, 28),
      deadline: DateTime(2026, 9, 25, 18),
    );

    expect(
      engine.calculate(dueToday, DateTime(2026, 9, 28, 9)).value,
      100,
    );
    expect(
      engine.calculate(overdue, DateTime(2026, 9, 28, 9)).value,
      100,
    );
  });

  test('current urgency is the maximum of age and deadline pressure', () {
    final task = _task(
      baseUrgency: 80,
      anchor: DateTime(2026, 9, 28),
      deadline: DateTime(2026, 10, 1),
    );

    final result = engine.calculate(task, DateTime(2026, 9, 28));

    expect(result.ageComponent, 80);
    expect(result.deadlineComponent, closeTo(50, 0.0001));
    expect(result.value, 80);
  });

  test('manual base urgency edit restarts aging from the new anchor', () {
    final original = _task(
      baseUrgency: 35,
      anchor: DateTime(2026, 9, 1),
    );
    final edited = original.copyWith(
      baseUrgency: 70,
      baseUrgencyAnchorAt: DateTime(2026, 9, 10),
      updatedAt: DateTime(2026, 9, 10),
    );

    final result = engine.calculate(edited, DateTime(2026, 9, 11));

    expect(result.ageComponent, 71.5);
    expect(result.value, 72);
  });

  test('urgency clamps to 100 and reports estimated calendar fallback', () {
    final task = _task(
      baseUrgency: 99,
      anchor: DateTime(2026, 12, 31),
    );

    final result = engine.calculate(task, DateTime(2027, 1, 4));

    expect(result.value, 100);
    expect(result.calendarEstimated, isTrue);
  });
}

Task _task({
  required int baseUrgency,
  required DateTime anchor,
  DateTime? deadline,
}) {
  return Task.create(
    id: 'task',
    title: 'Task',
    description: '',
    status: TaskStatus.planned,
    projectId: null,
    importance: 50,
    baseUrgency: baseUrgency,
    baseUrgencyAnchorAt: anchor,
    deadline: deadline,
    estimatedMinutes: 60,
    workload: Workload.medium,
    progress: 0,
    includeInWeeklyReport: true,
    createdAt: anchor,
    updatedAt: anchor,
  );
}
