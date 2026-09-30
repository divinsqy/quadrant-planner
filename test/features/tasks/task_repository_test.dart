import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/projects/project.dart' as domain;
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/projects/data/project_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late DateTime now;
  late TaskRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    now = DateTime.utc(2026, 9, 30, 9);
    var id = 0;
    repo = TaskRepository(
      db,
      idFactory: () {
        id += 1;
        return 'task-$id';
      },
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  test('watchTask emits a saved task update', () async {
    final task = await repo.createTask(
      const TaskDraft(title: 'DMA', status: TaskStatus.planned),
    );

    final updatedFuture = repo
        .watchTask(task.id)
        .where((value) => value?.title == 'Updated')
        .first;

    now = now.add(const Duration(hours: 1));
    await repo.save(task.copyWith(title: 'Updated', updatedAt: now));

    final updated = await updatedFuture;
    expect(updated, isNotNull);
    expect(updated!.title, 'Updated');
  });

  test('watchExecutableTasks includes only planned and in-progress non-deleted tasks', () async {
    final planned = await repo.createTask(
      const TaskDraft(title: 'Planned', status: TaskStatus.planned),
    );
    final running = await repo.createTask(
      const TaskDraft(title: 'Running', status: TaskStatus.inProgress),
    );
    await repo.createTask(
      const TaskDraft(title: 'Waiting', status: TaskStatus.waiting),
    );
    await repo.createTask(
      const TaskDraft(title: 'Inbox', status: TaskStatus.inbox),
    );

    var executable = await repo.watchExecutableTasks().first;
    expect(executable.map((e) => e.id).toSet(), {planned.id, running.id});

    now = now.add(const Duration(hours: 2));
    await repo.softDelete(planned.id, now);

    executable = await repo.watchExecutableTasks().first;
    expect(executable.map((e) => e.id).toSet(), {running.id});
  });

  test('saving a task reassigns its single project instead of adding another ownership', () async {
    final projects = ProjectRepository(db);
    final created = DateTime.utc(2026, 9, 30);
    await projects.save(domain.Project(
      id: 'p1',
      name: 'DMAC',
      objective: '',
      deadline: null,
      createdAt: created,
      updatedAt: created,
    ));
    await projects.save(domain.Project(
      id: 'p2',
      name: 'UVM',
      objective: '',
      deadline: null,
      createdAt: created,
      updatedAt: created,
    ));

    final task = await repo.createTask(
      const TaskDraft(
        title: 'Task',
        status: TaskStatus.planned,
        projectId: 'p1',
      ),
    );
    await repo.save(task.copyWith(projectId: 'p2'));

    final saved = await repo.watchTask(task.id).first;
    expect(saved!.projectId, 'p2');
  });
}
