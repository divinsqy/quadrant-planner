import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/user_data_schema.dart';
import 'sync_operation.dart';
import 'field_merge.dart';

class OutboxRepository {
  final AppDatabase db;
  OutboxRepository(this.db);
  Future<bool> get enabled async =>
      (await db
              .customSelect('SELECT enabled FROM sync_profile WHERE id=1')
              .getSingle())
          .read<int>('enabled') ==
      1;
  Future<String?> get boundUser async =>
      (await db
              .customSelect('SELECT user_id FROM sync_profile WHERE id=1')
              .getSingle())
          .readNullable<String>('user_id');
  Future<void> activate(String userId) => db.transaction(() async {
    final bound = await boundUser;
    if (bound != null && bound != userId) {
      throw StateError('Workspace belongs to another account');
    }
    await db.customStatement(
      'UPDATE sync_profile SET user_id=?, enabled=1 WHERE id=1',
      [userId],
    );
    {
      final schema = await UserDataSchema.load(db);
      for (final table in schema.tables) {
        for (final row
            in await db
                .customSelect(
                  'SELECT ${table.columns.join(',')} FROM ${table.name}',
                )
                .get()) {
          final id = table.idOf(row.data);
          final shadow = await db
              .customSelect(
                'SELECT payload_json FROM sync_shadow WHERE entity_kind=? AND entity_id=?',
                variables: [Variable(table.name), Variable(id)],
              )
              .getSingleOrNull();
          if (shadow != null &&
              sameValue(
                jsonDecode(shadow.read<String>('payload_json')),
                row.data,
              )) {
            continue;
          }
          if ((await (db.select(db.syncConflicts)..where(
                    (c) =>
                        c.entityKind.equals(table.name) &
                        c.entityId.equals(id) &
                        c.resolvedAt.isNull(),
                  ))
                  .get())
              .isNotEmpty) {
            continue;
          }
          if ((await pending()).any(
            (op) =>
                op.entityKind == table.name &&
                op.entityId == id &&
                sameValue(op.payload, row.data),
          )) {
            continue;
          }
          final restore = await db
              .customSelect(
                'SELECT 1 AS present FROM sync_restore_intents WHERE entity_kind=? AND entity_id=?',
                variables: [Variable(table.name), Variable(id)],
              )
              .getSingleOrNull();
          await enqueue(
            table.name,
            id,
            row.data,
            explicitRestore: restore != null,
          );
        }
      }
      for (final row
          in await db
              .customSelect(
                'SELECT t.*,s.payload_json FROM sync_tombstones t JOIN sync_shadow s USING(entity_kind,entity_id)',
              )
              .get()) {
        final kind = row.read<String>('entity_kind'),
            id = row.read<String>('entity_id');
        if (await schema.read(kind, id) != null) continue;
        final payload = Map<String, Object?>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );
        if (isDeleted(payload)) continue;
        if (schema.table(kind).columns.contains('deleted_at')) {
          payload['deleted_at'] = row.read<int>('deleted_at');
        } else {
          payload['_deleted'] = 1;
        }
        if (!(await pending()).any(
          (op) =>
              op.entityKind == kind &&
              op.entityId == id &&
              isDeleted(op.payload),
        )) {
          await enqueue(kind, id, payload);
        }
      }
    }
  });
  Future<void> disable() =>
      db.customStatement('UPDATE sync_profile SET enabled=0 WHERE id=1');
  Future<List<SyncOperation>> pending() async =>
      (await db
              .customSelect(
                "SELECT o.*,m.base_json,m.explicit_restore FROM sync_outbox o JOIN sync_operation_meta m USING(operation_id) WHERE status IN ('pending','failed','sending') ORDER BY o.rowid",
              )
              .get())
          .map((row) => SyncOperation.fromRow(row.data))
          .toList();
  Future<T> withoutCapture<T>(
    Future<T> Function() action, {
    bool restoring = false,
  }) => db.transaction(() async {
    final row = await db
        .customSelect(
          'SELECT suppressed,restoring FROM sync_profile WHERE id=1',
        )
        .getSingle();
    await db.customStatement(
      'UPDATE sync_profile SET suppressed=1,restoring=? WHERE id=1',
      [restoring ? 1 : 0],
    );
    try {
      return await action();
    } finally {
      await db.customStatement(
        'UPDATE sync_profile SET suppressed=?,restoring=? WHERE id=1',
        [row.read<int>('suppressed'), row.read<int>('restoring')],
      );
    }
  });
  Future<void> enqueue(
    String kind,
    String id,
    Map<String, Object?> payload, {
    String? operationId,
    bool explicitRestore = false,
  }) => db.transaction(() async {
    if (!await enabled) return;
    final shadow = await db
        .customSelect(
          'SELECT * FROM sync_shadow WHERE entity_kind=? AND entity_id=?',
          variables: [Variable(kind), Variable(id)],
        )
        .getSingleOrNull();
    final base = shadow == null
        ? <String, Object?>{}
        : Map<String, Object?>.from(
            jsonDecode(shadow.read<String>('payload_json')) as Map,
          );
    final opId = operationId ?? const Uuid().v4();
    await db.customStatement(
      'INSERT OR IGNORE INTO sync_outbox(operation_id,entity_kind,entity_id,base_revision,changed_fields_json,payload_json,created_at) VALUES(?,?,?,?,?,?,?)',
      [
        opId,
        kind,
        id,
        shadow?.read<int>('revision') ?? 0,
        jsonEncode(
          payload.keys
              .where((key) => jsonEncode(base[key]) != jsonEncode(payload[key]))
              .toList(),
        ),
        jsonEncode(payload),
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ],
    );
    await db.customStatement(
      'INSERT OR IGNORE INTO sync_operation_meta(operation_id,base_json,explicit_restore) VALUES(?,?,?)',
      [opId, jsonEncode(base), explicitRestore ? 1 : 0],
    );
  });
  Future<SyncOperation> beginAttempt(String id) => db.transaction(() async {
    await db.customStatement(
      'UPDATE sync_operation_meta SET attempts=attempts+1 WHERE operation_id=?',
      [id],
    );
    await (db.update(
      db.syncOutbox,
    )..where((row) => row.operationId.equals(id))).write(
      const SyncOutboxCompanion(status: Value('sending'), error: Value(null)),
    );
    return (await pending()).firstWhere((op) => op.operationId == id);
  });
  Future<void> markApplied(String id) =>
      (db.update(
        db.syncOutbox,
      )..where((row) => row.operationId.equals(id))).write(
        const SyncOutboxCompanion(status: Value('applied'), error: Value(null)),
      );
  // Persist a fixed diagnostic code, never raw HTTP bodies or exception text.
  Future<void> markFailed(String id, String error) =>
      (db.update(
        db.syncOutbox,
      )..where((row) => row.operationId.equals(id))).write(
        const SyncOutboxCompanion(
          status: Value('failed'),
          error: Value('network'),
        ),
      );
  Future<void> supersede(String kind, String id) => db.customUpdate(
    "UPDATE sync_outbox SET status='superseded' WHERE entity_kind=? AND entity_id=? AND status IN ('pending','failed','sending')",
    variables: [Variable(kind), Variable(id)],
    updates: {db.syncOutbox},
  );
}
