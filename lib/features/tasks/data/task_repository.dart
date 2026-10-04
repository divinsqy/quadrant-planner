import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_status.dart';
import '../../../domain/tasks/workload.dart';
import 'task_activity_repository.dart';
import 'task_relations_repository.dart';

class TaskDraft {
  final String title;
  final String description;
  final TaskStatus status;
  final String? projectId;
  final String? milestoneId;
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
    this.milestoneId,
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
  late final TaskRelationsRepository relations = TaskRelationsRepository(_db);

  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

  TaskRepository(
    this._db, {
    String Function()? idFactory,
    DateTime Function()? clock,
  }) : _idFactory = idFactory ?? (() => const Uuid().v4()),
       _clock = clock ?? (() => DateTime.now().toUtc());

  Future<Task> createTask(TaskDraft draft) async {
    final now = _clock().toUtc();
    final task = Task.create(
      id: _idFactory(),
      title: draft.title,
      description: draft.description,
      status: draft.status,
      projectId: draft.projectId,
      milestoneId: draft.milestoneId,
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
    await transaction(() async {
      await save(task);
      await TaskActivityRepository(_db).add(
        taskId: task.id,
        type: 'created',
        occurredAt: now,
        payload: {'title': task.title, 'status': task.status.name},
      );
    });
    return task;
  }

  Future<void> save(Task task) async {
    if (task.milestoneId != null) {
      final milestone =
          await (_db.select(_db.milestones)..where(
                (row) =>
                    row.id.equals(task.milestoneId!) & row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (milestone == null || milestone.projectId != task.projectId) {
        throw ArgumentError('里程碑必须属于任务所选项目');
      }
    }
    await _db
        .into(_db.tasks)
        .insertOnConflictUpdate(
          TasksCompanion(
            id: Value(task.id),
            title: Value(task.title),
            description: Value(task.description),
            status: Value(task.status.name),
            projectId: Value(task.projectId),
            milestoneId: Value(task.milestoneId),
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

  Future<Task?> get(String id) async {
    final query = _db.select(_db.tasks)..where((row) => row.id.equals(id));
    final row = await query.getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Stream<Task?> watchTask(String id) {
    final query = _db.select(_db.tasks)..where((row) => row.id.equals(id));
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : _fromRow(row),
    );
  }

  Stream<List<Task>> watchTasks({
    Set<TaskStatus>? statuses,
    String? projectId,
    String? tagId,
    String query = '',
  }) {
    final statement = _db.select(_db.tasks)
      ..where((row) {
        var expression = row.deletedAt.isNull();
        if (statuses != null && statuses.isNotEmpty) {
          expression =
              expression &
              row.status.isIn(
                statuses.map((status) => status.name).toList(growable: false),
              );
        }
        if (projectId != null) {
          expression = expression & row.projectId.equals(projectId);
        }
        if (tagId != null) {
          final taggedIds = _db.selectOnly(_db.taskTags)
            ..addColumns([_db.taskTags.taskId])
            ..where(_db.taskTags.tagId.equals(tagId));
          expression = expression & row.id.isInQuery(taggedIds);
        }
        final search = query.trim();
        if (search.isNotEmpty) {
          expression =
              expression &
              (row.title.like('%$search%') | row.description.like('%$search%'));
        }
        return expression;
      })
      ..orderBy([
        (row) => OrderingTerm.desc(row.updatedAt),
        (row) => OrderingTerm.desc(row.id),
      ]);
    return statement.watch().map(
      (rows) => rows.map(_fromRow).toList(growable: false),
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

  Future<List<Task>> getTasks({bool includeDeleted = false}) async {
    final rows =
        await (_db.select(_db.tasks)..where(
              (t) =>
                  includeDeleted ? const Constant(true) : t.deletedAt.isNull(),
            ))
            .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<Task>> search(String query, {int limit = 20}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const [];
    }

    final pattern = '%$normalized%';
    final statement = _db.select(_db.tasks)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            (row.title.like(pattern) | row.description.like(pattern)),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
      ..limit(limit);

    final rows = await statement.get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> softDelete(String id, DateTime at) async {
    final deletedAt = at.toUtc();
    await (_db.update(_db.tasks)..where((row) => row.id.equals(id))).write(
      TasksCompanion(deletedAt: Value(deletedAt), updatedAt: Value(deletedAt)),
    );
  }

  Task _fromRow(TaskRow row) {
    return Task.create(
      id: row.id,
      title: row.title,
      description: row.description,
      status: TaskStatus.values.byName(row.status),
      projectId: row.projectId,
      milestoneId: row.milestoneId,
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
