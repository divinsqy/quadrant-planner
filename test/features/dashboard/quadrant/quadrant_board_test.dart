import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/planning/planner_candidate.dart';
import 'package:quadrant_planner/domain/quadrant/quadrant.dart';
import 'package:quadrant_planner/domain/tasks/task.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/tasks/workload.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_board.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_models.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_painter.dart';

void main() {
  for (final position in const [
    Offset(90, 50),
    Offset(50, 10),
    Offset(90, 10),
  ]) {
    testWidgets(
      'edge task at $position supports hover then single/double click',
      (tester) async {
        String? selected;
        final opened = <String>[];
        await tester.pumpWidget(
          boardApp(
            tasks: [snapshot('edge', position.dx.toInt(), position.dy.toInt())],
            onSelect: (id) => selected = id,
            onOpen: opened.add,
          ),
        );
        final board = find.byKey(const ValueKey('quadrant-board-focus'));
        final rect = tester.getRect(board);
        final point =
            rect.topLeft +
            Offset(
              36 + (rect.width - 64) * position.dx / 100,
              28 + (rect.height - 60) * (1 - position.dy / 100),
            );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: rect.topLeft);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(point);
        await tester.pump();
        expect(find.text('Open Task'), findsOneWidget);
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 40));
        expect(selected, 'edge');
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 400));
        expect(opened, ['edge']);
      },
    );
  }
  testWidgets(
    'large text metadata can scroll to project tags and dependency details',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                height: 300,
                child: QuadrantBoard(
                  tasks: [snapshot('metadata', 50, 50)],
                  thresholds: const QuadrantThresholds(
                    urgency: 50,
                    importance: 50,
                  ),
                  taskMetadata: {
                    'metadata': {
                      '项目': 'Desktop workspace release project',
                      '标签': 'RTL、UVM、回归测试、桌面集成、版本发布',
                      '剩余工作日': '3',
                      '依赖': '已满足',
                    },
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final board = find.byKey(const ValueKey('quadrant-board-focus'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(board));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(board));
      await tester.pump();
      final metadataScroll = find.descendant(
        of: board,
        matching: find.byType(Scrollable),
      );
      expect(metadataScroll, findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('依赖：已满足'),
        150,
        scrollable: metadataScroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('依赖：已满足').hitTestable(), findsOneWidget);
      expect(
        tester.getBottomRight(find.text('依赖：已满足')).dy,
        lessThanOrEqualTo(tester.getBottomRight(board).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'clearing controlled selection also clears the painted selection',
    (tester) async {
      final tasks = [snapshot('selected', 50, 50)];
      await tester.pumpWidget(
        boardApp(tasks: tasks, selectedTaskId: 'selected'),
      );
      final board = find.byKey(const ValueKey('quadrant-board-focus'));
      final rect = tester.getRect(board);
      await tester.tapAt(
        rect.topLeft +
            Offset(36 + (rect.width - 64) / 2, 28 + (rect.height - 60) / 2),
      );
      await tester.pump();
      await tester.pumpWidget(boardApp(tasks: tasks));
      final painter =
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
      expect(painter.selectedTaskId, isNull);
    },
  );
  testWidgets('hover shows task metadata and single click selects it', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      boardApp(
        tasks: [snapshot('hover', 50, 50)],
        onSelect: (id) => selected = id,
      ),
    );

    final boardCenter = tester.getCenter(
      find.byKey(const ValueKey('quadrant-board-focus')),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: boardCenter);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(boardCenter);
    await tester.pump();

    expect(find.text('Hover Task'), findsOneWidget);
    expect(find.textContaining('紧急性 50'), findsOneWidget);
    expect(find.textContaining('重要性 50'), findsOneWidget);

    await tester.tapAt(boardCenter);
    await tester.pump();

    expect(selected, 'hover');

    // Let the double-click recognizer's single-click timeout expire before
    // the widget-test binding verifies there are no pending timers.
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('double click and keyboard Enter open the selected task', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      boardApp(
        tasks: [snapshot('open', 50, 50)],
        selectedTaskId: 'open',
        onOpen: opened.add,
      ),
    );

    final boardCenter = tester.getCenter(
      find.byKey(const ValueKey('quadrant-board-focus')),
    );
    await tester.tapAt(boardCenter);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(boardCenter);
    await tester.pump(const Duration(milliseconds: 400));

    expect(opened, contains('open'));

    // The double click already focuses the board via pointer-down.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(opened.where((id) => id == 'open').length, greaterThanOrEqualTo(2));
  });

  testWidgets('coincident tasks expose a cluster without losing titles', (
    tester,
  ) async {
    await tester.pumpWidget(
      boardApp(
        tasks: [
          snapshot('a', 50, 50, title: 'Task A'),
          snapshot('b', 50, 50, title: 'Task B'),
        ],
      ),
    );

    final boardCenter = tester.getCenter(
      find.byKey(const ValueKey('quadrant-board-focus')),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: boardCenter);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(boardCenter);
    await tester.pump();

    expect(find.text('2 个任务'), findsOneWidget);
    expect(find.text('Task A'), findsOneWidget);
    expect(find.text('Task B'), findsOneWidget);
  });

  testWidgets('dragging urgency threshold emits clamped settings only', (
    tester,
  ) async {
    QuadrantThresholds? changed;
    final source = snapshot('fixed', 25, 75);
    final originalUrgency = source.task.baseUrgency;
    final originalImportance = source.task.importance;

    await tester.pumpWidget(
      boardApp(tasks: [source], onThresholdChanged: (value) => changed = value),
    );

    final rect = tester.getRect(
      find.byKey(const ValueKey('quadrant-board-focus')),
    );
    await tester.dragFrom(
      Offset(rect.center.dx, rect.top + 80),
      const Offset(80, 0),
    );
    await tester.pump();

    expect(changed, isNotNull);
    expect(changed!.urgency, greaterThan(50));
    expect(changed!.urgency, lessThanOrEqualTo(100));
    expect(changed!.importance, 50);
    expect(source.task.baseUrgency, originalUrgency);
    expect(source.task.importance, originalImportance);
  });

  testWidgets(
    'expanded coincident tasks allow selecting and opening every member',
    (tester) async {
      final selected = <String>[];
      final opened = <String>[];
      await tester.pumpWidget(
        boardApp(
          tasks: List.generate(
            8,
            (index) =>
                snapshot('member-$index', 50, 50, title: 'Member $index'),
          ),
          onSelect: selected.add,
          onOpen: opened.add,
        ),
      );

      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('quadrant-board-focus'))),
      );
      await tester.pump();

      final picker = find.byKey(const ValueKey('quadrant-cluster-members'));
      expect(picker, findsOneWidget);
      for (var index = 0; index < 8; index++) {
        final member = find.byKey(
          ValueKey('quadrant-cluster-member-member-$index'),
        );
        await tester.scrollUntilVisible(
          member,
          80,
          scrollable: find.descendant(
            of: picker,
            matching: find.byType(Scrollable),
          ),
        );
        await Scrollable.ensureVisible(tester.element(member), alignment: 0.5);
        await tester.pump();
        await tester.tap(member);
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(member);
        await tester.pump(const Duration(milliseconds: 400));
        expect(selected, contains('member-$index'));
        expect(opened, contains('member-$index'));
      }
    },
  );

  testWidgets(
    'keyboard traverses every coincident member and shows focused metadata',
    (tester) async {
      final selected = <String>[];
      final opened = <String>[];
      await tester.pumpWidget(
        boardApp(
          tasks: [
            snapshot('a', 50, 50, title: 'Task A'),
            snapshot('b', 50, 50, title: 'Task B'),
            snapshot('c', 50, 50, title: 'Task C'),
          ],
          selectedTaskId: 'a',
          onSelect: selected.add,
          onOpen: opened.add,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.text('Task A'), findsOneWidget);
      expect(find.textContaining('紧急性 50'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selected.last, 'b');
      expect(find.text('Task B'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selected.last, 'c');
      expect(find.text('Task C'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected.last, 'b');
      expect(opened, ['b']);
    },
  );

  testWidgets('semantics expands clusters and activates individual members', (
    tester,
  ) async {
    final selected = <String>[];
    final opened = <String>[];
    await tester.pumpWidget(
      boardApp(
        tasks: [
          snapshot('a', 50, 50, title: 'Task A'),
          snapshot('b', 50, 50, title: 'Task B'),
          snapshot('solo', 10, 10, title: 'Solo Task'),
        ],
        onSelect: selected.add,
        onOpen: opened.add,
      ),
    );

    final clusterFinder = find.semantics.byLabel(RegExp('^2 个任务'));
    final cluster = clusterFinder.evaluate().single;
    expect(cluster.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(clusterFinder);
    await tester.pump();

    final memberFinder = find.semantics.byLabel(RegExp('^Task B，'));
    final member = memberFinder.evaluate().single;
    expect(member.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(
      member.getSemanticsData().hasAction(SemanticsAction.longPress),
      isTrue,
    );
    tester.semantics.tap(memberFinder);
    tester.semantics.longPress(memberFinder);
    await tester.pump();
    expect(selected.last, 'b');
    expect(opened, ['b']);

    final solo = find.semantics.byLabel(RegExp('^Solo Task，'));
    tester.semantics.tap(solo);
    tester.semantics.longPress(solo);
    await tester.pump();
    expect(selected.last, 'solo');
    expect(opened, ['b', 'solo']);
  });

  testWidgets('dense quadrant keeps member widgets lazy', (tester) async {
    await tester.pumpWidget(
      boardApp(
        tasks: List.generate(
          1000,
          (index) => snapshot('dense-$index', 50, 50, title: 'Dense $index'),
        ),
      ),
    );
    expect(find.byType(InkWell), findsNothing);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('quadrant-board-focus'))),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('quadrant-cluster-members')),
      findsOneWidget,
    );
    expect(find.byType(InkWell).evaluate().length, lessThan(30));
  });

  testWidgets(
    'zoom and pan survive a rebuild and empty double click resets them',
    (tester) async {
      await tester.pumpWidget(boardApp(tasks: [snapshot('fixed', 25, 75)]));
      final board = find.byKey(const ValueKey('quadrant-board-focus'));
      final topLeft = tester.getTopLeft(board);
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
          position: topLeft + const Offset(100, 300),
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.pump();
      expect(painter().viewport.zoom, greaterThan(1));
      await tester.dragFrom(
        topLeft + const Offset(100, 300),
        const Offset(30, -20),
      );
      await tester.pump();
      final moved = painter().viewport;
      expect(moved.center, isNot(const Offset(50, 50)));

      await tester.pumpWidget(
        boardApp(tasks: [snapshot('fixed', 25, 75, title: 'Updated')]),
      );
      expect(painter().viewport.zoom, moved.zoom);
      expect(painter().viewport.center, moved.center);
      await tester.tapAt(topLeft + const Offset(60, 60));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(topLeft + const Offset(60, 60));
      await tester.pump(const Duration(milliseconds: 400));
      expect(painter().viewport.zoom, 1);
      expect(painter().viewport.center, const Offset(50, 50));
    },
  );
}

Widget boardApp({
  required List<TaskPlanningSnapshot> tasks,
  String? selectedTaskId,
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onOpen,
  ValueChanged<QuadrantThresholds>? onThresholdChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 600,
          height: 400,
          child: QuadrantBoard(
            tasks: tasks,
            thresholds: const QuadrantThresholds(urgency: 50, importance: 50),
            selectedTaskId: selectedTaskId,
            onSelect: onSelect,
            onOpen: onOpen,
            onThresholdChanged: onThresholdChanged,
          ),
        ),
      ),
    ),
  );
}

TaskPlanningSnapshot snapshot(
  String id,
  int urgency,
  int importance, {
  String? title,
}) {
  final task = Task.create(
    id: id,
    title: title ?? (id == 'hover' ? 'Hover Task' : 'Open Task'),
    description: 'Detail note',
    status: TaskStatus.planned,
    projectId: null,
    importance: importance,
    baseUrgency: urgency,
    baseUrgencyAnchorAt: DateTime(2026, 9, 30),
    deadline: DateTime(2026, 10, 5),
    estimatedMinutes: 60,
    workload: Workload.medium,
    progress: 0,
    includeInWeeklyReport: true,
    createdAt: DateTime(2026, 9, 30),
    updatedAt: DateTime(2026, 9, 30),
  );
  return TaskPlanningSnapshot(
    task: task,
    currentUrgency: urgency,
    quadrant: Quadrant.doNow,
    dependenciesSatisfied: true,
    milestoneWorkdaysRemaining: null,
    fitsCurrentSlot: true,
  );
}
