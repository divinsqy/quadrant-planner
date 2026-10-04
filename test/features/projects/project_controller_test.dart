import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/projects/application/project_controller.dart';
import 'package:quadrant_planner/features/projects/data/project_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late ProjectRepository projects;
  late TaskRepository tasks;
  late ProjectController controller;
  final now = DateTime.utc(2026, 10, 1, 9);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    var id = 0;
    projects = ProjectRepository(
      db,
      clock: () => now,
      idFactory: () => 'p-${id++}',
    );
    tasks = TaskRepository(db, clock: () => now, idFactory: () => 't-${id++}');
    await projects.createProject(name: 'Launch', objective: 'Deliver v1');
    controller = ProjectController(
      projectId: 'p-0',
      projects: projects,
      tasks: tasks,
      clock: () => now,
    )..start();
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  test(
    'project state follows all owned task statuses and live progress',
    () async {
      await _until(controller, () => !controller.state.isLoading);
      final owned = await tasks.createTask(
        const TaskDraft(
          title: 'Owned',
          projectId: 'p-0',
          status: TaskStatus.waiting,
          estimatedMinutes: 60,
        ),
      );
      await tasks.createTask(
        const TaskDraft(title: 'Outside', status: TaskStatus.planned),
      );
      await _until(controller, () => controller.state.tasks.length == 1);
      expect(controller.state.tasks.single.id, owned.id);
      expect(controller.state.progress, 0);
      await tasks.save(owned.copyWith(status: TaskStatus.completed));
      await _until(controller, () => controller.state.progress == 100);
      expect(controller.state.tasks.single.status, TaskStatus.completed);
    },
  );

  test(
    'project edit preserves identity and creation while clearing deadline',
    () async {
      await _until(controller, () => !controller.state.isLoading);
      await controller.saveProject(
        name: 'Launch edited',
        objective: 'Evidence',
        deadline: null,
      );
      await _until(
        controller,
        () => controller.state.project?.name == 'Launch edited',
      );
      final saved = await projects.get('p-0');
      expect(saved?.objective, 'Evidence');
      expect(saved?.createdAt, now);
      expect(saved?.deadline, isNull);
    },
  );

  test(
    'milestone completion can be reopened and edited without losing identity',
    () async {
      await _until(controller, () => !controller.state.isLoading);
      final milestone = await controller.createMilestone(
        name: 'Beta',
        deadline: DateTime.utc(2026, 10, 15),
      );
      await controller.setMilestoneCompleted(milestone, true);
      final complete = (await projects.getMilestone(milestone.id))!;
      expect(complete.completedAt, now);
      await controller.saveMilestone(
        complete,
        name: 'Beta checked',
        deadline: null,
      );
      expect((await projects.getMilestone(milestone.id))?.completedAt, now);
      await controller.setMilestoneCompleted(complete, false);
      final reopened = (await projects.getMilestone(milestone.id))!;
      expect(reopened.completedAt, isNull);
      expect(reopened.name, 'Beta checked');
      expect(reopened.deadline, isNull);
    },
  );

  test(
    'timeline derives task and milestone dates and keeps source ids',
    () async {
      await _until(controller, () => !controller.state.isLoading);
      final task = await tasks.createTask(
        TaskDraft(
          title: 'Release test',
          projectId: 'p-0',
          deadline: DateTime.utc(2026, 10, 10),
        ),
      );
      final milestone = await controller.createMilestone(
        name: 'Beta',
        deadline: DateTime.utc(2026, 10, 8),
      );
      await _until(
        controller,
        () =>
            controller.state.tasks.isNotEmpty &&
            controller.state.milestones.isNotEmpty,
      );
      expect(
        controller.state.timeline
            .where((item) => item.taskId == task.id)
            .map((item) => item.date),
        contains(DateTime.utc(2026, 10, 10)),
      );
      expect(
        controller.state.timeline
            .where((item) => item.milestoneId == milestone.id)
            .map((item) => item.date),
        contains(DateTime.utc(2026, 10, 8)),
      );
      final dates = controller.state.timeline.map((item) => item.date).toList();
      expect(dates, orderedEquals([...dates]..sort()));
    },
  );
}

Future<void> _until(ProjectController controller, bool Function() ready) {
  if (ready()) return Future.value();
  final completer = Completer<void>();
  void listener() {
    if (ready()) {
      controller.removeListener(listener);
      completer.complete();
    }
  }

  controller.addListener(listener);
  return completer.future.timeout(const Duration(seconds: 5));
}
