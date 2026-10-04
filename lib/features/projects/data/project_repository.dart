import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/projects/milestone.dart';
import '../../../domain/projects/project.dart' as domain;

class ProjectRepository {
  final AppDatabase _db;
  final String Function() _idFactory;
  final DateTime Function() _clock;

  ProjectRepository(
    this._db, {
    String Function()? idFactory,
    DateTime Function()? clock,
  }) : _idFactory = idFactory ?? (() => const Uuid().v4()),
       _clock = clock ?? (() => DateTime.now().toUtc());

  Future<domain.Project> createProject({
    required String name,
    String objective = '',
    DateTime? deadline,
  }) async {
    final now = _clock().toUtc();
    final project = domain.Project(
      id: _idFactory(),
      name: name.trim(),
      objective: objective,
      deadline: deadline?.toUtc(),
      createdAt: now,
      updatedAt: now,
    );
    await save(project);
    return project;
  }

  Future<void> save(domain.Project project) async {
    _requireNonempty(project.id, 'id');
    _requireNonempty(project.name, 'name');
    await _db
        .into(_db.projects)
        .insertOnConflictUpdate(
          ProjectsCompanion(
            id: Value(project.id),
            name: Value(project.name.trim()),
            objective: Value(project.objective),
            deadline: Value(project.deadline?.toUtc()),
            createdAt: Value(project.createdAt.toUtc()),
            updatedAt: Value(project.updatedAt.toUtc()),
            deletedAt: Value(project.deletedAt?.toUtc()),
          ),
        );
  }

  Future<domain.Project?> get(String id) async {
    final row =
        await (_db.select(_db.projects)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .getSingleOrNull();
    return row == null ? null : _projectFromRow(row);
  }

  Stream<domain.Project?> watchProject(String id) {
    return (_db.select(_db.projects)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .watchSingleOrNull()
        .map((row) => row == null ? null : _projectFromRow(row));
  }

  Future<Milestone> createMilestone({
    required String projectId,
    required String name,
    DateTime? deadline,
  }) async {
    final now = _clock().toUtc();
    final milestone = Milestone(
      id: _idFactory(),
      projectId: projectId,
      name: name.trim(),
      deadline: deadline?.toUtc(),
      completedAt: null,
      createdAt: now,
      updatedAt: now,
    );
    await saveMilestone(milestone);
    return milestone;
  }

  Future<void> saveMilestone(Milestone milestone) => _db.transaction(() async {
    _requireNonempty(milestone.id, 'id');
    _requireNonempty(milestone.name, 'name');
    if (await get(milestone.projectId) == null) {
      throw ArgumentError.value(
        milestone.projectId,
        'projectId',
        'project must exist',
      );
    }
    await _db
        .into(_db.milestones)
        .insertOnConflictUpdate(
          MilestonesCompanion(
            id: Value(milestone.id),
            projectId: Value(milestone.projectId),
            name: Value(milestone.name.trim()),
            deadline: Value(milestone.deadline?.toUtc()),
            completedAt: Value(milestone.completedAt?.toUtc()),
            createdAt: Value(milestone.createdAt.toUtc()),
            updatedAt: Value(milestone.updatedAt.toUtc()),
          ),
        );
    await _db
        .into(_db.milestoneHistory)
        .insert(
          MilestoneHistoryCompanion.insert(
            milestoneId: milestone.id,
            projectId: milestone.projectId,
            name: milestone.name.trim(),
            deadline: Value(milestone.deadline?.toUtc()),
            completedAt: Value(milestone.completedAt?.toUtc()),
            createdAt: milestone.createdAt.toUtc(),
            occurredAt: milestone.updatedAt.toUtc(),
          ),
        );
  });

  Future<Milestone?> getMilestone(String id) async {
    final row =
        await (_db.select(_db.milestones)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .getSingleOrNull();
    return row == null ? null : _milestoneFromRow(row);
  }

  Stream<List<Milestone>> watchMilestones(String projectId) {
    return (_db.select(_db.milestones)
          ..where(
            (row) => row.projectId.equals(projectId) & row.deletedAt.isNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.createdAt),
            (row) => OrderingTerm.asc(row.name),
          ]))
        .watch()
        .map((rows) => rows.map(_milestoneFromRow).toList(growable: false));
  }

  domain.Project _projectFromRow(ProjectRow row) => domain.Project(
    id: row.id,
    name: row.name,
    objective: row.objective,
    deadline: row.deadline?.toUtc(),
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );

  Milestone _milestoneFromRow(MilestoneRow row) => Milestone(
    id: row.id,
    projectId: row.projectId,
    name: row.name,
    deadline: row.deadline?.toUtc(),
    completedAt: row.completedAt?.toUtc(),
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
  );

  void _requireNonempty(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
  }

  Future<List<domain.Project>> search(String query, {int limit = 20}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const [];
    }

    final pattern = '%$normalized%';
    final statement = _db.select(_db.projects)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            (row.name.like(pattern) | row.objective.like(pattern)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.name)])
      ..limit(limit);

    final rows = await statement.get();
    return rows.map(_projectFromRow).toList(growable: false);
  }

  Stream<List<domain.Project>> watchAll() {
    final query = _db.select(_db.projects)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm.asc(row.name)]);
    return query.watch().map(
      (rows) => rows.map(_projectFromRow).toList(growable: false),
    );
  }
}
