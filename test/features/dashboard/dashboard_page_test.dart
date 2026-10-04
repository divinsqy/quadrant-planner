import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/planning/work_calendar.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/settings/app_preferences.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/dashboard/application/dashboard_controller.dart';
import 'package:quadrant_planner/features/dashboard/presentation/dashboard_page.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_board.dart';
import 'package:quadrant_planner/features/inbox/presentation/quick_capture.dart';
import 'package:quadrant_planner/features/settings/data/preferences_repository.dart';
import 'package:quadrant_planner/features/settings/presentation/profile_settings.dart';
import 'package:quadrant_planner/features/tasks/application/task_editor_controller.dart';
import 'package:quadrant_planner/features/tasks/data/task_activity_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_preview_drawer.dart';

void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late PreferencesRepository preferences;
  late DashboardController dashboard;
  late TaskActivityRepository activity;
  late TaskEditorController editor;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    var id = 0;
    tasks = TaskRepository(
      db,
      idFactory: () {
        id += 1;
        return 'task-$id';
      },
      clock: () => DateTime.utc(2026, 9, 30, 9),
    );
    preferences = PreferencesRepository(db);
    var eventId = 0;
    activity = TaskActivityRepository(
      db,
      idFactory: () => 'event-${++eventId}',
    );
    editor = TaskEditorController(
      tasks: tasks,
      activity: activity,
      clock: () => DateTime.utc(2026, 9, 30, 9),
    );
    dashboard = DashboardController(
      tasks: tasks,
      preferences: preferences,
      calendar: WorkCalendar(
        schedule: WorkSchedule.standard(),
        coveredYears: const {2026},
        holidays: const {},
      ),
      clock: () => DateTime(2026, 9, 30, 9),
    );
  });

  tearDown(() async {
    dashboard.dispose();
    await db.close();
  });

  testWidgets('Dashboard greeting reacts to nickname changes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(controller: dashboard, taskRepository: tasks),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('早上好'), findsOneWidget);

    await preferences.save(
      const AppPreferences(
        nickname: 'Divins',
        importanceThreshold: 50,
        urgencyThreshold: 50,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('早上好，Divins'), findsOneWidget);
  });

  testWidgets('Quick Capture trims title and creates an Inbox task', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: QuickCapture(taskRepository: tasks)),
      ),
    );

    await tester.enterText(find.byType(TextField), '   DMA review   ');
    await tester.tap(find.text('快速记录'));
    await tester.pumpAndSettle();

    final matches = await tasks.search('DMA');
    expect(matches, hasLength(1));
    expect(matches.single.title, 'DMA review');
    expect(matches.single.status, TaskStatus.inbox);
  });

  testWidgets('Quick Capture rejects a blank title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: QuickCapture(taskRepository: tasks)),
      ),
    );

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('快速记录'));
    await tester.pumpAndSettle();

    expect(find.text('请输入任务标题'), findsOneWidget);
    expect((await db.select(db.tasks).get()), isEmpty);
  });

  testWidgets('newly planned task appears in Dashboard immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(controller: dashboard, taskRepository: tasks),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AXI write path'), findsNothing);

    await tasks.createTask(
      const TaskDraft(
        title: 'AXI write path',
        status: TaskStatus.planned,
        importance: 80,
        baseUrgency: 70,
        estimatedMinutes: 90,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AXI write path'), findsWidgets);
    expect(dashboard.state.snapshots, hasLength(1));
    expect(dashboard.state.currentRecommendation?.task.title, 'AXI write path');
    expect(
      dashboard.state.snapshots.single.currentUrgency,
      greaterThanOrEqualTo(70),
    );
  });

  testWidgets('dragged thresholds persist without changing task coordinates', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final task = await tasks.createTask(
      const TaskDraft(title: 'Fixed scores', status: TaskStatus.planned),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(controller: dashboard, taskRepository: tasks),
      ),
    );
    await tester.pumpAndSettle();
    final board = find.byType(QuadrantBoard);
    final rect = tester.getRect(board);
    final threshold =
        rect.topLeft +
        Offset(36 + (rect.width - 64) / 2, 28 + (rect.height - 60) / 2);
    await tester.dragFrom(threshold, const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(dashboard.state.preferences.urgencyThreshold, greaterThan(50));
    final stored = await tester.runAsync(() => preferences.watch().first);
    expect(
      stored!.urgencyThreshold,
      dashboard.state.preferences.urgencyThreshold,
    );
    final after = await tasks.get(task.id);
    expect(after!.importance, task.importance);
    expect(after.baseUrgency, task.baseUrgency);
    expect(after.baseUrgencyAnchorAt, task.baseUrgencyAnchorAt);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Profile Settings persists an edited nickname', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfileSettings(preferences: preferences)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Divins');
    await tester.tap(find.text('保存昵称'));
    await tester.pump();

    final saved = await (db.select(
      db.preferences,
    )..where((row) => row.id.equals('default'))).getSingle();
    expect(saved.nickname, 'Divins');
    expect(find.text('已保存'), findsOneWidget);

    // Unmount before the shared tearDown closes the Drift database so the
    // widget-owned preferences stream is fully cancelled first.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final size in [const Size(800, 600), const Size(1280, 900)]) {
    testWidgets('${size.width == 800 ? '' : 'desktop '}'
        'quadrant selection opens task preview and double click opens detail', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final task = await tasks.createTask(
        const TaskDraft(
          title: 'Centered Task',
          status: TaskStatus.planned,
          importance: 50,
          baseUrgency: 50,
          estimatedMinutes: 60,
        ),
      );
      String? opened;

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardPage(
            controller: dashboard,
            taskRepository: tasks,
            taskEditor: editor,
            onOpenTask: (id) => opened = id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        dashboard.state.snapshots.map((snapshot) => snapshot.task.id),
        contains(task.id),
      );
      final boardFinder = find.byType(QuadrantBoard);
      expect(boardFinder, findsOneWidget);
      final board = tester.widget<QuadrantBoard>(boardFinder);

      board.onSelect!(task.id);
      await tester.pump();

      expect(tester.widget<QuadrantBoard>(boardFinder).selectedTaskId, task.id);
      final previewFinder = find.byType(TaskPreviewDrawer);
      expect(previewFinder, findsOneWidget);
      expect(tester.widget<TaskPreviewDrawer>(previewFinder).task.id, task.id);

      // Compact layouts stack the preview below the quadrant. Reveal the
      // panel, then scroll its lazy list to build and reach the status action.
      await tester.ensureVisible(previewFinder);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('标记完成'),
        80,
        scrollable: find.descendant(
          of: previewFinder,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('标记完成'));
      await tester.pumpAndSettle();
      expect(find.text('标记完成').hitTestable(), findsOneWidget);

      board.onOpen!(task.id);
      await tester.pump();
      expect(opened, task.id);

      await tester.tap(find.text('标记完成'));
      await tester.pumpAndSettle();
      expect((await tasks.get(task.id))!.status, TaskStatus.completed);
      expect(dashboard.state.snapshots, isEmpty);
      expect(find.byType(TaskPreviewDrawer), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
