import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/projects/project.dart' as domain;
import 'package:quadrant_planner/domain/settings/app_preferences.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/projects/data/project_repository.dart';
import 'package:quadrant_planner/features/settings/data/preferences_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late TaskRepository tasks;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(
      db,
      idFactory: () => 'task-1',
      clock: () => DateTime.utc(2026, 9, 30, 9),
    );
  });

  tearDown(() => db.close());

  test('foreign keys reject a task that references a missing project', () async {
    final draft = TaskDraft(
      title: 'DMA',
      status: TaskStatus.planned,
      projectId: 'missing-project',
    );

    await expectLater(tasks.createTask(draft), throwsA(isA<Exception>()));
  });

  test('one task can link to multiple tags through task_tags', () async {
    final task = await tasks.createTask(
      const TaskDraft(title: 'DMA', status: TaskStatus.planned),
    );
    await db.into(db.tags).insert(
          TagsCompanion.insert(id: 'tag-a', name: 'RTL'),
        );
    await db.into(db.tags).insert(
          TagsCompanion.insert(id: 'tag-b', name: 'UVM'),
        );

    await db.into(db.taskTags).insert(
          TaskTagsCompanion.insert(taskId: task.id, tagId: 'tag-a'),
        );
    await db.into(db.taskTags).insert(
          TaskTagsCompanion.insert(taskId: task.id, tagId: 'tag-b'),
        );

    final links = await db.select(db.taskTags).get();
    expect(links.map((e) => e.tagId).toSet(), {'tag-a', 'tag-b'});
  });

  test('preferences repository defaults then emits saved values', () async {
    final repo = PreferencesRepository(db);
    expect(await repo.watch().first, isA<AppPreferences>());
    expect((await repo.watch().first).importanceThreshold, 50);

    const changed = AppPreferences(
      nickname: 'Divins',
      importanceThreshold: 62,
      urgencyThreshold: 57,
    );
    await repo.save(changed);

    final saved = await repo.watch().first;
    expect(saved.nickname, 'Divins');
    expect(saved.importanceThreshold, 62);
    expect(saved.urgencyThreshold, 57);
  });

  test('project repository saves and watches active projects', () async {
    final repo = ProjectRepository(db);
    final now = DateTime.utc(2026, 9, 30);
    final project = domain.Project(
      id: 'p1',
      name: 'DMAC',
      objective: 'Complete controller',
      deadline: DateTime.utc(2026, 11, 30),
      createdAt: now,
      updatedAt: now,
    );

    await repo.save(project);
    final items = await repo.watchAll().first;

    expect(items, hasLength(1));
    expect(items.single.id, 'p1');
    expect(items.single.name, 'DMAC');
  });
}
