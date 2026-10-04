import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/core/sync/outbox_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';
import 'package:quadrant_planner/features/tasks/data/trash_repository.dart';

void main() {
  test('29 days retained; old deletion purges with durable tombstone and explicit restore', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 10, 3);
    final tasks = TaskRepository(db);
    final recent = await tasks.createTask(const TaskDraft(title: 'recent'));
    final old = await tasks.createTask(const TaskDraft(title: 'old'));
    await tasks.softDelete(recent.id, now.subtract(const Duration(days: 29)));
    await tasks.softDelete(old.id, now.subtract(const Duration(days: 31)));
    final trash = TrashRepository(db, clock: () => now);
    expect(await trash.list(), hasLength(2));
    expect(await trash.purgeEligible(), 1);
    expect(await tasks.get(old.id), isNull);
    expect(await tasks.get(recent.id), isNotNull);
    expect(
      await db
          .customSelect(
            'SELECT * FROM sync_tombstones WHERE entity_id=?',
            variables: [Variable(old.id)],
          )
          .get(),
      hasLength(1),
    );
    await trash.restore('tasks', recent.id);
    expect((await tasks.getTasks()).single.id, recent.id);
  });
  test('pending deletion and unresolved conflict prevent purge', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 10, 3);
    final tasks = TaskRepository(db);
    final outbox = OutboxRepository(db);
    await outbox.activate('u');
    final task = await tasks.createTask(const TaskDraft(title: 'protected'));
    await tasks.softDelete(task.id, now.subtract(const Duration(days: 31)));
    expect(await TrashRepository(db, clock: () => now).purgeEligible(), 0);
    await db
        .into(db.syncConflicts)
        .insert(
          SyncConflictsCompanion.insert(
            id: 'c',
            entityKind: 'tasks',
            entityId: task.id,
            field: 'title',
            localJson: '"local"',
            remoteJson: '"remote"',
            createdAt: now,
          ),
        );
    for (final op in await outbox.pending()) {
      await outbox.markApplied(op.operationId);
    }
    expect(await TrashRepository(db, clock: () => now).purgeEligible(), 0);
  });
}
