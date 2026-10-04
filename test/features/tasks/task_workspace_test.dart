import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/tasks/application/tasks_library_controller.dart';
import 'package:quadrant_planner/features/tasks/data/task_activity_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_relations_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';
import 'package:quadrant_planner/features/tasks/application/task_editor_controller.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_editor.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_detail_page.dart';
import 'package:quadrant_planner/features/tasks/presentation/tasks_page.dart';
import 'package:quadrant_planner/domain/projects/project.dart' as domain;
import 'package:quadrant_planner/domain/projects/milestone.dart';
import 'package:quadrant_planner/features/projects/data/project_repository.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_preview_drawer.dart';
import 'package:quadrant_planner/features/inbox/presentation/inbox_page.dart';

void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late TaskRelationsRepository relations;
  final now = DateTime.utc(2026, 10, 1);
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    var id = 0;
    tasks = TaskRepository(
      db,
      idFactory: () => 'task-${++id}',
      clock: () => now,
    );
    relations = TaskRelationsRepository(db, clock: () => now);
  });
  tearDown(() => db.close());

  test('subtasks persist edits completion and soft deletion', () async {
    final task = await tasks.createTask(const TaskDraft(title: 'Parent'));
    final item = await relations.addSubtask(task.id, '  Write RTL  ');
    expect(
      (await relations.watchSubtasks(task.id).first).single.title,
      'Write RTL',
    );
    await relations.updateSubtask(
      item.id,
      title: 'Verify RTL',
      completed: true,
    );
    final saved = (await relations.watchSubtasks(task.id).first).single;
    expect(saved.completed, isTrue);
    expect(saved.title, 'Verify RTL');
    await relations.deleteSubtask(item.id);
    expect(await relations.watchSubtasks(task.id).first, isEmpty);
    await expectLater(relations.addSubtask(task.id, ' '), throwsArgumentError);
  });

  test(
    'dependencies reject self cycles and duplicates and react to completion',
    () async {
      final a = await tasks.createTask(
        const TaskDraft(title: 'A', status: TaskStatus.planned),
      );
      final b = await tasks.createTask(const TaskDraft(title: 'B'));
      final c = await tasks.createTask(const TaskDraft(title: 'C'));
      await expectLater(
        relations.addDependency(a.id, a.id),
        throwsArgumentError,
      );
      await relations.addDependency(a.id, b.id);
      await relations.addDependency(b.id, c.id);
      await expectLater(
        relations.addDependency(c.id, a.id),
        throwsArgumentError,
      );
      await expectLater(
        relations.addDependency(a.id, b.id),
        throwsArgumentError,
      );
      expect(await relations.watchBlockedTaskIds().first, {a.id, b.id});
      expect(
        (await relations.watchDependencies(a.id).first).single.blockingReason,
        contains('B'),
      );
      final unblocked = relations
          .watchBlockedTaskIds()
          .where((ids) => !ids.contains(a.id))
          .first;
      await tasks.save(b.copyWith(status: TaskStatus.completed));
      expect(await unblocked, {b.id});
      final dependency = (await relations.watchDependencies(a.id).first).single;
      await relations.removeDependency(dependency.dependency.id);
      expect(await relations.watchDependencies(a.id).first, isEmpty);
      await tasks.softDelete(c.id, now);
      expect(await relations.watchBlockedTaskIds().first, {b.id});
      final deletedPrerequisite =
          (await relations.watchDependencies(b.id).first).single;
      expect(deletedPrerequisite.satisfied, isFalse);
      expect(deletedPrerequisite.blockingReason, contains('已删除'));
      await relations.removeDependency(deletedPrerequisite.dependency.id);
      expect(await relations.watchBlockedTaskIds().first, isEmpty);
    },
  );

  test('recent activity observes new evidence and bounds the tail', () async {
    final task = await tasks.createTask(const TaskDraft(title: 'Evidence'));
    final activity = TaskActivityRepository(db);
    final next = activity
        .watchRecent(task.id, limit: 2)
        .where((events) => events.any((e) => e.type == 'test'))
        .first;
    await activity.add(taskId: task.id, type: 'test', occurredAt: now);
    expect(await next, hasLength(2));
    await expectLater(
      activity.fetchPage(task.id, limit: 0),
      throwsArgumentError,
    );
  });

  test(
    'task library preserves query selection scroll and combines filters',
    () async {
      final a = await tasks.createTask(
        const TaskDraft(title: 'DMA RTL', status: TaskStatus.planned),
      );
      await tasks.createTask(
        const TaskDraft(title: 'UVM RTL', status: TaskStatus.waiting),
      );
      await db
          .into(db.tags)
          .insert(
            TagsCompanion(id: const Value('tag'), name: const Value('RTL')),
          );
      await db
          .into(db.taskTags)
          .insert(
            TaskTagsCompanion(taskId: Value(a.id), tagId: const Value('tag')),
          );
      final controller = TasksLibraryController(
        tasks: tasks,
        initialTagId: 'tag',
      );
      addTearDown(controller.dispose);
      controller.setFilters(query: 'DMA', statuses: {TaskStatus.planned});
      controller.selectTask(a.id);
      controller.updateScrollOffset(123);
      expect((await controller.watchTasks().first).map((t) => t.id), [a.id]);
      expect(controller.state.selectedTaskId, a.id);
      expect(controller.state.scrollOffset, 123);
      expect(controller.state.tagId, 'tag');
      controller.setFilters(tagId: null);
      expect(controller.state.query, 'DMA');
      expect(controller.state.tagId, isNull);
    },
  );

  test('creation records durable activity in the task transaction', () async {
    final task = await tasks.createTask(const TaskDraft(title: 'Created'));
    final events = await TaskActivityRepository(db).fetchPage(task.id);
    expect(events.single.type, 'created');
    expect(events.single.payload['title'], 'Created');
  });

  testWidgets(
    'Overview saves deadline estimate workload progress and report inclusion',
    (tester) async {
      final task = await tasks.createTask(const TaskDraft(title: 'Overview'));
      final editor = TaskEditorController(
        tasks: tasks,
        activity: TaskActivityRepository(db),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskEditor(task: task, controller: editor),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, '截止日期（YYYY-MM-DD）'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.widgetWithText(TextField, '截止日期（YYYY-MM-DD）'),
        '2026-10-12',
      );
      await tester.enterText(find.widgetWithText(TextField, '预计时长（分钟）'), '90');
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, '完成进度（0–100）'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.widgetWithText(TextField, '完成进度（0–100）'),
        '40',
      );
      await tester.ensureVisible(find.text('计入周报'));
      await tester.tap(find.text('计入周报'));
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final saved = (await tasks.get(task.id))!;
      expect(saved.deadline!.toLocal().day, 12);
      expect(saved.estimatedMinutes, 90);
      expect(saved.progress, 40);
      expect(saved.includeInWeeklyReport, isFalse);
      expect(find.text('工作量'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'preview editing closes safely after the preview owner is disposed',
    (tester) async {
      final task = await tasks.createTask(
        const TaskDraft(title: 'Preview lifecycle', status: TaskStatus.planned),
      );
      final editor = TaskEditorController(
        tasks: tasks,
        activity: TaskActivityRepository(db),
      );
      var visible = true;
      var changedCallbacks = 0;
      late StateSetter rebuildOwner;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuildOwner = setState;
                return visible
                    ? TaskPreviewDrawer(
                        task: task,
                        controller: editor,
                        onTaskChanged: (_) => changedCallbacks++,
                      )
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('轻量编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<TaskStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('等待中').last);
      await tester.pumpAndSettle();
      rebuildOwner(() => visible = false);
      await tester.pumpAndSettle();
      expect(find.byType(TaskPreviewDrawer), findsNothing);
      expect(find.byType(Dialog), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('保存'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(TaskEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect((await tasks.get(task.id))!.status, TaskStatus.waiting);
      expect(find.byType(Dialog), findsNothing);
      expect(changedCallbacks, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('narrow task library restores its scroll after closing preview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (var i = 0; i < 50; i++) {
      await tasks.createTask(TaskDraft(title: 'Scroll task $i'));
    }
    final activity = TaskActivityRepository(db);
    final library = TasksLibraryController(tasks: tasks);
    addTearDown(library.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TasksPage(
          tasks: tasks,
          editor: TaskEditorController(tasks: tasks, activity: activity),
          activity: activity,
          controller: library,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView).last);
    list.controller!.jumpTo(1000);
    await tester.pumpAndSettle();
    final before = list.controller!.offset;
    await tester.tap(find.byType(ListTile).hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    final after = tester
        .widget<ListView>(find.byType(ListView).last)
        .controller!
        .offset;
    expect(after, before);
    expect(library.state.scrollOffset, before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Subtasks tab adds checks renames and deletes persisted children',
    (tester) async {
      final task = await tasks.createTask(const TaskDraft(title: 'Detail'));
      final activity = TaskActivityRepository(db);
      final editor = TaskEditorController(tasks: tasks, activity: activity);
      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailPage(
            taskId: task.id,
            tasks: tasks,
            editor: editor,
            activity: activity,
            relations: relations,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subtasks'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '子任务标题'),
        'Check RTL',
      );
      await tester.tap(find.text('添加子任务'));
      await tester.pumpAndSettle();
      expect(find.text('Check RTL'), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(() => relations.watchSubtasks(task.id).first))!
            .single
            .completed,
        isTrue,
      );
      await tester.tap(find.byTooltip('编辑子任务'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '子任务标题').last,
        'Verified',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('Verified'), findsOneWidget);
      await tester.tap(find.byTooltip('删除子任务'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => relations.watchSubtasks(task.id).first),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Tasks filters and selection survive remount on narrow large-text windows',
    (tester) async {
      final task = await tasks.createTask(
        const TaskDraft(title: 'DMA', status: TaskStatus.planned),
      );
      await tasks.createTask(const TaskDraft(title: 'Other'));
      final activity = TaskActivityRepository(db);
      final editor = TaskEditorController(tasks: tasks, activity: activity);
      final library = TasksLibraryController(tasks: tasks)
        ..setFilters(query: 'DMA')
        ..selectTask(task.id);
      addTearDown(library.dispose);
      await tester.binding.setSurfaceSize(const Size(360, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget page() => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: TasksPage(
            tasks: tasks,
            editor: editor,
            activity: activity,
            controller: library,
            projects: ProjectRepository(db),
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('Other'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('项目筛选'),
        100,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('tasks-filters')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部项目'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部项目').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('轻量编辑'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(TaskPreviewDrawer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('轻量编辑'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(library.state.query, 'DMA');
      expect(library.state.selectedTaskId, task.id);
      await tester.scrollUntilVisible(
        find.text('轻量编辑'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(TaskPreviewDrawer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('轻量编辑'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  test(
    'project assignment keeps one owner and validates milestone membership',
    () async {
      final projects = ProjectRepository(db);
      for (final id in ['p1', 'p2']) {
        await projects.save(
          domain.Project(
            id: id,
            name: id,
            objective: '',
            deadline: null,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await projects.saveMilestone(
        Milestone(
          id: 'm1',
          projectId: 'p1',
          name: 'RTL',
          deadline: null,
          completedAt: null,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final task = await tasks.createTask(
        const TaskDraft(
          title: 'Membership',
          projectId: 'p1',
          milestoneId: 'm1',
        ),
      );
      final editor = TaskEditorController(
        tasks: tasks,
        activity: TaskActivityRepository(db),
      );
      final updated = await editor.save(task, title: 'Keep membership');
      expect(updated.projectId, 'p1');
      expect(updated.milestoneId, 'm1');
      final reassigned = await editor.save(updated, projectId: 'p2');
      expect(reassigned.projectId, 'p2');
      expect(reassigned.milestoneId, isNull);
      await expectLater(
        editor.save(reassigned, milestoneId: 'm1'),
        throwsArgumentError,
      );
      expect((await tasks.get(task.id))!.milestoneId, isNull);
    },
  );

  test('failed activity persistence rolls back the task edit', () async {
    final task = await tasks.createTask(const TaskDraft(title: 'Before'));
    final editor = TaskEditorController(
      tasks: tasks,
      activity: _FailingActivity(db),
    );
    await expectLater(editor.save(task, title: 'After'), throwsStateError);
    expect((await tasks.get(task.id))!.title, 'Before');
    expect(await TaskActivityRepository(db).fetchPage(task.id), hasLength(1));
  });

  testWidgets(
    'editor leaves a concurrently changed project intact when its project control was untouched',
    (tester) async {
      final projects = ProjectRepository(db);
      for (final id in ['p1', 'p2']) {
        await projects.save(
          domain.Project(
            id: id,
            name: id,
            objective: '',
            deadline: null,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      final task = await tasks.createTask(
        const TaskDraft(title: 'Original', projectId: 'p1'),
      );
      final editor = TaskEditorController(
        tasks: tasks,
        activity: TaskActivityRepository(db),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskEditor(task: task, controller: editor),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tasks.save(task.copyWith(projectId: 'p2'));
      await tester.enterText(find.widgetWithText(TextField, '任务标题'), 'Edited');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final saved = (await tasks.get(task.id))!;
      expect(saved.title, 'Edited');
      expect(saved.projectId, 'p2');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'preview lightweight editing saves title and shows failed saves',
    (tester) async {
      final task = await tasks.createTask(
        const TaskDraft(title: 'Preview edit'),
      );
      final editor = TaskEditorController(
        tasks: tasks,
        activity: TaskActivityRepository(db),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskPreviewDrawer(task: task, controller: editor),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('轻量编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '任务标题'),
        'Updated preview',
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(TaskEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect((await tasks.get(task.id))!.title, 'Updated preview');
      expect(find.text('Updated preview'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskPreviewDrawer(
              task: task,
              controller: TaskEditorController(
                tasks: tasks,
                activity: _FailingActivity(db),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('标记完成'));
      await tester.pumpAndSettle();
      expect(find.textContaining('保存失败'), findsOneWidget);
      expect((await tasks.get(task.id))!.status, TaskStatus.inbox);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Inbox planning editor persists planned status without requiring another field edit',
    (tester) async {
      final task = await tasks.createTask(const TaskDraft(title: 'Plan me'));
      final editor = TaskEditorController(
        tasks: tasks,
        activity: TaskActivityRepository(db),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InboxPage(tasks: tasks, editor: editor),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('规划并编辑'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(TaskEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect((await tasks.get(task.id))!.status, TaskStatus.planned);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Dependencies tab adds removes blockers and visibly rejects cycles',
    (tester) async {
      final a = await tasks.createTask(const TaskDraft(title: 'Dependent'));
      final b = await tasks.createTask(const TaskDraft(title: 'Prerequisite'));
      final reverse = await relations.addDependency(b.id, a.id);
      final activity = TaskActivityRepository(db);
      final editor = TaskEditorController(tasks: tasks, activity: activity);
      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailPage(
            taskId: a.id,
            tasks: tasks,
            editor: editor,
            activity: activity,
            relations: relations,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dependencies'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prerequisite').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加依赖'));
      await tester.pumpAndSettle();
      expect(find.textContaining('循环'), findsOneWidget);
      await relations.removeDependency(reverse.id);
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加依赖'));
      await tester.pumpAndSettle();
      expect(find.text('等待前置任务完成：Prerequisite'), findsOneWidget);
      await editor.complete(b);
      await tester.pumpAndSettle();
      expect(find.text('前置依赖已满足'), findsOneWidget);
      await tester.tap(find.byTooltip('移除依赖'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => relations.watchDependencies(a.id).first),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Activity tab loads beyond fifty same-time events without skipping older evidence',
    (tester) async {
      final task = await tasks.createTask(const TaskDraft(title: 'History'));
      var id = 0;
      final activity = TaskActivityRepository(
        db,
        idFactory: () => 'event-${(++id).toString().padLeft(3, '0')}',
      );
      for (var i = 0; i < 55; i++) {
        await activity.add(
          taskId: task.id,
          type: 'activity-${i.toString().padLeft(2, '0')}',
          occurredAt: now.add(const Duration(hours: 1)),
        );
      }
      final editor = TaskEditorController(tasks: tasks, activity: activity);
      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailPage(
            taskId: task.id,
            tasks: tasks,
            editor: editor,
            activity: activity,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('加载更多活动'),
        600,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('加载更多活动'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('activity-00'),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('activity-00'), findsOneWidget);
      expect(find.text('加载更多活动'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

class _FailingActivity extends TaskActivityRepository {
  _FailingActivity(super.db);
  @override
  Future<Never> add({
    required String taskId,
    required String type,
    required DateTime occurredAt,
    Map<String, dynamic> payload = const {},
  }) async => throw StateError('activity unavailable');
}
