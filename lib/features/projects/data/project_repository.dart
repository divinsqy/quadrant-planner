import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/projects/project.dart' as domain;

class ProjectRepository {
  final AppDatabase _db;

  ProjectRepository(this._db);

  Future<void> save(domain.Project project) async {
    await _db.into(_db.projects).insertOnConflictUpdate(
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

  Stream<List<domain.Project>> watchAll() {
    final query = _db.select(_db.projects)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm.asc(row.name)]);
    return query.watch().map(
          (rows) => rows
              .map(
                (row) => domain.Project(
                  id: row.id,
                  name: row.name,
                  objective: row.objective,
                  deadline: row.deadline,
                  createdAt: row.createdAt,
                  updatedAt: row.updatedAt,
                  deletedAt: row.deletedAt,
                ),
              )
              .toList(growable: false),
        );
  }
}
