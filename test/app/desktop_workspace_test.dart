import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/app/quadrant_planner_app.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/planning/work_calendar.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/projects/project.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_board.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_painter.dart';
import 'package:quadrant_planner/features/dashboard/presentation/dashboard_page.dart';
import 'package:quadrant_planner/features/projects/data/project_repository.dart';
import 'package:quadrant_planner/features/search/presentation/command_palette.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_detail_page.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_preview_drawer.dart';

void main() {
  testWidgets(
    'seven destinations remain usable in a narrow window with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 480));
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(() {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        return tester.binding.setSurfaceSize(null);
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(QuadrantPlannerApp(database: db));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final digit in [
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit1,
      ]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(digit);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'actual app opens Dashboard, retains selection and routes search',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.now();
      await ProjectRepository(db).save(
        Project(
          id: 'p1',
          name: 'Desktop release',
          objective: 'Ship workspace',
          deadline: null,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final task = await TaskRepository(db).createTask(
        const TaskDraft(
          title: 'Integration route task',
          status: TaskStatus.planned,
          projectId: 'p1',
          estimatedMinutes: 60,
        ),
      );
      await tester.pumpWidget(
        QuadrantPlannerApp(
          database: db,
          calendar: WorkCalendar(
            schedule: WorkSchedule.standard(),
            coveredYears: const {2026},
            holidays: const {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QuadrantBoard), findsOneWidget);
      final dashboard = tester
          .widget<DashboardPage>(find.byType(DashboardPage))
          .controller;
      dashboard.filterProject('p1');
      await tester.pumpAndSettle();
      QuadrantPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (widget) =>
                          widget is CustomPaint &&
                          widget.painter is QuadrantPainter,
                    ),
                  )
                  .painter!
              as QuadrantPainter;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(QuadrantBoard)),
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.pump();
      final viewport = painter().viewport;
      expect(viewport.zoom, greaterThan(1));
      var board = tester.widget<QuadrantBoard>(find.byType(QuadrantBoard));
      board.onSelect!(task.id);
      await tester.pump();
      expect(find.byType(TaskPreviewDrawer), findsOneWidget);
      board.onOpen!(task.id);
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<QuadrantBoard>(find.byType(QuadrantBoard)).selectedTaskId,
        task.id,
      );
      expect(dashboard.state.projectId, 'p1');
      expect(painter().viewport.zoom, viewport.zoom);
      expect(painter().viewport.center, viewport.center);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(CommandPalette),
          matching: find.byType(TextField),
        ),
        'Desktop release',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CommandPalette),
          matching: find.widgetWithText(ListTile, 'Desktop release'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsWidgets);
      expect(find.text('Ship workspace'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(CommandPalette),
          matching: find.byType(TextField),
        ),
        'Integration route',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CommandPalette),
          matching: find.widgetWithText(ListTile, 'Integration route task'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('保存昵称'), findsOneWidget);
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp).first).themeMode,
        ThemeMode.dark,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
