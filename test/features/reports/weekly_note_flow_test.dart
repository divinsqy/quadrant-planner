import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/app/quadrant_planner_app.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/reports/report_style_profile.dart';
import 'package:quadrant_planner/domain/reports/weekly_report.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/focus/application/focus_controller.dart';
import 'package:quadrant_planner/features/focus/data/focus_repository.dart';
import 'package:quadrant_planner/features/focus/presentation/focus_page.dart';
import 'package:quadrant_planner/features/reports/application/weekly_report_builder.dart';
import 'package:quadrant_planner/features/reports/data/report_repository.dart';
import 'package:quadrant_planner/features/reports/data/weekly_note_repository.dart';
import 'package:quadrant_planner/features/reports/presentation/reports_page.dart';
import 'package:quadrant_planner/features/tasks/application/task_editor_controller.dart';
import 'package:quadrant_planner/features/tasks/data/task_activity_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_detail_page.dart';

void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late WeeklyNoteRepository notes;
  final now = DateTime(2026, 10, 9);
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db, clock: () => now);
    notes = WeeklyNoteRepository(db, clock: () => now);
  });
  tearDown(() => db.close());
  Future<void> writeNote(WidgetTester tester) async {
    await tester.tap(find.byTooltip('记录本周笔记'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '问题 / 困难'),
      'AXI burst 边界失败',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '原因'),
      'dmac_regfile 地址对齐',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '解决 / 进展'),
      '补充 UVM 场景',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '体会 / 感受'),
      '检查 RTL 边界条件',
    );
    await tester.tap(find.text('保存笔记'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'task note becomes evidenced QA and saved history retains its snapshot',
    (tester) async {
      final task = await tasks.createTask(
        const TaskDraft(
          title: 'RTL dmac_regfile',
          status: TaskStatus.inProgress,
          progress: 60,
        ),
      );
      final activity = TaskActivityRepository(db);
      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailPage(
            taskId: task.id,
            tasks: tasks,
            editor: TaskEditorController(tasks: tasks, activity: activity),
            activity: activity,
            weeklyNotes: notes,
            noteClock: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await writeNote(tester);
      final note = (await notes.forWeek(now)).single;
      expect(note.taskId, task.id);
      final repo = ReportRepository(db);
      final draft = await WeeklyReportBuilder(
        reports: repo,
        clock: () => now,
      ).build(DateRange.weekOf(now), ReportStyleProfile.standard());
      expect(draft.reflections.single.question, 'AXI burst 边界失败');
      expect(draft.reflections.single.answer, contains('dmac_regfile 地址对齐'));
      expect(draft.reflections.single.evidence.single.sourceId, note.id);
      await repo.save(draft.copyWith(status: ReportStatus.finalized));
      await tasks.save(
        task.copyWith(
          title: 'later changed title',
          progress: 100,
          updatedAt: now.add(const Duration(days: 10)),
        ),
      );
      final historical = (await repo.get(draft.id))!;
      expect(historical.workItems.single.text, 'RTL dmac_regfile');
      expect(historical.workItems.single.progress, 60);
      expect(historical.reflections.single.question, 'AXI burst 边界失败');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'completed Focus exposes linked note capture without changing estimate',
    (tester) async {
      final task = await tasks.createTask(
        const TaskDraft(
          title: 'UVM dmac_intr',
          status: TaskStatus.planned,
          estimatedMinutes: 60,
        ),
      );
      var clock = now;
      final focus = FocusController(FocusRepository(db), clock: () => clock);
      addTearDown(focus.dispose);
      await focus.start(task.id);
      clock = clock.add(const Duration(minutes: 20));
      await focus.complete(completeTask: false);
      await tester.pumpWidget(
        MaterialApp(
          home: FocusPage(controller: focus, tasks: tasks, weeklyNotes: notes),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('专注已完成'), findsOneWidget);
      await writeNote(tester);
      expect((await notes.forWeek(now)).single.taskId, task.id);
      expect((await tasks.get(task.id))!.estimatedMinutes, 60);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'actual Reports route captures general notes and produces useful zero completion draft',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(QuadrantPlannerApp(database: db));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(ReportsPage), findsOneWidget);
      await tester.tap(find.byTooltip('记录本周笔记'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存笔记'));
      await tester.pumpAndSettle();
      expect(find.textContaining('至少填写'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, '问题 / 困难'),
        'UVM 测试缺少 AXI 场景',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '解决 / 进展'),
        'dmac_intr 场景已补齐',
      );
      await tester.tap(find.text('保存笔记'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成草稿'));
      await tester.pumpAndSettle();
      final draft = tester
          .widget<ReportsPage>(find.byType(ReportsPage))
          .controller
          .draft!;
      expect(draft.workItems.single.text, 'dmac_intr 场景已补齐');
      expect(draft.reflections.single.question, 'UVM 测试缺少 AXI 场景');
      expect(draft.workItems.single.evidence, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
