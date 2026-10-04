import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/tasks/application/task_editor_controller.dart';
import 'package:quadrant_planner/features/tasks/data/task_activity_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_detail_page.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_preview_drawer.dart';
import 'package:quadrant_planner/features/inbox/presentation/inbox_page.dart';

void main() {
  late AppDatabase db;
  late DateTime now;
  late TaskRepository tasks;
  late TaskActivityRepository activity;
  late TaskEditorController controller;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 1, 9);
    var taskId = 0;
    var eventId = 0;

    tasks = TaskRepository(
      db,
      idFactory: () => 'task-${++taskId}',
      clock: () => now,
    );
    activity = TaskActivityRepository(
      db,
      idFactory: () => 'event-${++eventId}',
    );
    controller = TaskEditorController(
      tasks: tasks,
      activity: activity,
      clock: () => now,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('Inbox task can be planned and records the status change', () async {
    final inbox = await tasks.createTask(const TaskDraft(title: 'Learn UVM'));
    expect(inbox.status, TaskStatus.inbox);

    now = DateTime.utc(2026, 10, 1, 10);
    final planned = await controller.save(inbox, status: TaskStatus.planned);

    expect(planned.status, TaskStatus.planned);
    expect((await tasks.get(planned.id))!.status, TaskStatus.planned);

    final events = await activity.fetchPage(planned.id, limit: 20);
    expect(events, hasLength(2));
    final update = events.singleWhere((event) => event.type == 'task_updated');
    expect(update.payload['changes']['status']['before'], 'inbox');
    expect(update.payload['changes']['status']['after'], 'planned');
  });

  test(
    'changing importance keeps urgency anchor, changing base urgency resets it',
    () async {
      final task = await tasks.createTask(
        const TaskDraft(
          title: 'AXI write path',
          status: TaskStatus.planned,
          importance: 60,
          baseUrgency: 40,
        ),
      );
      final originalAnchor = task.baseUrgencyAnchorAt;

      now = DateTime.utc(2026, 10, 1, 11);
      final importanceOnly = await controller.save(task, importance: 80);
      expect(importanceOnly.importance, 80);
      expect(importanceOnly.baseUrgencyAnchorAt, originalAnchor);

      now = DateTime.utc(2026, 10, 1, 14);
      final urgencyChanged = await controller.save(
        importanceOnly,
        baseUrgency: 75,
      );
      expect(urgencyChanged.baseUrgency, 75);
      expect(urgencyChanged.baseUrgencyAnchorAt, DateTime.utc(2026, 10, 1, 14));
    },
  );

  test('deadline can be set without resetting urgency anchor', () async {
    final task = await tasks.createTask(
      const TaskDraft(
        title: 'DMA SPEC',
        status: TaskStatus.planned,
        baseUrgency: 50,
      ),
    );
    final anchor = task.baseUrgencyAnchorAt;

    now = DateTime.utc(2026, 10, 1, 15);
    final updated = await controller.save(
      task,
      deadline: DateTime.utc(2026, 10, 8),
    );

    expect(updated.deadline, DateTime.utc(2026, 10, 8));
    expect(updated.baseUrgencyAnchorAt, anchor);
  });

  test('waiting task disappears from executable stream', () async {
    final task = await tasks.createTask(
      const TaskDraft(title: 'Blocked review', status: TaskStatus.planned),
    );
    expect(
      (await tasks.watchExecutableTasks().first).map((item) => item.id),
      contains(task.id),
    );

    now = DateTime.utc(2026, 10, 1, 16);
    await controller.save(task, status: TaskStatus.waiting);

    expect(
      (await tasks.watchExecutableTasks().first).map((item) => item.id),
      isNot(contains(task.id)),
    );
  });

  test(
    'complete sets 100 percent, completion time, and activity event',
    () async {
      final task = await tasks.createTask(
        const TaskDraft(
          title: '4K boundary RTL',
          status: TaskStatus.inProgress,
          progress: 45,
        ),
      );

      now = DateTime.utc(2026, 10, 1, 17, 30);
      final completed = await controller.complete(task);

      expect(completed.status, TaskStatus.completed);
      expect(completed.progress, 100);
      expect(completed.completedAt, now);

      final events = await activity.fetchPage(task.id, limit: 20);
      final completedEvent = events.singleWhere(
        (event) => event.type == 'completed',
      );
      expect(completedEvent.occurredAt, now);
    },
  );

  test(
    'activity pagination returns newest events without loading everything',
    () async {
      final task = await tasks.createTask(
        const TaskDraft(title: 'Activity task', status: TaskStatus.planned),
      );

      for (var i = 0; i < 5; i += 1) {
        now = DateTime.utc(2026, 10, 1, 9 + i);
        await controller.save(task, importance: 51 + i);
      }

      final first = await activity.fetchPage(task.id, limit: 2);
      expect(first, hasLength(2));
      expect(first[0].occurredAt.isAfter(first[1].occurredAt), isTrue);

      final second = await activity.fetchPage(
        task.id,
        limit: 2,
        before: first.last.occurredAt,
      );
      expect(second, hasLength(2));
      expect(
        second.every(
          (event) => event.occurredAt.isBefore(first.last.occurredAt),
        ),
        isTrue,
      );
    },
  );

  test(
    'activity page cursor retains events sharing the same timestamp',
    () async {
      final task = await tasks.createTask(const TaskDraft(title: 'Same time'));
      for (var i = 0; i < 5; i++) {
        await controller.save(task, importance: 60 + i);
      }
      final first = await activity.fetchPage(task.id, limit: 2);
      final second = await activity.fetchPage(
        task.id,
        limit: 2,
        before: first.last.occurredAt,
        beforeId: first.last.id,
      );
      expect(second, hasLength(2));
    },
  );

  testWidgets('task preview can complete a task', (tester) async {
    final task = await tasks.createTask(
      const TaskDraft(
        title: 'Preview Task',
        status: TaskStatus.inProgress,
        progress: 25,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskPreviewDrawer(task: task, controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preview Task'), findsOneWidget);
    await tester.tap(find.text('标记完成'));
    await tester.pumpAndSettle();

    final saved = await tasks.get(task.id);
    expect(saved!.status, TaskStatus.completed);
    expect(saved.progress, 100);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('task detail exposes four lifecycle tabs', (tester) async {
    final task = await tasks.createTask(
      const TaskDraft(title: 'Detail Task', status: TaskStatus.planned),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailPage(
          taskId: task.id,
          tasks: tasks,
          editor: controller,
          activity: activity,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Subtasks'), findsOneWidget);
    expect(find.text('Dependencies'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Inbox shows only inbox tasks and can plan one', (tester) async {
    final inbox = await tasks.createTask(const TaskDraft(title: 'Inbox Task'));
    await tasks.createTask(
      const TaskDraft(title: 'Planned Task', status: TaskStatus.planned),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InboxPage(tasks: tasks, editor: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inbox Task'), findsOneWidget);
    expect(find.text('Planned Task'), findsNothing);

    await tester.tap(find.text('规划'));
    await tester.pumpAndSettle();

    expect((await tasks.get(inbox.id))!.status, TaskStatus.planned);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
