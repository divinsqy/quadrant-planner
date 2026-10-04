import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/planning/planned_block.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/features/planner/application/planner_controller.dart';
import 'package:quadrant_planner/features/planner/data/planner_repository.dart';
import 'package:quadrant_planner/features/planner/presentation/planner_page.dart';
import 'package:quadrant_planner/features/settings/data/preferences_repository.dart';
import 'package:quadrant_planner/features/settings/data/work_schedule_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late PlannerController controller;
  late PlannerRepository plans;
  Future<void> mount(WidgetTester tester, DateTime day) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final tasks = TaskRepository(db);
    final schedules = WorkScheduleRepository(db);
    plans = PlannerRepository(db, schedules: schedules);
    controller = PlannerController(
      plans: plans,
      tasks: tasks,
      schedules: schedules,
      preferences: PreferencesRepository(db),
      clock: () => day,
    );
    addTearDown(() async {
      controller.dispose();
      await db.close();
    });
    await tasks.createTask(
      const TaskDraft(
        title: 'Timeline task',
        status: TaskStatus.planned,
        estimatedMinutes: 60,
        importance: 90,
        baseUrgency: 90,
      ),
    );
    await tester.runAsync(controller.replan);
    await tester.pumpWidget(
      MaterialApp(home: PlannerPage(controller: controller)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'timeline exposes lunch and reasons with validated keyboard move',
    (tester) async {
      await mount(tester, DateTime(2026, 10, 5));
      expect(find.text('12:00–14:00 午休 · 不可用'), findsOneWidget);
      expect(find.textContaining('重要且紧急'), findsWidgets);
      await tester.tap(find.byTooltip('延后15分钟').first);
      await tester.pumpAndSettle();
      expect((await plans.day(controller.date)).first.start.minute, 15);
      await tester.tap(find.byTooltip('锁定时段').first);
      await tester.pumpAndSettle();
      expect((await plans.day(controller.date)).first.isLocked, isTrue);
      expect(find.byTooltip('延后15分钟').first, findsOneWidget);
      final button = tester.widget<IconButton>(
        find
            .byWidgetPredicate((w) => w is IconButton && w.tooltip == '延后15分钟')
            .first,
      );
      expect(button.onPressed, isNull);
      await tester.tap(find.text('重新规划'));
      await tester.pumpAndSettle();
      expect((await plans.day(controller.date)).first.start.minute, 15);
    },
  );
  testWidgets('invalid lunch drop explains error and retains original block', (
    tester,
  ) async {
    await mount(tester, DateTime(2026, 10, 5));
    final original = (await plans.day(controller.date)).first;
    final draggable = find.byWidgetPredicate(
      (w) => w is Draggable<PlannedBlock>,
    );
    final target = find.byKey(const ValueKey('planner-slot-720'));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    // Exercise the same public drop callback after scrolling changes geometry.
    final drop = tester.widget<DragTarget<PlannedBlock>>(target);
    drop.onAcceptWithDetails!(
      DragTargetDetails<PlannedBlock>(data: original, offset: Offset.zero),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('不能跨午休'), findsOneWidget);
    expect((await plans.day(controller.date)).first.start, original.start);
    expect(draggable, findsWidgets);
  });
  testWidgets('manual time dialog rejects lunch then persists a valid move', (
    tester,
  ) async {
    await mount(tester, DateTime(2026, 10, 5));
    final original = (await plans.day(controller.date)).single;
    await tester.tap(find.byTooltip('修改时间').first);
    await tester.pumpAndSettle();
    final start = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == '开始时间',
    );
    final end = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == '结束时间',
    );
    await tester.enterText(start, '11:30');
    await tester.enterText(end, '14:30');
    await tester.tap(find.text('保存时间'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不能跨午休'), findsOneWidget);
    expect((await plans.day(controller.date)).single.start, original.start);
    await tester.enterText(start, '14:00');
    await tester.enterText(end, '15:00');
    await tester.tap(find.text('保存时间'));
    await tester.pumpAndSettle();
    expect(find.text('修改计划时间'), findsNothing);
    expect(find.text('14:00–15:00 · Timeline task'), findsOneWidget);
    expect(
      (await plans.day(controller.date)).single.source,
      PlanBlockSource.manual,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'locked custom-hour block remains visible after work hours change',
    (tester) async {
      await mount(tester, DateTime(2026, 10, 5));
      final b = (await plans.day(controller.date)).first;
      await controller.schedules.saveWeekdays({
        1: [const TimeWindow(startMinutes: 420, endMinutes: 540)],
      });
      await controller.move(
        b.id,
        DateTime(2026, 10, 5, 7),
        DateTime(2026, 10, 5, 8),
      );
      await controller.lock(b.id, true);
      await controller.schedules.saveWeekdays({
        1: [const TimeWindow(startMinutes: 540, endMinutes: 720)],
      });
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('07:00–08:00 · Timeline task'), findsOneWidget);
    },
  );
  testWidgets('weekend empty state can add one-date window and replan', (
    tester,
  ) async {
    await mount(tester, DateTime(2026, 10, 10));
    expect(find.textContaining('当天没有可用工作时段'), findsOneWidget);
    await tester.tap(find.text('单日临时时段'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('override-start')),
      '10:00',
    );
    await tester.enterText(find.byKey(const ValueKey('override-end')), '12:00');
    await tester.tap(find.text('保存临时时段'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新规划'));
    await tester.pumpAndSettle();
    expect((await plans.day(controller.date)).single.start.hour, 10);
    expect(await plans.day(DateTime(2026, 10, 17)), isEmpty);
  });
  testWidgets(
    'planner controls stay accessible with narrow window and large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 600));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        return tester.binding.setSurfaceSize(null);
      });
      await mount(tester, DateTime(2026, 10, 5));
      expect(tester.takeException(), isNull);
      expect(find.text('重新规划').hitTestable(), findsOneWidget);
    },
  );
}
