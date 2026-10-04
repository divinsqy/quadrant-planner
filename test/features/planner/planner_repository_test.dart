import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/planning/planned_block.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/planner/data/planner_repository.dart';
import 'package:quadrant_planner/features/settings/data/work_schedule_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late PlannerRepository repo;
  late WorkScheduleRepository schedules;
  late String taskId;
  final day = DateTime(2026, 10, 5);
  PlannedBlock block(String id, int start, int end, {bool locked = false}) =>
      PlannedBlock(
        id: id,
        taskId: taskId,
        start: day.add(Duration(minutes: start)),
        end: day.add(Duration(minutes: end)),
        isLocked: locked,
        source: PlanBlockSource.suggested,
      );
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    schedules = WorkScheduleRepository(db);
    repo = PlannerRepository(db, schedules: schedules);
    taskId = (await TaskRepository(db).createTask(
      const TaskDraft(
        title: 'Plan',
        status: TaskStatus.planned,
        estimatedMinutes: 240,
      ),
    )).id;
  });
  tearDown(() => db.close());
  test(
    'locked blocks survive replacement with identity and times unchanged',
    () async {
      await repo.replaceUnlockedSuggestions(day, [
        block('locked', 600, 660, locked: true),
        block('old', 840, 900),
      ]);
      await repo.replaceUnlockedSuggestions(day, [block('new', 540, 600)]);
      final rows = await repo.watchDay(day).first;
      expect(rows.map((b) => b.id), ['new', 'locked']);
      expect(rows.last.start, DateTime(2026, 10, 5, 10));
      expect(rows.last.end, DateTime(2026, 10, 5, 11));
      expect(rows.last.isLocked, isTrue);
    },
  );
  test(
    'overlap replacement rolls back without deleting existing plan',
    () async {
      await repo.replaceUnlockedSuggestions(day, [
        block('locked', 600, 660, locked: true),
      ]);
      await expectLater(
        repo.replaceUnlockedSuggestions(day, [block('overlap', 630, 690)]),
        throwsArgumentError,
      );
      expect((await repo.watchDay(day).first).single.id, 'locked');
    },
  );
  test(
    'manual move persists across replan and locked block rejects move',
    () async {
      await repo.replaceUnlockedSuggestions(day, [block('a', 540, 600)]);
      await repo.moveBlock(
        'a',
        DateTime(2026, 10, 5, 14),
        DateTime(2026, 10, 5, 15),
      );
      await repo.replaceUnlockedSuggestions(day, []);
      final moved = (await repo.watchDay(day).first).single;
      expect(moved.start, DateTime(2026, 10, 5, 14));
      expect(moved.source, PlanBlockSource.manual);
      await repo.lockBlock('a', true);
      await expectLater(
        repo.moveBlock(
          'a',
          DateTime(2026, 10, 5, 15),
          DateTime(2026, 10, 5, 16),
        ),
        throwsArgumentError,
      );
    },
  );
  test('lunch crossing and default weekend scheduling rejected', () async {
    await expectLater(
      repo.replaceUnlockedSuggestions(day, [block('lunch', 690, 870)]),
      throwsArgumentError,
    );
    final saturday = DateTime(2026, 10, 10);
    await expectLater(
      repo.replaceUnlockedSuggestions(saturday, [
        PlannedBlock(
          id: 'weekend',
          taskId: taskId,
          start: DateTime(2026, 10, 10, 10),
          end: DateTime(2026, 10, 10, 11),
          isLocked: false,
          source: PlanBlockSource.manual,
        ),
      ]),
      throwsArgumentError,
    );
  });
  test(
    'automatic chunks for a large task cannot be below thirty minutes',
    () async {
      await expectLater(
        repo.replaceUnlockedSuggestions(day, [block('tiny', 540, 560)]),
        throwsArgumentError,
      );
      expect(await repo.day(day), isEmpty);
    },
  );
  test('valid late work window can end at midnight and UTC input keeps local clock', () async {
    await schedules.saveWeekdays({
      1: [const TimeWindow(startMinutes: 1260, endMinutes: 1440)],
    });
    await repo.replaceUnlockedSuggestions(day, [
      PlannedBlock(
        id: 'late',
        taskId: taskId,
        start: DateTime(2026, 10, 5, 21).toUtc(),
        end: DateTime(2026, 10, 6).toUtc(),
        isLocked: false,
        source: PlanBlockSource.manual,
      ),
    ]);
    final result = (await repo.day(day)).single;
    expect(result.start, DateTime(2026, 10, 5, 21));
    expect(result.end, DateTime(2026, 10, 6));
    expect(result.durationMinutes, 180);
  });
  test(
    'pin and skip are date-specific and skip explicitly clears task slots',
    () async {
      await repo.replaceUnlockedSuggestions(day, [block('a', 540, 600)]);
      await repo.pinTask(taskId, day);
      expect((await repo.overridesForDay(day))[taskId], 'pin');
      expect((await repo.watchDay(day).first).single.isLocked, isTrue);
      expect(
        await repo.overridesForDay(day.add(const Duration(days: 1))),
        isEmpty,
      );
      await repo.skipTask(taskId, day);
      expect((await repo.overridesForDay(day))[taskId], 'skip');
      expect(await repo.watchDay(day).first, isEmpty);
    },
  );
  test(
    'schedule changes preserve locked slots even outside new windows',
    () async {
      await repo.replaceUnlockedSuggestions(day, [
        block('a', 540, 600, locked: true),
      ]);
      await schedules.saveWeekdays({DateTime.monday: []});
      await repo.replaceUnlockedSuggestions(day, []);
      expect((await repo.watchDay(day).first).single.start.hour, 9);
    },
  );
  test('reordering swaps adjacent unlocked slots atomically', () async {
    final other = await TaskRepository(
      db,
    ).createTask(const TaskDraft(title: 'Other', status: TaskStatus.planned));
    await repo.replaceUnlockedSuggestions(day, [
      block('a', 540, 600),
      PlannedBlock(
        id: 'b',
        taskId: other.id,
        start: DateTime(2026, 10, 5, 10),
        end: DateTime(2026, 10, 5, 11),
        isLocked: false,
        source: PlanBlockSource.suggested,
      ),
    ]);
    await repo.reorderBlock('b', -1);
    final result = await repo.watchDay(day).first;
    expect(result.map((b) => b.id), ['b', 'a']);
    expect(result.map((b) => b.source), everyElement(PlanBlockSource.manual));
  });
}
