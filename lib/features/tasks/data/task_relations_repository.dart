import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/tasks/subtask.dart';
import '../../../domain/tasks/task_dependency.dart';
import '../../../domain/tasks/task_status.dart';
import 'task_activity_repository.dart';

class TaskDependencyState {
  final TaskDependency dependency;
  final String title;
  final bool satisfied;
  final bool prerequisiteDeleted;

  const TaskDependencyState({
    required this.dependency,
    required this.title,
    required this.satisfied,
    this.prerequisiteDeleted = false,
  });

  String? get blockingReason => satisfied
      ? null
      : prerequisiteDeleted
      ? '前置任务已删除且未完成：$title，请移除依赖或恢复任务'
      : '等待前置任务完成：$title';
}

class TaskRelationsRepository {
  final AppDatabase _db;
  final String Function() _idFactory;
  final DateTime Function() _clock;

  TaskRelationsRepository(
    this._db, {
    String Function()? idFactory,
    DateTime Function()? clock,
  }) : _idFactory = idFactory ?? (() => const Uuid().v4()),
       _clock = clock ?? (() => DateTime.now().toUtc());

  Stream<List<Subtask>> watchSubtasks(String taskId) {
    final query = _db.select(_db.subtasks)
      ..where((row) => row.taskId.equals(taskId) & row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.asc(row.position),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query.watch().map(
      (rows) => rows.map(_subtask).toList(growable: false),
    );
  }

  Future<Subtask> addSubtask(String taskId, String title) =>
      _db.transaction(() async {
        final cleaned = _title(title);
        await _requireTask(taskId);
        final existing = await (_db.select(
          _db.subtasks,
        )..where((row) => row.taskId.equals(taskId))).get();
        final position =
            existing.fold<int>(
              -1,
              (max, row) => row.position > max ? row.position : max,
            ) +
            1;
        final now = _clock().toUtc();
        final id = _idFactory();
        await _db
            .into(_db.subtasks)
            .insert(
              SubtasksCompanion.insert(
                id: id,
                taskId: taskId,
                title: cleaned,
                position: Value(position),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _event(taskId, 'subtask_added', {
          'subtaskId': id,
          'title': cleaned,
        });
        return Subtask(
          id: id,
          taskId: taskId,
          title: cleaned,
          completed: false,
          position: position,
          createdAt: now,
          updatedAt: now,
        );
      });

  Future<void> updateSubtask(String id, {String? title, bool? completed}) =>
      _db.transaction(() async {
        final row =
            await (_db.select(_db.subtasks)
                  ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
                .getSingleOrNull();
        if (row == null) throw ArgumentError('子任务不存在');
        final cleaned = title == null ? row.title : _title(title);
        await (_db.update(
          _db.subtasks,
        )..where((row) => row.id.equals(id))).write(
          SubtasksCompanion(
            title: Value(cleaned),
            completed: Value(completed ?? row.completed),
            updatedAt: Value(_clock().toUtc()),
          ),
        );
        await _event(row.taskId, 'subtask_updated', {
          'subtaskId': id,
          'title': cleaned,
          'completed': completed ?? row.completed,
        });
      });

  Future<void> deleteSubtask(String id) => _db.transaction(() async {
    final row =
        await (_db.select(_db.subtasks)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null) throw ArgumentError('子任务不存在');
    final now = _clock().toUtc();
    await (_db.update(_db.subtasks)..where((row) => row.id.equals(id))).write(
      SubtasksCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await _event(row.taskId, 'subtask_deleted', {
      'subtaskId': id,
      'title': row.title,
    });
  });

  Stream<List<TaskDependencyState>> watchDependencies(String taskId) {
    final query = _db.select(_db.dependencies).join([
      innerJoin(
        _db.tasks,
        _db.tasks.id.equalsExp(_db.dependencies.dependsOnTaskId),
      ),
    ])..where(_db.dependencies.taskId.equals(taskId));
    query.orderBy([
      OrderingTerm.asc(_db.dependencies.createdAt),
      OrderingTerm.asc(_db.dependencies.id),
    ]);
    return query.watch().map(
      (rows) => rows
          .map((row) {
            final dependency = row.readTable(_db.dependencies);
            final task = row.readTable(_db.tasks);
            return TaskDependencyState(
              dependency: _dependency(dependency),
              title: task.title,
              satisfied: task.status == TaskStatus.completed.name,
              prerequisiteDeleted: task.deletedAt != null,
            );
          })
          .toList(growable: false),
    );
  }

  Stream<Set<String>> watchBlockedTaskIds() {
    final prerequisite = _db.alias(_db.tasks, 'prerequisite');
    final dependent = _db.alias(_db.tasks, 'dependent');
    final query =
        _db.select(_db.dependencies).join([
          innerJoin(
            prerequisite,
            prerequisite.id.equalsExp(_db.dependencies.dependsOnTaskId),
          ),
          innerJoin(dependent, dependent.id.equalsExp(_db.dependencies.taskId)),
        ])..where(
          prerequisite.status.equals(TaskStatus.completed.name).not() &
              dependent.deletedAt.isNull(),
        );
    return query.watch().map(
      (rows) => Set.unmodifiable(
        rows.map((row) => row.readTable(_db.dependencies).taskId),
      ),
    );
  }

  Future<Set<String>> blockedTaskIds() async {
    final prerequisite = _db.alias(_db.tasks, 'prerequisite');
    final query = _db.select(_db.dependencies).join([
      innerJoin(
        prerequisite,
        prerequisite.id.equalsExp(_db.dependencies.dependsOnTaskId),
      ),
    ])..where(prerequisite.status.equals(TaskStatus.completed.name).not());
    return (await query.get())
        .map((row) => row.readTable(_db.dependencies).taskId)
        .toSet();
  }

  Future<TaskDependency> addDependency(String taskId, String prerequisiteId) =>
      _db.transaction(() async {
        if (taskId == prerequisiteId) throw ArgumentError('任务不能依赖自身');
        await _requireTask(taskId);
        await _requireTask(prerequisiteId);
        final all = await _db.select(_db.dependencies).get();
        if (all.any(
          (row) =>
              row.taskId == taskId && row.dependsOnTaskId == prerequisiteId,
        )) {
          throw ArgumentError('依赖关系已存在');
        }
        final edges = <String, List<String>>{};
        for (final row in all) {
          (edges[row.taskId] ??= []).add(row.dependsOnTaskId);
        }
        final pending = [prerequisiteId];
        final seen = <String>{};
        while (pending.isNotEmpty) {
          final id = pending.removeLast();
          if (id == taskId) throw ArgumentError('依赖关系会形成循环');
          if (seen.add(id)) pending.addAll(edges[id] ?? const []);
        }
        final dependency = TaskDependency(
          id: _idFactory(),
          taskId: taskId,
          dependsOnTaskId: prerequisiteId,
          createdAt: _clock().toUtc(),
        );
        await _db
            .into(_db.dependencies)
            .insert(
              DependenciesCompanion.insert(
                id: dependency.id,
                taskId: taskId,
                dependsOnTaskId: prerequisiteId,
                createdAt: dependency.createdAt,
              ),
            );
        await _event(taskId, 'dependency_added', {
          'dependsOnTaskId': prerequisiteId,
        });
        return dependency;
      });

  Future<void> removeDependency(String id) => _db.transaction(() async {
    final row = await (_db.select(
      _db.dependencies,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (row == null) throw ArgumentError('依赖关系不存在');
    await (_db.delete(
      _db.dependencies,
    )..where((row) => row.id.equals(id))).go();
    await _event(row.taskId, 'dependency_removed', {
      'dependsOnTaskId': row.dependsOnTaskId,
    });
  });

  Future<void> _requireTask(String id) async {
    final row =
        await (_db.select(_db.tasks)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null) throw ArgumentError('任务不存在');
  }

  String _title(String title) {
    final cleaned = title.trim();
    if (cleaned.isEmpty) throw ArgumentError('子任务标题不能为空');
    return cleaned;
  }

  Future<void> _event(
    String taskId,
    String type,
    Map<String, dynamic> payload,
  ) async {
    await TaskActivityRepository(_db).add(
      taskId: taskId,
      type: type,
      occurredAt: _clock().toUtc(),
      payload: payload,
    );
  }

  Subtask _subtask(SubtaskRow row) => Subtask(
    id: row.id,
    taskId: row.taskId,
    title: row.title,
    completed: row.completed,
    position: row.position,
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
  );
  TaskDependency _dependency(DependencyRow row) => TaskDependency(
    id: row.id,
    taskId: row.taskId,
    dependsOnTaskId: row.dependsOnTaskId,
    createdAt: row.createdAt.toUtc(),
  );
}
