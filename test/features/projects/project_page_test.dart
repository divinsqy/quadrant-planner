import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/projects/project.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/projects/data/project_repository.dart';
import 'package:quadrant_planner/features/projects/presentation/project_detail_page.dart';
import 'package:quadrant_planner/features/projects/presentation/projects_page.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late ProjectRepository projects;
  late TaskRepository tasks;
  final now = DateTime.utc(2026, 10, 1, 9);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    var id = 0;
    projects = ProjectRepository(
      db,
      clock: () => now,
      idFactory: () => 'p-${id++}',
    );
    tasks = TaskRepository(db, clock: () => now, idFactory: () => 't-${id++}');
  });
  tearDown(() => db.close());

  testWidgets(
    'Projects creates a local project with objective and deadline and opens it',
    (tester) async {
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectsPage(
            projects: projects,
            tasks: tasks,
            onOpenProject: (id) => opened = id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建项目'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('project-name')),
        '  Release  ',
      );
      await tester.enterText(
        find.byKey(const Key('project-objective')),
        'Ship desktop app',
      );
      await tester.enterText(
        find.byKey(const Key('project-deadline')),
        '2026-10-31',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final saved = (await projects.search('Release')).single;
      expect(saved.name, 'Release');
      expect(saved.objective, 'Ship desktop app');
      expect(saved.deadline?.toLocal().day, 31);
      await tester.tap(find.text('Release'));
      expect(opened, saved.id);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('project create errors preserve the dialog draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsPage(
          projects: _FailingProjects(db),
          tasks: tasks,
          onOpenProject: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('project-name')), 'Keep draft');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Disk is full'), findsOneWidget);
    expect(find.text('Keep draft'), findsOneWidget);
    expect(await projects.search('Keep draft'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('detail edits project objective and removes deadline', (
    tester,
  ) async {
    final project = await projects.createProject(
      name: 'Launch',
      objective: 'Old objective',
      deadline: DateTime.utc(2026, 10, 30),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectDetailPage(
          projectId: project.id,
          projects: projects,
          tasks: tasks,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑项目'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('project-name')),
      'Launch revised',
    );
    await tester.enterText(
      find.byKey(const Key('project-objective')),
      'Evidence based',
    );
    await tester.enterText(find.byKey(const Key('project-deadline')), '');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final saved = (await projects.get(project.id))!;
    expect(saved.name, 'Launch revised');
    expect(saved.objective, 'Evidence based');
    expect(saved.deadline, isNull);
    expect(find.text('Evidence based'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'detail tabs show owned tasks, editable milestones and dated timeline',
    (tester) async {
      final project = await projects.createProject(
        name: 'Launch',
        objective: 'Deliver v1',
      );
      final task = await tasks.createTask(
        TaskDraft(
          title: 'Owned task',
          projectId: project.id,
          status: TaskStatus.waiting,
          deadline: DateTime.utc(2026, 10, 10),
        ),
      );
      await tasks.createTask(const TaskDraft(title: 'Outside task'));
      String? openedTask;
      String? quadrantProject;
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectDetailPage(
            projectId: project.id,
            projects: projects,
            tasks: tasks,
            onOpenTask: (id) => openedTask = id,
            onShowQuadrant: (id) => quadrantProject = id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('在象限中查看'));
      expect(quadrantProject, project.id);
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();
      expect(find.text('Owned task'), findsOneWidget);
      expect(find.text('Outside task'), findsNothing);
      await tester.tap(find.text('Owned task'));
      expect(openedTask, task.id);
      await tester.tap(find.text('Milestones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建里程碑'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('milestone-name')), 'Beta');
      await tester.enterText(
        find.byKey(const Key('milestone-deadline')),
        '2026-10-08',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final milestone = (await tester.runAsync(
        () => projects.watchMilestones(project.id).first,
      ))!.single;
      await tester.tap(find.byKey(Key('milestone-complete-${milestone.id}')));
      await tester.pumpAndSettle();
      expect(
        (await projects.getMilestone(milestone.id))?.completedAt,
        isNotNull,
      );
      await tester.tap(find.byTooltip('编辑里程碑'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('milestone-name')),
        'Beta checked',
      );
      await tester.enterText(
        find.byKey(const Key('milestone-deadline')),
        '2026-10-09',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect((await projects.getMilestone(milestone.id))?.name, 'Beta checked');
      expect(
        (await projects.getMilestone(milestone.id))?.deadline?.toLocal().day,
        9,
      );
      await tester.tap(find.text('Timeline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Beta checked'), findsWidgets);
      expect(find.textContaining('Owned task'), findsWidgets);
      expect(find.text('2026-10-10'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('project pages remain usable in narrow windows with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final project = await projects.createProject(
      name: 'A lengthy desktop release project',
      objective: 'A long objective that should wrap across multiple lines.',
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ProjectDetailPage(
          projectId: project.id,
          projects: projects,
          tasks: tasks,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('编辑项目'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'completed task status displays 100 percent and project progress stays live',
    (tester) async {
      final project = await projects.createProject(name: 'Release');
      final task = await tasks.createTask(
        TaskDraft(
          title: 'Finished task',
          projectId: project.id,
          status: TaskStatus.completed,
          progress: 0,
          estimatedMinutes: 60,
        ),
      );
      await tasks.createTask(
        TaskDraft(
          title: 'Remaining task',
          projectId: project.id,
          estimatedMinutes: 180,
        ),
      );
      await tasks.createTask(
        const TaskDraft(
          title: 'Outside completed',
          status: TaskStatus.completed,
          estimatedMinutes: 1000,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectDetailPage(
            projectId: project.id,
            projects: projects,
            tasks: tasks,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('进度 25.0%'), findsOneWidget);
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();
      expect(find.text('已完成 · 100%'), findsOneWidget);
      await tasks.save(task.copyWith(status: TaskStatus.waiting, progress: 50));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('进度 0.0%'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

class _FailingProjects extends ProjectRepository {
  _FailingProjects(super.db);

  @override
  Future<Project> createProject({
    required String name,
    String objective = '',
    DateTime? deadline,
  }) async {
    throw StateError('Disk is full');
  }
}
