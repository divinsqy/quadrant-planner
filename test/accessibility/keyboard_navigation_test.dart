import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quadrant_planner/app/desktop_workspace.dart';
import 'package:quadrant_planner/app/workspace_providers.dart';
import 'package:quadrant_planner/app/quadrant_planner_app.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/planning/work_calendar.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_painter.dart';
import 'package:quadrant_planner/features/planner/data/planner_repository.dart';
import 'package:quadrant_planner/features/settings/data/work_schedule_repository.dart';
import 'package:quadrant_planner/features/search/presentation/command_palette.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_preview_drawer.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_editor.dart';
import 'package:quadrant_planner/features/tasks/application/task_editor_controller.dart';
import 'package:quadrant_planner/features/tasks/data/task_activity_repository.dart';

Future<void> chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool shift = false,
}) async {
  final modifier = meta
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

void main() {
  for (final meta in [false, true]) {
    testWidgets(
      '${meta ? 'Cmd' : 'Ctrl'} capture saves locally and closes without a pointer',
      (tester) async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(QuadrantPlannerApp(database: db));
        await tester.pumpAndSettle();
        await chord(tester, LogicalKeyboardKey.keyN, meta: meta);
        expect(find.byType(Dialog), findsOneWidget);
        await tester.enterText(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(TextField),
          ),
          'RTL AXI keyboard capture',
        );
        await chord(tester, LogicalKeyboardKey.enter, meta: meta);
        expect(
          (await TaskRepository(db).getTasks()).single.title,
          'RTL AXI keyboard capture',
        );
        expect(find.byType(Dialog), findsNothing);
        await chord(tester, LogicalKeyboardKey.keyK, meta: meta);
        expect(find.byType(CommandPalette), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(CommandPalette), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'Ctrl Enter saves the edited task while a text field is focused',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final tasks = TaskRepository(db);
      final task = await tasks.createTask(
        const TaskDraft(title: 'Old RTL title'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskEditor(
              task: task,
              controller: TaskEditorController(
                tasks: tasks,
                activity: TaskActivityRepository(db),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '任务标题'),
        'New UVM title',
      );
      await chord(tester, LogicalKeyboardKey.enter);
      expect((await tasks.get(task.id))!.title, 'New UVM title');
    },
  );
  for (final clustered in [false, true]) {
    for (final pointer in [false, true]) {
      testWidgets(
        'Escape closes ${clustered ? 'clustered' : 'separate'} quadrant preview from ${pointer ? 'pointer' : 'keyboard'} and preserves arrow navigation',
        (tester) async {
          final db = AppDatabase.forTesting(NativeDatabase.memory());
          addTearDown(db.close);
          await TaskRepository(db).createTask(
            const TaskDraft(
              title: 'Preview keyboard',
              status: TaskStatus.planned,
            ),
          );
          await TaskRepository(db).createTask(
            TaskDraft(
              title: 'Next keyboard',
              status: TaskStatus.planned,
              importance: clustered ? 50 : 80,
            ),
          );
          await tester.binding.setSurfaceSize(const Size(1280, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(QuadrantPlannerApp(database: db));
          await tester.pumpAndSettle();
          final boardFocus = Focus.of(
            tester.element(find.byKey(const ValueKey('quadrant-board-focus'))),
          );
          final painter =
              tester
                      .widget<CustomPaint>(
                        find.byWidgetPredicate(
                          (w) =>
                              w is CustomPaint && w.painter is QuadrantPainter,
                        ),
                      )
                      .painter!
                  as QuadrantPainter;
          expect(painter.clusters.any((c) => c.members.length > 1), clustered);
          if (pointer) {
            await tester.tapAt(
              tester.getTopLeft(
                    find.byKey(const ValueKey('quadrant-board-focus')),
                  ) +
                  painter.clusters.first.screenCenter,
            );
          } else {
            boardFocus.requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          }
          await tester.pumpAndSettle();
          expect(find.byType(TaskPreviewDrawer), findsOneWidget);
          if (pointer && clustered) {
            expect(
              find.byKey(const ValueKey('quadrant-cluster-members')),
              findsOneWidget,
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('quadrant-cluster-members')),
              findsNothing,
            );
            expect(find.byType(TaskPreviewDrawer), findsOneWidget);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(TaskPreviewDrawer), findsNothing);
          expect(boardFocus.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(find.byType(TaskPreviewDrawer), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
  testWidgets('global replan shortcut persists blocks and never enters lunch', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final today = DateTime.now();
    final date = DateTime(today.year, today.month, today.day);
    final calendar = WorkCalendar(
      schedule: WorkSchedule.standard().withDateOverride(date, const [
        TimeWindow(startMinutes: 540, endMinutes: 720),
        TimeWindow(startMinutes: 840, endMinutes: 1080),
      ]),
      coveredYears: const {},
      holidays: const {},
    );
    await TaskRepository(db).createTask(
      const TaskDraft(
        title: 'UVM today',
        status: TaskStatus.planned,
        estimatedMinutes: 240,
      ),
    );
    await tester.pumpWidget(
      QuadrantPlannerApp(database: db, calendar: calendar),
    );
    await tester.pumpAndSettle();
    final planner = ProviderScope.containerOf(
      tester.element(find.byType(DesktopWorkspace)),
    ).read(plannerControllerProvider);
    await chord(tester, LogicalKeyboardKey.keyP, shift: true);
    for (var i = 0; i < 1000 && planner.busy; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(planner.busy, isFalse);
    final blocks = await PlannerRepository(
      db,
      schedules: WorkScheduleRepository(db, baseCalendar: calendar),
    ).day(date);
    expect(blocks, isNotEmpty);
    expect(blocks.every((b) => b.end.hour <= 12 || b.start.hour >= 14), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
