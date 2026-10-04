import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/user_data_schema.dart';
import 'field_merge.dart';
import 'outbox_repository.dart';

enum ConflictChoice { local, remote, merged }

class ConflictRepository {
  final AppDatabase db;
  final OutboxRepository outbox;
  ConflictRepository(this.db) : outbox = OutboxRepository(db);
  Future<List<SyncConflictRow>> unresolved() =>
      (db.select(db.syncConflicts)
            ..where((r) => r.resolvedAt.isNull())
            ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
          .get();
  Stream<List<SyncConflictRow>> watch() async* {
    final schema = await UserDataSchema.load(db);
    yield* db
        .customSelect(
          'SELECT * FROM sync_conflicts WHERE resolved_at IS NULL ORDER BY created_at',
          readsFrom: {...schema.readsFrom, db.syncConflicts},
        )
        .watch()
        .map(
          (rows) => rows.map((row) => db.syncConflicts.map(row.data)).toList(),
        );
  }

  Future<void> record(
    String kind,
    String entityId,
    FieldConflict conflict,
  ) async {
    final existing =
        await (db.select(db.syncConflicts)..where(
              (r) =>
                  r.entityKind.equals(kind) &
                  r.entityId.equals(entityId) &
                  r.field.equals(conflict.field) &
                  r.resolvedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) {
      await (db.update(
        db.syncConflicts,
      )..where((r) => r.id.equals(existing.id))).write(
        SyncConflictsCompanion(
          remoteJson: Value(encodedValue(conflict.remote)),
        ),
      );
      return;
    }
    await db
        .into(db.syncConflicts)
        .insert(
          SyncConflictsCompanion.insert(
            id: const Uuid().v4(),
            entityKind: kind,
            entityId: entityId,
            field: conflict.field,
            baseJson: Value(encodedValue(conflict.base)),
            localJson: encodedValue(conflict.local),
            remoteJson: encodedValue(conflict.remote),
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> resolve(
    String id,
    ConflictChoice choice, {
    String? mergedText,
  }) => db.transaction(() async {
    final conflict = await (db.select(
      db.syncConflicts,
    )..where((r) => r.id.equals(id) & r.resolvedAt.isNull())).getSingle();
    final schema = await UserDataSchema.load(db);
    final current = await schema.read(conflict.entityKind, conflict.entityId);
    final chosen = jsonDecode(
      choice == ConflictChoice.remote
          ? conflict.remoteJson
          : conflict.localJson,
    );
    var payload = Map<String, Object?>.of(current ?? {});
    var restore = false;
    if (conflict.field == '_deletion') {
      if (choice == ConflictChoice.merged) {
        throw ArgumentError('Deletion requires an explicit side');
      }
      payload = Map<String, Object?>.from(chosen as Map);
      restore = !isDeleted(payload);
    } else if (conflict.field == '_invariant') {
      if (choice == ConflictChoice.merged) {
        throw ArgumentError('Choose a complete valid version');
      }
      payload = choice == ConflictChoice.local
          ? current ??
                {
                  ...Map<String, Object?>.from(
                    jsonDecode(conflict.remoteJson) as Map,
                  ),
                  '_deleted': 1,
                }
          : Map<String, Object?>.from(chosen as Map);
    } else {
      if (choice == ConflictChoice.merged &&
          (mergedText == null || chosen is! String)) {
        throw ArgumentError('Text conflict required');
      }
      payload[conflict.field] = choice == ConflictChoice.merged
          ? mergedText
          : choice == ConflictChoice.local && current != null
          ? current[conflict.field]
          : chosen;
    }
    await outbox.withoutCapture(() async {
      if (restore) {
        await db.customStatement(
          'DELETE FROM sync_tombstones WHERE entity_kind=? AND entity_id=?',
          [conflict.entityKind, conflict.entityId],
        );
        await db.customStatement(
          'INSERT OR IGNORE INTO sync_restore_intents(entity_kind,entity_id) VALUES(?,?)',
          [conflict.entityKind, conflict.entityId],
        );
      }
      await schema.write(conflict.entityKind, payload);
    }, restoring: restore);
    await (db.update(db.syncConflicts)..where((r) => r.id.equals(id))).write(
      SyncConflictsCompanion(resolvedAt: Value(DateTime.now().toUtc())),
    );
    if (!(await unresolved()).any(
      (c) =>
          c.entityKind == conflict.entityKind &&
          c.entityId == conflict.entityId,
    )) {
      await outbox.supersede(conflict.entityKind, conflict.entityId);
      await outbox.enqueue(
        conflict.entityKind,
        conflict.entityId,
        payload,
        explicitRestore:
            (await db
                .customSelect(
                  'SELECT 1 AS present FROM sync_restore_intents WHERE entity_kind=? AND entity_id=?',
                  variables: [
                    Variable(conflict.entityKind),
                    Variable(conflict.entityId),
                  ],
                )
                .getSingleOrNull()) !=
            null,
      );
    }
  });
}
