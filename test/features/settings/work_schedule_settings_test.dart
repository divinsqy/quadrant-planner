import 'package:drift/native.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/planner/application/planner_controller.dart';
import 'package:quadrant_planner/features/planner/data/planner_repository.dart';
import 'package:quadrant_planner/features/settings/data/preferences_repository.dart';
import 'package:quadrant_planner/features/settings/data/work_schedule_repository.dart';
import 'package:quadrant_planner/features/settings/presentation/work_schedule_settings.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late WorkScheduleRepository repo;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = WorkScheduleRepository(db);
  });
  tearDown(() => db.close());
  test(
    'existing Planner automatically observes same-sized work-window edits',
    () async {
      final tasks = TaskRepository(db);
      await tasks.createTask(
        const TaskDraft(
          title: 'Reactive hours',
          status: TaskStatus.planned,
          estimatedMinutes: 60,
        ),
      );
      final controller = PlannerController(
        plans: PlannerRepository(db, schedules: repo),
        tasks: tasks,
        schedules: repo,
        preferences: PreferencesRepository(db),
        clock: () => DateTime(2026, 10, 5),
      );
      addTearDown(controller.dispose);
      controller.start();
      for (final hour in [10, 11]) {
        final updated = Completer<void>();
        void observe() {
          if (!updated.isCompleted &&
              controller.suggestion.blocks.isNotEmpty &&
              controller.suggestion.blocks.first.start.hour == hour) {
            updated.complete();
          }
        }

        controller.addListener(observe);
        await repo.saveWeekdays({
          1: [TimeWindow(startMinutes: hour * 60, endMinutes: 720)],
        });
        await updated.future.timeout(const Duration(seconds: 5));
        controller.removeListener(observe);
      }
    },
  );
  test(
    'default windows persist edits, empty configured template stays empty',
    () async {
      expect(
        (await repo.getCalendar()).availableWindows(DateTime(2026, 10, 5)),
        [
          const TimeWindow(startMinutes: 540, endMinutes: 720),
          const TimeWindow(startMinutes: 840, endMinutes: 1080),
        ],
      );
      expect(
        (await repo.getCalendar()).availableWindows(DateTime(2026, 10, 10)),
        isEmpty,
      );
      await repo.saveWeekdays({
        1: [const TimeWindow(startMinutes: 600, endMinutes: 720)],
      });
      expect(
        (await WorkScheduleRepository(db).getCalendar())
            .availableWindows(DateTime(2026, 10, 5))
            .single
            .startMinutes,
        600,
      );
      await repo.saveWeekdays({});
      expect(
        (await WorkScheduleRepository(
          db,
        ).getCalendar()).availableWindows(DateTime(2026, 10, 5)),
        isEmpty,
      );
    },
  );
  test('invalid, overlapping, lunch-crossing and recurring weekend windows rejected without mutation', () async {
    for (final invalid in [
      {
        1: [const TimeWindow(startMinutes: 600, endMinutes: 540)],
      },
      {
        1: [
          const TimeWindow(startMinutes: 540, endMinutes: 660),
          const TimeWindow(startMinutes: 600, endMinutes: 720),
        ],
      },
      {
        1: [const TimeWindow(startMinutes: 690, endMinutes: 870)],
      },
      {
        6: [const TimeWindow(startMinutes: 600, endMinutes: 720)],
      },
    ]) {
      await expectLater(repo.saveWeekdays(invalid), throwsArgumentError);
    }
    expect(
      (await repo.getCalendar())
          .availableWindows(DateTime(2026, 10, 5))
          .first
          .startMinutes,
      540,
    );
  });
  test('one-date opening survives repository restart and leaves weekly schedule alone', () async {
    final saturday = DateTime(2026, 10, 10);
    await repo.setDateOverride(saturday, [
      const TimeWindow(startMinutes: 600, endMinutes: 720),
    ]);
    final calendar = await WorkScheduleRepository(db).getCalendar();
    expect(calendar.availableWindows(saturday).single.startMinutes, 600);
    expect(calendar.availableWindows(DateTime(2026, 10, 17)), isEmpty);
    expect(calendar.schedule.windowsForWeekday(1).first.startMinutes, 540);
    await repo.clearDateOverride(saturday);
    expect((await repo.getCalendar()).availableWindows(saturday), isEmpty);
  });
  testWidgets('settings edits recurring hours and subsequent plan uses them', (
    tester,
  ) async {
    final tasks = TaskRepository(db);
    await tasks.createTask(
      const TaskDraft(
        title: 'Hours',
        status: TaskStatus.planned,
        estimatedMinutes: 60,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorkScheduleSettings(schedules: repo),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('09:00–12:00, 14:00–18:00'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('schedule-weekday-1')),
      '10:00–12:00, 14:00–17:00',
    );
    await tester.ensureVisible(find.text('保存工作时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存工作时间'));
    await tester.pumpAndSettle();
    final plans = PlannerRepository(db, schedules: repo);
    final controller = PlannerController(
      plans: plans,
      tasks: tasks,
      schedules: repo,
      preferences: PreferencesRepository(db),
      clock: () => DateTime(2026, 10, 5),
    );
    addTearDown(controller.dispose);
    await controller.replan();
    expect((await plans.day(DateTime(2026, 10, 5))).single.start.hour, 10);
    expect(find.text('工作时间已保存'), findsOneWidget);
  });
  testWidgets(
    'settings shows validation error for lunch overlap and stays usable with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 600));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        return tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WorkScheduleSettings(schedules: repo),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('schedule-weekday-1')),
        '11:00–15:00',
      );
      await tester.ensureVisible(find.text('保存工作时间'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存工作时间'));
      await tester.pumpAndSettle();
      expect(find.textContaining('午休'), findsWidgets);
      expect(tester.takeException(), isNull);
      expect(
        (await repo.getCalendar())
            .availableWindows(DateTime(2026, 10, 5))
            .first
            .startMinutes,
        540,
      );
    },
  );
}
