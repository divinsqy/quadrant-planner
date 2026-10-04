import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/planning/planned_block.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/planner/application/planner_controller.dart';
import 'package:quadrant_planner/features/planner/data/planner_repository.dart';
import 'package:quadrant_planner/features/focus/data/focus_repository.dart';
import 'package:quadrant_planner/features/settings/data/preferences_repository.dart';
import 'package:quadrant_planner/features/settings/data/work_schedule_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late PlannerController controller;
  late PlannerRepository plans;
  late TaskRepository tasks;
  late WorkScheduleRepository schedules;
  final day = DateTime(2026, 10, 5);
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
    schedules = WorkScheduleRepository(db);
    plans = PlannerRepository(db, schedules: schedules);
    controller = PlannerController(
      plans: plans,
      tasks: tasks,
      schedules: schedules,
      preferences: PreferencesRepository(db),
      clock: () => day,
    );
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });
  test(
    'replan preserves active Focus block identity and completion marker',
    () async {
      final task = await tasks.createTask(
        const TaskDraft(
          title: 'Active block',
          status: TaskStatus.planned,
          estimatedMinutes: 60,
        ),
      );
      await controller.replan();
      final original = (await plans.day(day)).single;
      final focus = FocusRepository(db);
      await focus.start(
        task.id,
        day.add(const Duration(hours: 9)),
        planBlockId: original.id,
      );
      await controller.replan();
      expect((await focus.activeSession())!.planBlockId, original.id);
      final preserved = (await plans.day(day)).single;
      expect(preserved.start, original.start);
      expect(preserved.end, original.end);
      expect(preserved.isLocked, original.isLocked);
      await expectLater(plans.skipTask(task.id, day), throwsStateError);
      await focus.complete(
        day.add(const Duration(hours: 10)),
        completeTask: false,
      );
      expect((await plans.day(day)).single.completedAt, isNotNull);
      await controller.replan();
      expect((await plans.day(day)).single.id, original.id);
    },
  );
  test('reverse-date planning accounts for future unlocked and locked reservations', () async {
    await tasks.createTask(
      const TaskDraft(
        title: 'Reserved',
        status: TaskStatus.planned,
        estimatedMinutes: 60,
      ),
    );
    final tuesday = day.add(const Duration(days: 1));
    controller.selectDate(tuesday);
    await controller.replan();
    final reserved = (await plans.day(tuesday)).single;
    controller.selectDate(day);
    await controller.replan();
    expect(await plans.day(day), isEmpty);
    await plans.lockBlock(reserved.id, true);
    await schedules.saveWeekdays({
      1: [const TimeWindow(startMinutes: 420, endMinutes: 720)],
    });
    await controller.replan();
    expect(await plans.day(day), isEmpty);
    expect((await plans.day(tuesday)).single.id, reserved.id);
  });
  test(
    'replan subtracts locked duration and never duplicates reserved work',
    () async {
      final task = await tasks.createTask(
        const TaskDraft(
          title: 'Split',
          status: TaskStatus.planned,
          estimatedMinutes: 240,
        ),
      );
      await plans.replaceUnlockedSuggestions(day, [
        PlannedBlock(
          id: 'lock',
          taskId: task.id,
          start: DateTime(2026, 10, 5, 10),
          end: DateTime(2026, 10, 5, 11),
          isLocked: true,
          source: PlanBlockSource.manual,
        ),
      ]);
      await controller.replan();
      final result = await plans.day(day);
      expect(result.fold<int>(0, (n, b) => n + b.durationMinutes), 240);
      expect(result.where((b) => b.id == 'lock').single.start.hour, 10);
      expect(
        result
            .where((b) => b.source == PlanBlockSource.suggested)
            .map((b) => b.durationMinutes),
        everyElement(greaterThanOrEqualTo(30)),
      );
      expect(
        result.every((b) => b.end.hour <= 12 || b.start.hour >= 14),
        isTrue,
      );
    },
  );
  test(
    'pin is first and locked, skip is absent, following date independent',
    () async {
      final first = await tasks.createTask(
        const TaskDraft(
          title: 'High',
          status: TaskStatus.planned,
          importance: 90,
          estimatedMinutes: 60,
        ),
      );
      final pinned = await tasks.createTask(
        const TaskDraft(
          title: 'Pinned',
          status: TaskStatus.planned,
          importance: 10,
          estimatedMinutes: 60,
        ),
      );
      await controller.pin(pinned.id);
      expect((await plans.day(day)).first.taskId, pinned.id);
      expect((await plans.day(day)).first.isLocked, isTrue);
      await controller.skip(first.id);
      expect((await plans.day(day)).any((b) => b.taskId == first.id), isFalse);
      controller.selectDate(day.add(const Duration(days: 1)));
      await controller.replan();
      expect(
        (await plans.day(day.add(const Duration(days: 1))))
            .any((b) => b.taskId == first.id),
        isTrue,
      );
    },
  );
  test('multi-day split accounts for prior persisted allocations', () async {
    final task = await tasks.createTask(
      const TaskDraft(
        title: 'Long',
        status: TaskStatus.planned,
        estimatedMinutes: 600,
      ),
    );
    await controller.replan();
    expect(
      (await plans.day(day)).fold<int>(0, (n, b) => n + b.durationMinutes),
      420,
    );
    controller.selectDate(day.add(const Duration(days: 1)));
    await controller.replan();
    expect(
      (await plans.day(day.add(const Duration(days: 1))))
          .where((b) => b.taskId == task.id)
          .fold<int>(0, (n, b) => n + b.durationMinutes),
      180,
    );
  });
  test('blocked dependencies excluded even when pinned', () async {
    final pre = await tasks.createTask(
      const TaskDraft(title: 'Prerequisite', status: TaskStatus.waiting),
    );
    final task = await tasks.createTask(
      const TaskDraft(
        title: 'Blocked',
        status: TaskStatus.planned,
        estimatedMinutes: 60,
      ),
    );
    await tasks.relations.addDependency(task.id, pre.id);
    await controller.pin(task.id);
    expect(await plans.day(day), isEmpty);
  });
  test('weekend override opens only one day', () async {
    await tasks.createTask(
      const TaskDraft(
        title: 'Weekend',
        status: TaskStatus.planned,
        estimatedMinutes: 60,
      ),
    );
    final saturday = DateTime(2026, 10, 10);
    controller.selectDate(saturday);
    await controller.replan();
    expect(await plans.day(saturday), isEmpty);
    await schedules.setDateOverride(saturday, [
      const TimeWindow(startMinutes: 600, endMinutes: 720),
    ]);
    await controller.replan();
    expect((await plans.day(saturday)).single.start.hour, 10);
    controller.selectDate(DateTime(2026, 10, 17));
    await controller.replan();
    expect(await plans.day(DateTime(2026, 10, 17)), isEmpty);
  });
}
