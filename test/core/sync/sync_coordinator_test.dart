import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Variable, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/core/sync/supabase_sync_client.dart';
import 'package:quadrant_planner/core/sync/sync_coordinator.dart';
import 'package:quadrant_planner/core/sync/conflict_repository.dart';
import 'package:quadrant_planner/core/sync/sync_operation.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';
import 'package:quadrant_planner/features/tasks/data/trash_repository.dart';
import 'package:quadrant_planner/features/settings/data/work_schedule_repository.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/core/sync/field_merge.dart';

import '../../support/sync_fakes.dart';

void main() {
  late AppDatabase db;
  late MemorySessions sessions;
  late FakeCloud cloud;
  late SyncCoordinator sync;
  var closedInside = false;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessions = MemorySessions();
    cloud = FakeCloud();
    sync = SyncCoordinator(db: db, sessions: sessions, transport: cloud);
    closedInside = false;
  });
  tearDown(() async {
    if (!closedInside) {
      sync.dispose();
      await db.close();
    }
  });
  Future<void> login() async => sync.signIn('a@example.com', '123456');
  test('no session leaves app usable; offline push retains committed edit and sanitized error', () async {
    await TaskRepository(db).createTask(const TaskDraft(title: 'RTL'));
    await sync.syncOnce();
    expect(sync.status, SyncStatus.disabled);
    await login();
    cloud.fail = true;
    await sync.syncOnce();
    expect(sync.status, SyncStatus.pending);
    expect((await TaskRepository(db).getTasks()).single.title, 'RTL');
    expect(await sync.outbox.pending(), isNotEmpty);
    final dump = (await db.customSelect('SELECT * FROM sync_outbox').get())
        .toString();
    expect(dump, isNot(contains('SECRET')));
  });
  test('local commit completes while network is blocked and repeated operation is idempotent', () async {
    await login();
    await TaskRepository(db).createTask(const TaskDraft(title: 'AXI'));
    cloud.gate = Completer<void>();
    final running = sync.syncOnce();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await TaskRepository(db)
        .createTask(const TaskDraft(title: 'UVM'))
        .timeout(const Duration(seconds: 2));
    expect(await TaskRepository(db).getTasks(), hasLength(2));
    cloud.gate!.complete();
    await running;
    await sync.syncOnce();
    expect(sync.status, SyncStatus.synced);
    final op =
        (await db
                .customSelect(
                  "SELECT o.*,m.base_json,m.explicit_restore FROM sync_outbox o JOIN sync_operation_meta m USING(operation_id) LIMIT 1",
                )
                .getSingle())
            .data;
    final before = cloud.changes.length;
    await cloud.push(SyncOperation.fromRow(op), sessions.value!);
    expect(cloud.changes, hasLength(before));
  });
  test('remote different field merges, conflict persists until explicitly resolved', () async {
    await login();
    final task = await TaskRepository(db)
        .createTask(const TaskDraft(title: 'RTL'));
    await sync.syncOnce();
    final key = 'tasks/${task.id}';
    final old = cloud.entities[key]!;
    await db.customUpdate(
      'UPDATE tasks SET title=? WHERE id=?',
      variables: [const Variable('local'), Variable(task.id)],
      updates: {db.tasks},
    );
    final remote = RemoteEntity(
      kind: 'tasks',
      id: task.id,
      revision: old.revision + 1,
      payload: {...old.payload, 'deadline': 1900000000},
      sequence: cloud.changes.length + 1,
    );
    cloud.entities[key] = remote;
    cloud.changes.add(remote);
    await sync.syncOnce();
    await sync.syncOnce();
    final saved = await TaskRepository(db).get(task.id);
    expect(saved!.title, 'local');
    expect(saved.deadline, isNotNull);
    final current = cloud.entities[key]!;
    await db.customUpdate(
      'UPDATE tasks SET importance=60 WHERE id=?',
      variables: [Variable(task.id)],
      updates: {db.tasks},
    );
    final overlap = RemoteEntity(
      kind: 'tasks',
      id: task.id,
      revision: current.revision + 1,
      payload: {...current.payload, 'importance': 70},
      sequence: cloud.changes.length + 1,
    );
    cloud.entities[key] = overlap;
    cloud.changes.add(overlap);
    await sync.syncOnce();
    expect(sync.status, SyncStatus.conflict);
    final conflicts = await sync.conflicts.unresolved();
    expect(conflicts.single.field, 'importance');
    await sync.conflicts.resolve(conflicts.single.id, ConflictChoice.local);
    await sync.syncOnce();
    expect(cloud.entities[key]!.payload['importance'], 60);
    expect(await sync.conflicts.unresolved(), isEmpty);
  });
  test('queued edits and conflicts survive a real database reopen', () async {
    final dir = await Directory.systemTemp.createTemp('qpb-sync-test-');
    final path = '${dir.path}/workspace.sqlite';
    final disk = AppDatabase.forTesting(NativeDatabase(File(path)));
    final first = SyncCoordinator(
      db: disk,
      sessions: sessions,
      transport: cloud,
    );
    await first.signIn('a', '1');
    await TaskRepository(disk).createTask(const TaskDraft(title: 'survives'));
    await first.conflicts.record(
      'tasks',
      (await TaskRepository(disk).getTasks()).single.id,
      const FieldConflict('description', '', 'local', 'remote'),
    );
    first.dispose();
    await disk.close();
    final reopened = AppDatabase.forTesting(NativeDatabase(File(path)));
    final second = SyncCoordinator(
      db: reopened,
      sessions: sessions,
      transport: cloud,
    );
    expect(await second.outbox.pending(), isNotEmpty);
    expect(await second.conflicts.unresolved(), hasLength(1));
    await second.syncOnce();
    expect(second.status, SyncStatus.conflict);
    second.dispose();
    await reopened.close();
    await dir.delete(recursive: true);
  });
  test('stale offline edit cannot resurrect remote delete; explicit restore propagates', () async {
    await login();
    final task = await TaskRepository(db)
        .createTask(const TaskDraft(title: 'RTL'));
    await sync.syncOnce();
    final key = 'tasks/${task.id}', old = cloud.entities['tasks/${task.id}']!;
    await db.customUpdate(
      "UPDATE tasks SET title='offline edit' WHERE id=?",
      variables: [Variable(task.id)],
      updates: {db.tasks},
    );
    final deletion = RemoteEntity(
      kind: 'tasks',
      id: task.id,
      revision: old.revision + 1,
      payload: {...old.payload, 'deleted_at': 1900000000},
      sequence: cloud.changes.length + 1,
    );
    cloud.entities[key] = deletion;
    cloud.changes.add(deletion);
    await sync.syncOnce();
    expect(await TaskRepository(db).getTasks(), isEmpty);
    expect(sync.status, SyncStatus.conflict);
    final conflict = (await sync.conflicts.unresolved()).single;
    await sync.conflicts.resolve(conflict.id, ConflictChoice.local);
    await sync.syncOnce();
    expect(isDeleted(cloud.entities[key]!.payload), isFalse);
    expect((await TaskRepository(db).getTasks()).single.title, 'offline edit');
  });
  test('recurring work schedule delete/reinsert synchronizes new values without tombstone', () async {
    await login();
    final schedules = WorkScheduleRepository(db);
    await schedules.saveWeekdays({
      1: [const TimeWindow(startMinutes: 540, endMinutes: 720)],
    });
    await sync.syncOnce();
    await schedules.saveWeekdays({
      1: [const TimeWindow(startMinutes: 600, endMinutes: 720)],
    });
    await sync.syncOnce();
    await sync.syncOnce();
    expect(sync.status, SyncStatus.synced);
    expect(
      (await schedules.getCalendar())
          .availableWindows(DateTime(2026, 10, 5))
          .single
          .startMinutes,
      600,
    );
    expect(
      (await db
          .customSelect(
            "SELECT * FROM sync_tombstones WHERE entity_kind='work_schedule_windows'",
          )
          .get()),
      isEmpty,
    );
  });
  test('deletion in flight preserves an explicit local restore made before its receipt', () async {
    await login();
    final task = await TaskRepository(db)
        .createTask(const TaskDraft(title: 'restore'));
    await sync.syncOnce();
    await TaskRepository(db).softDelete(task.id, DateTime.now());
    cloud.gate = Completer<void>();
    final running = sync.syncOnce();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await TrashRepository(db).restore('tasks', task.id);
    cloud.gate!.complete();
    await running;
    await sync.syncOnce();
    expect(await TaskRepository(db).getTasks(), hasLength(1));
    expect(isDeleted(cloud.entities['tasks/${task.id}']!.payload), isFalse);
  });
  test(
    'keeping local after a subsequent edit uses the latest local value',
    () async {
      await login();
      final task = await TaskRepository(
        db,
      ).createTask(const TaskDraft(title: 'RTL', description: 'first local'));
      await sync.conflicts.record(
        'tasks',
        task.id,
        const FieldConflict('description', 'base', 'first local', 'remote'),
      );
      await db.customUpdate(
        'UPDATE tasks SET description=? WHERE id=?',
        variables: [const Variable('latest local'), Variable(task.id)],
        updates: {db.tasks},
      );
      await sync.conflicts.resolve(
        (await sync.conflicts.unresolved()).single.id,
        ConflictChoice.local,
      );
      expect(
        (await TaskRepository(db).get(task.id))!.description,
        'latest local',
      );
    },
  );
  test('closing during upload leaves a retryable operation without late database access', () async {
    await login();
    await TaskRepository(db)
        .createTask(const TaskDraft(title: 'safe shutdown'));
    cloud.gate = Completer<void>();
    final running = sync.syncOnce();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await sync.outbox.pending(), isNotEmpty);
    sync.dispose();
    await db.close();
    cloud.gate!.complete();
    closedInside = true;
    await expectLater(running, completes);
  });
  test(
    'closing during background startup does not leak a database error',
    () async {
      final starting = sync.start();
      sync.dispose();
      await db.close();
      closedInside = true;
      await expectLater(starting, completes);
    },
  );
  test('local edit during deferred foreign-key apply preserves remote fields and current edit', () async {
    await login();
    final task = await TaskRepository(db)
        .createTask(const TaskDraft(title: 'before'));
    await sync.syncOnce();
    final key = 'tasks/${task.id}', old = cloud.entities['tasks/${task.id}']!;
    final remote = RemoteEntity(
      kind: 'tasks',
      id: task.id,
      revision: old.revision + 1,
      payload: {
        ...old.payload,
        'project_id': 'late-parent',
        'description': 'remote result',
      },
      sequence: cloud.changes.length + 1,
    );
    cloud.entities[key] = remote;
    cloud.changes.add(remote);
    await sync.syncOnce();
    expect(sync.status, SyncStatus.pending);
    await db.customUpdate(
      "UPDATE tasks SET title='latest local' WHERE id=?",
      variables: [Variable(task.id)],
      updates: {db.tasks},
    );
    final parent = RemoteEntity(
      kind: 'projects',
      id: 'late-parent',
      revision: 1,
      payload: {
        'id': 'late-parent',
        'name': 'DMAC',
        'objective': '',
        'deadline': null,
        'created_at': 1,
        'updated_at': 1,
        'deleted_at': null,
      },
      sequence: cloud.changes.length + 1,
    );
    cloud.entities['projects/late-parent'] = parent;
    cloud.changes.add(parent);
    await sync.syncOnce();
    await sync.syncOnce();
    final saved = (await TaskRepository(db).get(task.id))!;
    expect(saved.title, 'latest local');
    expect(saved.projectId, 'late-parent');
    expect(saved.description, 'remote result');
    expect(cloud.entities[key]!.payload['project_id'], 'late-parent');
  });
  test('deferred auto-merge eventually enqueues its local field after parent arrives', () async {
    await login();
    final task = await TaskRepository(db)
        .createTask(const TaskDraft(title: 'before'));
    await sync.syncOnce();
    final key = 'tasks/${task.id}', old = cloud.entities['tasks/${task.id}']!;
    await db.customUpdate(
      "UPDATE tasks SET title='local before pull' WHERE id=?",
      variables: [Variable(task.id)],
      updates: {db.tasks},
    );
    final remote = RemoteEntity(
      kind: 'tasks',
      id: task.id,
      revision: old.revision + 1,
      payload: {...old.payload, 'project_id': 'late-parent'},
      sequence: cloud.changes.length + 1,
    );
    cloud.entities[key] = remote;
    cloud.changes.add(remote);
    await sync.syncOnce();
    final parent = RemoteEntity(
      kind: 'projects',
      id: 'late-parent',
      revision: 1,
      payload: {
        'id': 'late-parent',
        'name': 'DMAC',
        'objective': '',
        'deadline': null,
        'created_at': 1,
        'updated_at': 1,
        'deleted_at': null,
      },
      sequence: cloud.changes.length + 1,
    );
    cloud.entities['projects/late-parent'] = parent;
    cloud.changes.add(parent);
    await sync.syncOnce();
    await sync.syncOnce();
    expect((await TaskRepository(db).get(task.id))!.title, 'local before pull');
    expect(cloud.entities[key]!.payload['title'], 'local before pull');
    expect(sync.status, SyncStatus.synced);
  });
  test(
    'restore intent survives resolving deletion before another text conflict',
    () async {
      await login();
      final task = await TaskRepository(db)
          .createTask(const TaskDraft(title: 'RTL', description: 'base'));
      await sync.syncOnce();
      final key = 'tasks/${task.id}', old = cloud.entities['tasks/${task.id}']!;
      await db.customUpdate(
        "UPDATE tasks SET description='local' WHERE id=?",
        variables: [Variable(task.id)],
        updates: {db.tasks},
      );
      final changed = RemoteEntity(
        kind: 'tasks',
        id: task.id,
        revision: old.revision + 1,
        payload: {...old.payload, 'description': 'remote'},
        sequence: cloud.changes.length + 1,
      );
      cloud.entities[key] = changed;
      cloud.changes.add(changed);
      await sync.syncOnce();
      final deleted = RemoteEntity(
        kind: 'tasks',
        id: task.id,
        revision: changed.revision + 1,
        payload: {...changed.payload, 'deleted_at': 1900000000},
        sequence: cloud.changes.length + 1,
      );
      cloud.entities[key] = deleted;
      cloud.changes.add(deleted);
      await sync.syncOnce();
      final conflicts = await sync.conflicts.unresolved();
      expect(conflicts, hasLength(2));
      await sync.conflicts.resolve(
        conflicts.singleWhere((c) => c.field == '_deletion').id,
        ConflictChoice.local,
      );
      await sync.conflicts.resolve(
        conflicts.singleWhere((c) => c.field == 'description').id,
        ConflictChoice.local,
      );
      await sync.syncOnce();
      expect(isDeleted(cloud.entities[key]!.payload), isFalse);
      expect(cloud.entities[key]!.payload['description'], 'local');
    },
  );
  test('independent calendar edits that would overlap become a resolvable conflict', () async {
    await login();
    final schedules = WorkScheduleRepository(db);
    await schedules.saveWeekdays({
      1: [
        const TimeWindow(startMinutes: 540, endMinutes: 600),
        const TimeWindow(startMinutes: 660, endMinutes: 720),
      ],
    });
    await sync.syncOnce();
    final second = cloud.entities.values.singleWhere(
      (e) =>
          e.kind == 'work_schedule_windows' &&
          e.payload['start_minutes'] == 660,
    );
    await schedules.saveWeekdays({
      1: [
        const TimeWindow(startMinutes: 540, endMinutes: 645),
        const TimeWindow(startMinutes: 660, endMinutes: 720),
      ],
    });
    final remote = RemoteEntity(
      kind: second.kind,
      id: second.id,
      revision: second.revision + 1,
      payload: {...second.payload, 'start_minutes': 615},
      sequence: cloud.changes.length + 1,
    );
    cloud.entities['${second.kind}/${second.id}'] = remote;
    cloud.changes.add(remote);
    await sync.syncOnce();
    final calendar = await schedules.getCalendar();
    expect(
      calendar.availableWindows(DateTime(2026, 10, 5)).last.startMinutes,
      660,
    );
    final conflict = (await sync.conflicts.unresolved()).single;
    expect(conflict.field, '_invariant');
    await sync.conflicts.resolve(conflict.id, ConflictChoice.local);
    await sync.syncOnce();
    expect(sync.status, SyncStatus.synced);
  });
  test(
    'remote manual block cannot overlap or move a local locked block',
    () async {
      await login();
      final task = await TaskRepository(db)
          .createTask(const TaskDraft(title: 'RTL'));
      await sync.syncOnce();
      await db
          .into(db.dailyPlanBlocks)
          .insert(
            DailyPlanBlocksCompanion.insert(
              id: 'locked',
              localDate: '2026-10-05',
              taskId: task.id,
              startMinutes: 540,
              endMinutes: 630,
              isLocked: const Value(true),
              source: const Value('manual'),
            ),
          );
      final incoming = RemoteEntity(
        kind: 'daily_plan_blocks',
        id: 'remote',
        revision: 1,
        payload: {
          'id': 'remote',
          'local_date': '2026-10-05',
          'task_id': task.id,
          'start_minutes': 600,
          'end_minutes': 660,
          'is_locked': 1,
          'source': 'manual',
          'completed_at': null,
        },
        sequence: cloud.changes.length + 1,
      );
      cloud.entities['daily_plan_blocks/remote'] = incoming;
      cloud.changes.add(incoming);
      await sync.syncOnce();
      final rows = await db.select(db.dailyPlanBlocks).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'locked');
      expect(rows.single.endMinutes, 630);
      final conflict = (await sync.conflicts.unresolved()).single;
      expect(conflict.field, '_invariant');
      await sync.conflicts.resolve(conflict.id, ConflictChoice.local);
      await sync.syncOnce();
      expect(sync.status, SyncStatus.synced);
    },
  );
}
