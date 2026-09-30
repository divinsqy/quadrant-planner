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
import 'package:quadrant_planner/features/inbox/presentation/quick_capture.dart';
import 'package:quadrant_planner/features/settings/data/preferences_repository.dart';
import 'package:quadrant_planner/features/settings/presentation/profile_settings.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late PreferencesRepository preferences;
  late DashboardController dashboard;

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
        home: DashboardPage(
          controller: dashboard,
          taskRepository: tasks,
        ),
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
        home: Scaffold(
          body: QuickCapture(taskRepository: tasks),
        ),
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
        home: Scaffold(
          body: QuickCapture(taskRepository: tasks),
        ),
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
        home: DashboardPage(
          controller: dashboard,
          taskRepository: tasks,
        ),
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

  testWidgets('Profile Settings persists an edited nickname', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileSettings(preferences: preferences),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Divins');
    await tester.tap(find.text('保存昵称'));
    await tester.pumpAndSettle();

    final saved = await preferences.watch().first;
    expect(saved.nickname, 'Divins');
  });
}
