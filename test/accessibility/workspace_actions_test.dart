
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/app/quadrant_planner_app.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/planning/planned_block.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/inbox/presentation/inbox_page.dart';
import 'package:quadrant_planner/features/tasks/presentation/tasks_page.dart';
import 'package:quadrant_planner/features/projects/presentation/projects_page.dart';
import 'package:quadrant_planner/features/planner/presentation/planner_page.dart';
import 'package:quadrant_planner/features/planner/presentation/planner_block_card.dart';
import 'package:quadrant_planner/features/reports/presentation/reports_page.dart';
import 'package:quadrant_planner/features/dashboard/presentation/dashboard_page.dart';
import 'package:quadrant_planner/features/settings/presentation/profile_settings.dart';
import 'package:quadrant_planner/features/reports/application/reports_controller.dart';
import 'package:quadrant_planner/features/reports/data/report_repository.dart';
import 'package:quadrant_planner/features/reports/data/report_file_gateway.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

import 'keyboard_navigation_test.dart' show chord;

class _Files implements ReportFileGateway {
  String? copied;
  Uint8List? exported;
  @override
  Future<ReportSample?> pickStyleSample() async => null;
  @override
  Future<bool> save({
    required String filename,
    required Uint8List bytes,
  }) async {
    exported = bytes;
    return true;
  }

  @override
  Future<void> copyPlainText(String value) async {
    copied = value;
  }
}

Future<void> keyboardActivate(
  WidgetTester tester,
  Finder target, {
  ReportsController? nativeWork,
}) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  final content = find
      .descendant(
        of: target,
        matching: find.byWidgetPredicate((w) => w is Text || w is Icon),
      )
      .first;
  Focus.of(tester.element(content)).requestFocus();
  await tester.pump();
  if (nativeWork != null) {
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await Future.doWhile(() async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return nativeWork.busy;
      }).timeout(const Duration(seconds: 10));
    });
  } else {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Ctrl and Cmd number keys reach all seven actual destinations', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(QuadrantPlannerApp(database: db));
    await tester.pumpAndSettle();
    final pages = [
      DashboardPage,
      InboxPage,
      TasksPage,
      ProjectsPage,
      PlannerPage,
      ReportsPage,
      ProfileSettings,
    ];
    final keys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
    ];
    for (final meta in [false, true]) {
      for (var i = 0; i < 7; i++) {
        await chord(tester, keys[i], meta: meta);
        expect(find.byType(pages[i]), findsOneWidget);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('planner keyboard move reorder and accessible lock actions', (
    tester,
  ) async {
    final calls = <int>[];
    var locked = false;
    final block = PlannedBlock(
      id: 'b',
      taskId: 't',
      isLocked: false,
      source: PlanBlockSource.suggested,
      start: DateTime(2026, 10, 5, 9),
      end: DateTime(2026, 10, 5, 10),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannerBlockCard(
            block: block,
            title: 'RTL slot',
            onMoveMinutes: calls.add,
            onReorder: calls.add,
            onLock: () => locked = true,
          ),
        ),
      ),
    );
    Focus.of(
      tester.element(
        find.byWidgetPredicate((w) => w is Draggable<PlannedBlock>),
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await chord(tester, LogicalKeyboardKey.arrowUp, meta: true);
    expect(calls, [15, -1]);
    await keyboardActivate(tester, find.byTooltip('锁定时段'));
    expect(locked, isTrue);
  });
  testWidgets(
    'report generate Markdown XLSX and copy remain keyboard activatable',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final at = DateTime(2026, 10, 9);
      await TaskRepository(db, clock: () => at).createTask(
        const TaskDraft(
          title: 'AXI dmac_intr',
          status: TaskStatus.inProgress,
          progress: 80,
        ),
      );
      final files = _Files();
      final controller = ReportsController(
        reports: ReportRepository(db, clock: () => at),
        files: files,
        clock: () => at,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ReportsPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      await keyboardActivate(tester, find.widgetWithText(FilledButton, '生成草稿'));
      expect(
        controller.draft!.workItems.single.text,
        contains('AXI dmac_intr'),
      );
      await keyboardActivate(
        tester,
        find.widgetWithText(OutlinedButton, '导出 Markdown'),
      );
      expect(String.fromCharCodes(files.exported!), contains('AXI dmac_intr'));
      await keyboardActivate(
        tester,
        find.widgetWithText(OutlinedButton, '导出 XLSX'),
        nativeWork: controller,
      );
      expect(files.exported!.take(2).toList(), [80, 75]);
      await keyboardActivate(
        tester,
        find.widgetWithText(OutlinedButton, '复制纯文本'),
        nativeWork: controller,
      );
      expect(files.copied, contains('AXI dmac_intr'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
