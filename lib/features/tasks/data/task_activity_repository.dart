import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/tasks/task_activity_event.dart';

class TaskActivityRepository {
  final AppDatabase _db;
  final String Function() _idFactory;

  TaskActivityRepository(
    this._db, {
    String Function()? idFactory,
  }) : _idFactory = idFactory ?? (() => const Uuid().v4());

  Future<TaskActivityEvent> add({
    required String taskId,
    required String type,
    required DateTime occurredAt,
    Map<String, dynamic> payload = const {},
  }) async {
    final event = TaskActivityEvent(
      id: _idFactory(),
      taskId: taskId,
      type: type,
      occurredAt: occurredAt.toUtc(),
      payload: Map.unmodifiable(payload),
    );

    await _db.into(_db.activityEvents).insert(
          ActivityEventsCompanion(
            id: Value(event.id),
            taskId: Value(event.taskId),
            type: Value(event.type),
            occurredAt: Value(event.occurredAt),
            payloadJson: Value(jsonEncode(event.payload)),
          ),
        );
    return event;
  }

  Future<List<TaskActivityEvent>> fetchPage(
    String taskId, {
    int limit = 50,
    DateTime? before,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }

    final query = _db.select(_db.activityEvents)
      ..where((row) {
        var expression = row.taskId.equals(taskId);
        if (before != null) {
          expression = expression & row.occurredAt.isSmallerThanValue(before.toUtc());
        }
        return expression;
      })
      ..orderBy([
        (row) => OrderingTerm.desc(row.occurredAt),
        (row) => OrderingTerm.desc(row.id),
      ])
      ..limit(limit);

    final rows = await query.get();
    return rows.map(_fromRow).toList(growable: false);
  }

  TaskActivityEvent _fromRow(ActivityEventRow row) {
    final decoded = jsonDecode(row.payloadJson);
    return TaskActivityEvent(
      id: row.id,
      taskId: row.taskId,
      type: row.type,
      occurredAt: row.occurredAt.toUtc(),
      payload: decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{},
    );
  }
}
