import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/user_data_schema.dart';
import '../../../core/sync/field_merge.dart';
import '../../../core/sync/outbox_repository.dart';

class TrashItem {
  final String kind, id, title;
  final DateTime deletedAt;
  const TrashItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.deletedAt,
  });
}

class TrashRepository {
  final AppDatabase db;
  final DateTime Function() clock;
  late final outbox = OutboxRepository(db);
  TrashRepository(this.db, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  Future<List<TrashItem>> list() async {
    final result = <TrashItem>[];
    final schema = await UserDataSchema.load(db);
    for (final spec in schema.tables.where(
      (table) => table.columns.contains('deleted_at'),
    )) {
      for (final row
          in await db
              .customSelect(
                'SELECT * FROM ${spec.name} WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC',
              )
              .get()) {
        result.add(
          TrashItem(
            kind: spec.name,
            id: spec.idOf(row.data),
            title:
                (row.data['title'] ?? row.data['name'] ?? spec.idOf(row.data))
                    as String,
            deletedAt: DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('deleted_at') * 1000,
              isUtc: true,
            ),
          ),
        );
      }
    }
    return result;
  }

  Future<void> restore(String kind, String id) => db.transaction(() async {
    final schema = await UserDataSchema.load(db);
    final spec = schema.table(kind);
    if (!spec.columns.contains('deleted_at')) {
      throw ArgumentError('Not a trash entity');
    }
    final payload = await schema.read(kind, id);
    if (payload == null) throw StateError('Entity was purged');
    payload['deleted_at'] = null;
    if (payload.containsKey('updated_at')) {
      payload['updated_at'] = clock().millisecondsSinceEpoch ~/ 1000;
    }
    await outbox.withoutCapture(() async {
      await db.customStatement(
        'DELETE FROM sync_tombstones WHERE entity_kind=? AND entity_id=?',
        [kind, id],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO sync_restore_intents(entity_kind,entity_id) VALUES(?,?)',
        [kind, id],
      );
      await schema.write(kind, payload);
    }, restoring: true);
    await outbox.supersede(kind, id);
    await outbox.enqueue(kind, id, payload, explicitRestore: true);
  });
  Future<int> purgeEligible() => db.transaction(() async {
    final schema = await UserDataSchema.load(db);
    var count = 0;
    for (final item in await list()) {
      if (clock().toUtc().difference(item.deletedAt) <=
          const Duration(days: 30)) {
        continue;
      }
      // Parent cascade must not destroy another entity's unresolved work.
      if ((await db.select(db.syncConflicts).get()).any(
        (c) => c.resolvedAt == null,
      )) {
        continue;
      }
      if ((await outbox.pending()).isNotEmpty) continue;
      final shadow = await db
          .customSelect(
            'SELECT payload_json FROM sync_shadow WHERE entity_kind=? AND entity_id=?',
            variables: [Variable(item.kind), Variable(item.id)],
          )
          .getSingleOrNull();
      if (await outbox.boundUser != null &&
          (shadow == null ||
              !isDeleted(
                Map<String, Object?>.from(
                  jsonDecode(shadow.read<String>('payload_json')) as Map,
                ),
              ))) {
        continue;
      }
      await db.customStatement(
        'INSERT INTO sync_tombstones(entity_kind,entity_id,deleted_at) VALUES(?,?,?) ON CONFLICT(entity_kind,entity_id) DO NOTHING',
        [item.kind, item.id, item.deletedAt.millisecondsSinceEpoch ~/ 1000],
      );
      await outbox.withoutCapture(
        () => db.customUpdate(
          'DELETE FROM ${item.kind} WHERE ${schema.table(item.kind).whereKey}',
          variables: schema
              .table(item.kind)
              .keyValues(item.id)
              .map((v) => Variable(v))
              .toList(),
          updates: schema.readsFrom,
        ),
      );
      count++;
    }
    return count;
  });
}
