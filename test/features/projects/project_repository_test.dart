import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/projects/milestone.dart';
import 'package:quadrant_planner/domain/projects/project.dart';
import 'package:quadrant_planner/features/projects/data/project_repository.dart';

void main() {
  late AppDatabase db;
  late ProjectRepository projects;
  final now = DateTime.utc(2026, 10, 1);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    var nextId = 0;
    projects = ProjectRepository(
      db,
      clock: () => now,
      idFactory: () => 'new-${nextId++}',
    );
  });
  tearDown(() => db.close());

  test('empty project names are rejected before persistence', () async {
    await expectLater(
      projects.save(
        Project(
          id: 'p1',
          name: '   ',
          objective: '',
          deadline: null,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsArgumentError,
    );
    expect(await projects.watchAll().first, isEmpty);
  });

  test(
    'create and edit project persist identity, objective and deadline',
    () async {
      final Project project = await (projects as dynamic).createProject(
        name: '  Launch  ',
        objective: 'Release locally',
        deadline: DateTime.utc(2026, 11, 1),
      );
      expect(project.name, 'Launch');
      await projects.save(
        Project(
          id: project.id,
          name: 'Launch v1',
          objective: 'Validated release',
          deadline: null,
          createdAt: project.createdAt,
          updatedAt: now,
        ),
      );
      final Project? saved = await (projects as dynamic).get(project.id);
      expect(saved?.name, 'Launch v1');
      expect(saved?.objective, 'Validated release');
      expect(saved?.deadline, isNull);
      expect(saved?.createdAt, project.createdAt);
    },
  );

  test(
    'milestone stream is scoped and completion survives a database read',
    () async {
      for (final id in ['p1', 'p2']) {
        await projects.save(
          Project(
            id: id,
            name: id,
            objective: '',
            deadline: null,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      final Milestone milestone = await (projects as dynamic).createMilestone(
        projectId: 'p1',
        name: '  Beta  ',
        deadline: DateTime.utc(2026, 10, 15),
      );
      await (projects as dynamic).createMilestone(
        projectId: 'p2',
        name: 'Other',
      );
      final stream = (projects as dynamic).watchMilestones(
        'p1',
      ) as Stream<List<Milestone>>;
      final updated = stream
          .where((items) => items.single.completedAt != null)
          .first;
      await (projects as dynamic).saveMilestone(
        Milestone(
          id: milestone.id,
          projectId: 'p1',
          name: 'Beta validated',
          deadline: null,
          completedAt: now,
          createdAt: milestone.createdAt,
          updatedAt: now,
        ),
      );
      expect((await updated).single.name, 'Beta validated');
      final Milestone? saved = await (projects as dynamic).getMilestone(
        milestone.id,
      );
      expect(saved?.completedAt, now);
      expect(saved?.deadline, isNull);
      expect(await stream.first, hasLength(1));
    },
  );

  test('milestones require an active project and a nonempty name', () async {
    await expectLater(
      (projects as dynamic).createMilestone(projectId: 'missing', name: 'Beta'),
      throwsArgumentError,
    );
    await projects.save(
      Project(
        id: 'p1',
        name: 'Project',
        objective: '',
        deadline: null,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await expectLater(
      (projects as dynamic).createMilestone(projectId: 'p1', name: ' '),
      throwsArgumentError,
    );
  });

  test(
    'project lists expose UTC dates consistently with single-project reads',
    () async {
      await projects.createProject(
        name: 'Release',
        deadline: DateTime.utc(2026, 10, 31),
      );
      final watched = (await projects.watchAll().first).single;
      expect(watched.createdAt, now);
      expect(watched.deadline, DateTime.utc(2026, 10, 31));
      expect(watched.createdAt.isUtc, isTrue);
      expect((await projects.search('Release')).single.deadline?.isUtc, isTrue);
    },
  );
}
