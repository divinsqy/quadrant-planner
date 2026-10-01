import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/planning/planner_candidate.dart';
import 'package:quadrant_planner/domain/quadrant/quadrant.dart';
import 'package:quadrant_planner/domain/tasks/task.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/tasks/workload.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_board.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_models.dart';

void main() {
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

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(300, 200));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(const Offset(300, 200));
    await tester.pump();

    expect(find.text('Hover Task'), findsOneWidget);
    expect(find.textContaining('紧急性 50'), findsOneWidget);
    expect(find.textContaining('重要性 50'), findsOneWidget);

    await tester.tapAt(const Offset(300, 200));
    await tester.pump();

    expect(selected, 'hover');
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

    await tester.tapAt(const Offset(300, 200));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(300, 200));
    await tester.pump(const Duration(milliseconds: 400));

    expect(opened, contains('open'));

    await tester.tap(find.byKey(const ValueKey('quadrant-board-focus')));
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

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(300, 200));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(const Offset(300, 200));
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
      boardApp(
        tasks: [source],
        onThresholdChanged: (value) => changed = value,
      ),
    );

    await tester.dragFrom(
      const Offset(300, 80),
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
            thresholds: const QuadrantThresholds(
              urgency: 50,
              importance: 50,
            ),
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
