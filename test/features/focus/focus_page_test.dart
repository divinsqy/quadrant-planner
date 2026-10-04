import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/app/quadrant_planner_app.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/planning/work_calendar.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/dashboard/presentation/dashboard_page.dart';
import 'package:quadrant_planner/features/focus/application/focus_controller.dart';
import 'package:quadrant_planner/features/focus/data/focus_repository.dart';
import 'package:quadrant_planner/features/focus/presentation/focus_page.dart';
import 'package:quadrant_planner/features/planner/presentation/planner_page.dart';
import 'package:quadrant_planner/features/tasks/data/task_activity_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';
import 'package:quadrant_planner/features/tasks/application/task_editor_controller.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_detail_page.dart';

void main() {
  testWidgets(
    'focus pause resume and completion shows actual time and subtasks',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final tasks = TaskRepository(db);
      final task = await tasks.createTask(
        const TaskDraft(
          title: 'Focus UI',
          status: TaskStatus.planned,
          estimatedMinutes: 60,
        ),
      );
      await tasks.relations.addSubtask(task.id, 'Test scenario');
      var now = DateTime.utc(2026, 10, 5, 9);
      final focus = FocusController(FocusRepository(db), clock: () => now);
      addTearDown(focus.dispose);
      await focus.start(task.id);
      await tester.pumpWidget(
        MaterialApp(
          home: FocusPage(controller: focus, tasks: tasks),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Test scenario'), findsOneWidget);
      now = now.add(const Duration(minutes: 10));
      await tester.tap(find.text('暂停'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 20));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('已专注 10:00'), findsOneWidget);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 5));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认完成'));
      await tester.pumpAndSettle();
      expect(find.text('专注已完成'), findsOneWidget);
      expect((await tasks.get(task.id))!.estimatedMinutes, 60);
      expect(
        (await TaskActivityRepository(db).fetchPage(task.id))
            .singleWhere((e) => e.type == 'focus_completed')
            .payload['actualSeconds'],
        900,
      );
      final activity = TaskActivityRepository(db);
      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailPage(
            taskId: task.id,
            tasks: tasks,
            editor: TaskEditorController(tasks: tasks, activity: activity),
            activity: activity,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(find.text('专注完成'), findsOneWidget);
      expect(find.textContaining('实际用时 15.0 分钟'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'actual app starts from Dashboard Now and recovers active Focus on remount',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final tasks = TaskRepository(db);
      final task = await tasks.createTask(
        const TaskDraft(
          title: 'Recommendation Focus',
          status: TaskStatus.planned,
          estimatedMinutes: 60,
        ),
      );
      final calendar = WorkCalendar(
        schedule: WorkSchedule.standard(),
        coveredYears: const {},
        holidays: const {},
      );
      await tester.pumpWidget(
        QuadrantPlannerApp(database: db, calendar: calendar),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DashboardPage), findsOneWidget);
      await tester.tap(find.text('开始专注'));
      await tester.pumpAndSettle();
      expect(find.byType(FocusPage), findsOneWidget);
      expect((await FocusRepository(db).activeSession())!.taskId, task.id);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        QuadrantPlannerApp(database: db, calendar: calendar),
      );
      await tester.pumpAndSettle();
      expect(find.text('恢复专注'), findsOneWidget);
      await tester.tap(find.text('恢复专注'));
      await tester.pumpAndSettle();
      expect(find.byType(FocusPage), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认完成'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('当前没有可执行任务'), findsOneWidget);
      // The Planner destination must expose the implemented workspace.
      final dashboard = find.byType(DashboardPage);
      expect(dashboard, findsOneWidget);
      await tester.tap(find.text('规划').first);
      await tester.pumpAndSettle();
      expect(find.byType(PlannerPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
