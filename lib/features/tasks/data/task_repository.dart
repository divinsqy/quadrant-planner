import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_status.dart';
import '../../../domain/tasks/workload.dart';

class TaskDraft {
  final String title;
  final String description;
  final TaskStatus status;
  final String? projectId;
  final int importance;
  final int baseUrgency;
  final DateTime? deadline;
  final int? estimatedMinutes;
  final Workload workload;
  final int progress;
  final bool includeInWeeklyReport;

  const TaskDraft({
    required this.title,
    this.description = '',
    this.status = TaskStatus.inbox,
    this.projectId,
    this.importance = 50,
    this.baseUrgency = 50,
    this.deadline,
    this.estimatedMinutes,
    this.workload = Workload.medium,
    this.progress = 0,
    this.includeInWeeklyReport = true,
  });
}

class TaskRepository {
  final AppDatabase _db;
  final String Function() _idFactory;
  final DateTime Function() _clock;

  TaskRepository(
    this._db, {
    String Function()? idFactory,
    DateTime Function()? clock,
  })  : _idFactory = idFactory ?? (() => const Uuid().v4()),
        _clock = clock ?? (() => DateTime.now().toUtc());

  Future<Task> createTask(TaskDraft draft) async {
    final now = _clock().toUtc();
    final task = Task.create(
      id: _idFactory(),
      title: draft.title,
      description: draft.description,
      status: draft.status,
      projectId: draft.projectId,
      importance: draft.importance,
      baseUrgency: draft.baseUrgency,
      baseUrgencyAnchorAt: now,
      deadline: draft.deadline,
      estimatedMinutes: draft.estimatedMinutes,
      workload: draft.workload,
      progress: draft.progress,
      includeInWeeklyReport: draft.includeInWeeklyReport,
      createdAt: now,
      updatedAt: now,
    );
    await save(task);
    return task;
  }

  Future<void> save(Task task) async {
    await _db.into(_db.tasks).insertOnConflictUpdate(
          TasksCompanion(
            id: Value(task.id),
            title: Value(task.title),
            description: Value(task.description),
            status: Value(task.status.name),
            projectId: Value(task.projectId),
            importance: Value(task.importance),
            baseUrgency: Value(task.baseUrgency),
            baseUrgencyAnchorAt: Value(task.baseUrgencyAnchorAt),
            deadline: Value(task.deadline),
            estimatedMinutes: Value(task.estimatedMinutes),
            workload: Value(task.workload.name),
            progress: Value(task.progress),
            includeInWeeklyReport: Value(task.includeInWeeklyReport),
            createdAt: Value(task.createdAt),
            updatedAt: Value(task.updatedAt),
            completedAt: Value(task.completedAt),
            deletedAt: Value(task.deletedAt),
          ),
        );
  }

  Stream<Task?> watchTask(String id) {
    final query = _db.select(_db.tasks)..where((row) => row.id.equals(id));
    return query.watchSingleOrNull().map(
          (row) => row == null ? null : _fromRow(row),
        );
  }

  Stream<List<Task>> watchExecutableTasks() {
    final query = _db.select(_db.tasks)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.status.isIn([
              TaskStatus.planned.name,
              TaskStatus.inProgress.name,
            ]),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return query.watch().map(
          (rows) => rows.map(_fromRow).toList(growable: false),
        );
  }

  Future<void> softDelete(String id, DateTime at) async {
    final deletedAt = at.toUtc();
    await (_db.update(_db.tasks)..where((row) => row.id.equals(id))).write(
      TasksCompanion(
        deletedAt: Value(deletedAt),
        updatedAt: Value(deletedAt),
      ),
    );
  }

  Task _fromRow(TaskRow row) {
    return Task.create(
      id: row.id,
      title: row.title,
      description: row.description,
      status: TaskStatus.values.byName(row.status),
      projectId: row.projectId,
      importance: row.importance,
      baseUrgency: row.baseUrgency,
      baseUrgencyAnchorAt: row.baseUrgencyAnchorAt,
      deadline: row.deadline,
      estimatedMinutes: row.estimatedMinutes,
      workload: Workload.values.byName(row.workload),
      progress: row.progress,
      includeInWeeklyReport: row.includeInWeeklyReport,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      completedAt: row.completedAt,
      deletedAt: row.deletedAt,
    );
  }
}
