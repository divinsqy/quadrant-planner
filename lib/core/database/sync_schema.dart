import 'package:drift/drift.dart';

import 'app_database.dart';
import 'user_data_schema.dart';

/// Triggers participate in the caller's SQLite transaction, including implicit
/// single-statement transactions. No network or secure-storage call is involved.
Future<void> installSyncSchema(AppDatabase db) async {
  for (final sql in [
    'CREATE UNIQUE INDEX IF NOT EXISTS milestone_history_sync_id ON milestone_history(sync_id)',
    '''CREATE TABLE IF NOT EXISTS sync_profile (id INTEGER PRIMARY KEY CHECK(id=1), user_id TEXT, enabled INTEGER NOT NULL DEFAULT 0, suppressed INTEGER NOT NULL DEFAULT 0, restoring INTEGER NOT NULL DEFAULT 0)''',
    'INSERT OR IGNORE INTO sync_profile(id) VALUES(1)',
    '''CREATE TABLE IF NOT EXISTS sync_shadow (entity_kind TEXT NOT NULL, entity_id TEXT NOT NULL, revision INTEGER NOT NULL, payload_json TEXT NOT NULL, pending_apply INTEGER NOT NULL DEFAULT 0, apply_json TEXT, PRIMARY KEY(entity_kind,entity_id))''',
    '''CREATE TABLE IF NOT EXISTS sync_operation_meta (operation_id TEXT PRIMARY KEY REFERENCES sync_outbox(operation_id) ON DELETE CASCADE, base_json TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, explicit_restore INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE IF NOT EXISTS sync_tombstones (entity_kind TEXT NOT NULL, entity_id TEXT NOT NULL, deleted_at INTEGER NOT NULL, PRIMARY KEY(entity_kind,entity_id))''',
    '''CREATE TABLE IF NOT EXISTS sync_restore_intents (entity_kind TEXT NOT NULL,entity_id TEXT NOT NULL,PRIMARY KEY(entity_kind,entity_id))''',
  ]) {
    await db.customStatement(sql);
  }
  final schema = await UserDataSchema.load(db);
  final shadowColumns = await db
      .customSelect('PRAGMA table_info(sync_shadow)')
      .get();
  if (!shadowColumns.any(
    (row) => row.read<String>('name') == 'apply_before_json',
  )) {
    await db.customStatement(
      'ALTER TABLE sync_shadow ADD COLUMN apply_before_json TEXT',
    );
    for (final row
        in await db
            .customSelect('SELECT * FROM sync_shadow WHERE pending_apply=1')
            .get()) {
      final frozen = await db
          .customSelect(
            'SELECT payload_json FROM sync_outbox WHERE entity_kind=? AND entity_id=? AND base_revision<? ORDER BY rowid DESC LIMIT 1',
            variables: [
              Variable(row.read<String>('entity_kind')),
              Variable(row.read<String>('entity_id')),
              Variable(row.read<int>('revision')),
            ],
          )
          .getSingleOrNull();
      await db.customStatement(
        'UPDATE sync_shadow SET apply_before_json=? WHERE entity_kind=? AND entity_id=?',
        [
          frozen?.read<String>('payload_json') ?? '{}',
          row.read<String>('entity_kind'),
          row.read<String>('entity_id'),
        ],
      );
    }
  }
  for (final spec in schema.tables) {
    final kind = spec.name;
    if (!spec.columns.contains('deleted_at')) {
      await db.customStatement(
        '''CREATE TRIGGER IF NOT EXISTS restore_reinsert_$kind BEFORE INSERT ON $kind
        WHEN (SELECT suppressed=0 FROM sync_profile WHERE id=1)
        BEGIN
          INSERT OR IGNORE INTO sync_restore_intents(entity_kind,entity_id) SELECT '$kind',${spec.sqlId('NEW')} WHERE EXISTS(SELECT 1 FROM sync_tombstones WHERE entity_kind='$kind' AND entity_id=${spec.sqlId('NEW')});
          DELETE FROM sync_tombstones WHERE entity_kind='$kind' AND entity_id=${spec.sqlId('NEW')};
        END''',
      );
    } else {
      await db.customStatement(
        '''CREATE TRIGGER IF NOT EXISTS guard_reinsert_$kind BEFORE INSERT ON $kind
        WHEN NEW.deleted_at IS NULL AND (SELECT suppressed=0 AND restoring=0 FROM sync_profile WHERE id=1) AND EXISTS(SELECT 1 FROM sync_tombstones WHERE entity_kind='$kind' AND entity_id=${spec.sqlId('NEW')})
        BEGIN SELECT RAISE(ABORT,'Explicit restore required'); END''',
      );
    }
    for (final action in ['UPDATE', 'DELETE']) {
      final alias = action == 'DELETE' ? 'OLD' : 'NEW';
      final deleted = action == 'DELETE'
          ? '1'
          : spec.columns.contains('deleted_at')
          ? 'NEW.deleted_at IS NOT NULL'
          : '0';
      await db.customStatement(
        '''CREATE TRIGGER IF NOT EXISTS tombstone_${kind}_${action.toLowerCase()} AFTER $action ON $kind
        WHEN (SELECT suppressed=0 FROM sync_profile WHERE id=1) AND $deleted
        BEGIN
          INSERT INTO sync_tombstones(entity_kind,entity_id,deleted_at) VALUES('$kind',${spec.sqlId(alias)},${spec.columns.contains('deleted_at') ? 'COALESCE($alias.deleted_at,unixepoch())' : 'unixepoch()'})
            ON CONFLICT(entity_kind,entity_id) DO UPDATE SET deleted_at=excluded.deleted_at;
          DELETE FROM sync_restore_intents WHERE entity_kind='$kind' AND entity_id=${spec.sqlId(alias)};
        END''',
      );
    }
    for (final action in ['INSERT', 'UPDATE', 'DELETE']) {
      final alias = action == 'DELETE' ? 'OLD' : 'NEW';
      final id = spec.sqlId(alias);
      final payload = action == 'DELETE'
          ? spec.columns.contains('deleted_at')
                ? "json_set(${spec.sqlPayload(alias)}, '\$.deleted_at', COALESCE(OLD.deleted_at,unixepoch()))"
                : "json_set(${spec.sqlPayload(alias)}, '\$._deleted', 1)"
          : spec.sqlPayload(alias);
      final deleted = action == 'DELETE'
          ? '1'
          : spec.columns.contains('deleted_at')
          ? '$alias.deleted_at IS NOT NULL'
          : '0';
      final base =
          "COALESCE((SELECT CASE WHEN pending_apply=1 THEN apply_before_json ELSE payload_json END FROM sync_shadow WHERE entity_kind='$kind' AND entity_id=$id),'{}')";
      final fields =
          "(SELECT json_group_array(key) FROM json_each($payload) WHERE json_extract($base,'\$.'||key) IS NOT value)";
      final pending =
          "entity_kind='$kind' AND entity_id=$id AND status='pending' AND operation_id IN (SELECT operation_id FROM sync_operation_meta WHERE attempts=0)";
      // Rebuild capture triggers after additive metadata upgrades.
      await db.customStatement(
        'DROP TRIGGER IF EXISTS sync_${kind}_${action.toLowerCase()}',
      );
      if (action != 'DELETE') {
        await db.customStatement(
          '''CREATE TRIGGER IF NOT EXISTS refresh_conflict_${kind}_${action.toLowerCase()} AFTER $action ON $kind
          WHEN (SELECT suppressed=0 FROM sync_profile WHERE id=1)
          BEGIN UPDATE sync_conflicts SET local_json=(SELECT json_quote(value) FROM json_each($payload) WHERE key=sync_conflicts.field)
            WHERE entity_kind='$kind' AND entity_id=$id AND resolved_at IS NULL AND field IN (${spec.columns.map((key) => "'$key'").join(',')}); END''',
        );
      }
      await db.customStatement(
        '''CREATE TRIGGER IF NOT EXISTS sync_${kind}_${action.toLowerCase()} AFTER $action ON $kind
        WHEN (SELECT enabled=1 AND suppressed=0 FROM sync_profile WHERE id=1)
        BEGIN
          INSERT INTO sync_tombstones(entity_kind,entity_id,deleted_at) SELECT '$kind',$id,unixepoch() WHERE $deleted
            ON CONFLICT(entity_kind,entity_id) DO UPDATE SET deleted_at=excluded.deleted_at;
          DELETE FROM sync_operation_meta WHERE operation_id IN (SELECT operation_id FROM sync_outbox WHERE $pending);
          DELETE FROM sync_outbox WHERE entity_kind='$kind' AND entity_id=$id AND status='pending' AND operation_id NOT IN (SELECT operation_id FROM sync_operation_meta);
          INSERT INTO sync_outbox(operation_id,entity_kind,entity_id,base_revision,changed_fields_json,payload_json,status,created_at)
            VALUES(lower(hex(randomblob(16))),'$kind',$id,COALESCE((SELECT revision FROM sync_shadow WHERE entity_kind='$kind' AND entity_id=$id),0),$fields,$payload,'pending',unixepoch());
          INSERT INTO sync_operation_meta(operation_id,base_json,explicit_restore)
            SELECT operation_id,$base,((SELECT restoring FROM sync_profile WHERE id=1) OR EXISTS(SELECT 1 FROM sync_restore_intents WHERE entity_kind='$kind' AND entity_id=$id)) FROM sync_outbox WHERE rowid=last_insert_rowid();
        END''',
      );
    }
    if (spec.columns.contains('deleted_at')) {
      await db.customStatement(
        '''CREATE TRIGGER IF NOT EXISTS guard_restore_$kind BEFORE UPDATE ON $kind
        WHEN OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL AND (SELECT restoring=0 AND suppressed=0 FROM sync_profile WHERE id=1)
        BEGIN SELECT RAISE(ABORT,'Explicit restore required'); END''',
      );
    }
  }
}
