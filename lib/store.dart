import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

class LocalStore {
  final Database db;
  final String deviceId;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  LocalStore._(this.db, this.deviceId);

  Stream<void> get changes => _changes.stream;

  static Future<LocalStore> open() async {
    sqfliteFfiInit();
    final base = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Directory.current.path)
        : p.join(Platform.environment['HOME'] ?? Directory.current.path, 'Library', 'Application Support');
    final dir = Directory(p.join(base, 'QuadrantPlanner'));
    await dir.create(recursive: true);

    final deviceFile = File(p.join(dir.path, 'device_id.txt'));
    var deviceId = const Uuid().v4();
    if (await deviceFile.exists()) {
      final saved = (await deviceFile.readAsString()).trim();
      if (saved.isNotEmpty) deviceId = saved;
    } else {
      await deviceFile.writeAsString(deviceId, flush: true);
    }

    final db = await databaseFactoryFfi.openDatabase(
      p.join(dir.path, 'quadrant.sqlite'),
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (d) async {
          await d.execute('PRAGMA foreign_keys = ON');
          await d.execute('PRAGMA journal_mode = WAL');
        },
        onCreate: _createSchema,
      ),
    );

    final store = LocalStore._(db, deviceId);
    await store._ensureLocalProfile();
    return store;
  }

  static Future<void> _createSchema(Database d, int version) async {
    await d.execute('''
      CREATE TABLE profiles(
        profile_id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        user_id TEXT,
        active INTEGER NOT NULL DEFAULT 0,
        sync_enabled INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE tasks(
        profile_id TEXT NOT NULL,
        task_id TEXT NOT NULL,
        state_json TEXT NOT NULL,
        server_revision INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(profile_id, task_id)
      )
    ''');
    await d.execute('''
      CREATE TABLE task_events(
        profile_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        task_id TEXT NOT NULL,
        idx INTEGER NOT NULL,
        event_json TEXT NOT NULL,
        confirmed INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(profile_id, event_id),
        UNIQUE(profile_id, task_id, idx)
      )
    ''');
    await d.execute('''
      CREATE TABLE tags(
        profile_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        state_json TEXT NOT NULL,
        name TEXT NOT NULL,
        archived_at TEXT,
        PRIMARY KEY(profile_id, tag_id)
      )
    ''');
    await d.execute('CREATE UNIQUE INDEX tags_active_name_uq ON tags(profile_id, name) WHERE archived_at IS NULL');
    await d.execute('''
      CREATE TABLE settings(
        profile_id TEXT PRIMARY KEY,
        state_json TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE outbox(
        profile_id TEXT NOT NULL,
        batch_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        PRIMARY KEY(profile_id, batch_id)
      )
    ''');
    await d.execute('''
      CREATE TABLE sync_state(
        profile_id TEXT PRIMARY KEY,
        cursor INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'disabled'
      )
    ''');
    await d.execute('''
      CREATE TABLE conflicts(
        profile_id TEXT NOT NULL,
        conflict_id TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        cloud_json TEXT NOT NULL,
        local_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY(profile_id, conflict_id)
      )
    ''');
  }

  Future<void> _ensureLocalProfile() async {
    final active = await db.query('profiles', where: 'active = 1', limit: 1);
    if (active.isNotEmpty) return;
    final id = 'local-${const Uuid().v4()}';
    await db.transaction((tx) async {
      await tx.insert('profiles', {
        'profile_id': id,
        'kind': 'local',
        'active': 1,
        'sync_enabled': 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await tx.insert('sync_state', {'profile_id': id, 'cursor': 0, 'status': 'disabled'});
      await tx.insert('settings', {
        'profile_id': id,
        'state_json': jsonEncode(const AppSettings().toJson()),
      });
    });
  }

  Future<Map<String, Object?>> activeProfile() async =>
      (await db.query('profiles', where: 'active = 1', limit: 1)).single;

  Future<AppSettings> settings() async {
    final p = await activeProfile();
    final rows = await db.query('settings', where: 'profile_id = ?', whereArgs: [p['profile_id']]);
    if (rows.isEmpty) return const AppSettings();
    return AppSettings.fromJson(
      (jsonDecode(rows.single['state_json'] as String) as Map).cast<String, Object?>(),
    );
  }

  Future<void> saveSettings(AppSettings value) async {
    if (!(value.importanceMin < 0 &&
        value.importanceMax > 0 &&
        value.urgencyMin < 0 &&
        value.urgencyMax > 0)) {
      throw ArgumentError('范围必须满足 min < 0 < max');
    }
    final p = await activeProfile();
    await db.insert(
      'settings',
      {'profile_id': p['profile_id'], 'state_json': jsonEncode(value.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _changes.add(null);
  }

  Future<List<TagRecord>> listTags({bool includeArchived = false}) async {
    final p = await activeProfile();
    final rows = await db.query(
      'tags',
      where: includeArchived ? 'profile_id = ?' : 'profile_id = ? AND archived_at IS NULL',
      whereArgs: [p['profile_id']],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows
        .map((r) => TagRecord.fromJson(
              (jsonDecode(r['state_json'] as String) as Map).cast<String, Object?>(),
            ))
        .toList();
  }

  Future<void> createTag(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty || name.runes.length > 40) {
      throw ArgumentError('标签名需为 1..40 字符');
    }
    final p = await activeProfile();
    final tag = TagRecord(id: const Uuid().v4(), name: name);
    await db.insert('tags', {
      'profile_id': p['profile_id'],
      'tag_id': tag.id,
      'state_json': jsonEncode(tag.toJson()),
      'name': tag.name,
      'archived_at': null,
    });
    _changes.add(null);
  }

  Future<void> renameTag(TagRecord tag, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty || name.runes.length > 40) throw ArgumentError('标签名需为 1..40 字符');
    final p = await activeProfile();
    final next = TagRecord(id: tag.id, name: name, archivedAt: tag.archivedAt);
    await db.update(
      'tags',
      {'state_json': jsonEncode(next.toJson()), 'name': name},
      where: 'profile_id = ? AND tag_id = ?',
      whereArgs: [p['profile_id'], tag.id],
    );
    _changes.add(null);
  }

  Future<void> archiveTag(TagRecord tag) async {
    final p = await activeProfile();
    final next = TagRecord(id: tag.id, name: tag.name, archivedAt: DateTime.now().toUtc());
    await db.update(
      'tags',
      {
        'state_json': jsonEncode(next.toJson()),
        'archived_at': next.archivedAt!.toIso8601String(),
      },
      where: 'profile_id = ? AND tag_id = ?',
      whereArgs: [p['profile_id'], tag.id],
    );
    _changes.add(null);
  }

  Future<List<TaskRecord>> listTasks({
    bool includeCompleted = false,
    String? tagId,
    bool untaggedOnly = false,
  }) async {
    final p = await activeProfile();
    final rows = await db.query('tasks', where: 'profile_id = ?', whereArgs: [p['profile_id']]);
    final items = rows
        .map((r) => TaskRecord.fromJson(
              (jsonDecode(r['state_json'] as String) as Map).cast<String, Object?>(),
            ))
        .where((t) => t.status != TaskStatus.deleted)
        .where((t) => includeCompleted || t.status == TaskStatus.active)
        .where((t) => tagId == null || t.tagIds.contains(tagId))
        .where((t) => !untaggedOnly || t.tagIds.isEmpty)
        .toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<List<TaskEvent>> taskHistory(String taskId) async {
    final p = await activeProfile();
    final rows = await db.query(
      'task_events',
      where: 'profile_id = ? AND task_id = ?',
      whereArgs: [p['profile_id'], taskId],
      orderBy: 'idx ASC',
    );
    return rows
        .map((r) => TaskEvent.fromJson(
              (jsonDecode(r['event_json'] as String) as Map).cast<String, Object?>(),
            ))
        .toList();
  }

  Future<TaskRecord> createTask({
    required String title,
    required String note,
    required int importance,
    required int urgency,
    required List<String> tagIds,
  }) async {
    final s = await settings();
    final cleaned = title.trim();
    if (cleaned.isEmpty) throw ArgumentError('标题不能为空');
    if (importance < s.importanceMin ||
        importance > s.importanceMax ||
        urgency < s.urgencyMin ||
        urgency > s.urgencyMax) {
      throw ArgumentError('评分超出当前输入范围');
    }
    final now = DateTime.now().toUtc();
    final task = TaskRecord(
      id: const Uuid().v4(),
      title: cleaned,
      note: note,
      importance: importance,
      urgencyAnchor: urgency,
      urgencyAnchorAt: now,
      createdAt: now,
      tagIds: List.unmodifiable(tagIds),
      status: TaskStatus.active,
    );
    await _appendEvent('created', task, now);
    return task;
  }

  Future<TaskRecord> editTask(
    TaskRecord old, {
    required String title,
    required String note,
    required int importance,
    int? newUrgency,
    required List<String> tagIds,
  }) async {
    final s = await settings();
    final cleaned = title.trim();
    if (cleaned.isEmpty) throw ArgumentError('标题不能为空');
    if (importance < s.importanceMin || importance > s.importanceMax) {
      throw ArgumentError('重要性超出当前输入范围');
    }
    if (newUrgency != null && (newUrgency < s.urgencyMin || newUrgency > s.urgencyMax)) {
      throw ArgumentError('紧急性超出当前输入范围');
    }
    final now = DateTime.now().toUtc();
    final next = old.copyWith(
      title: cleaned,
      note: note,
      importance: importance,
      urgencyAnchor: newUrgency ?? old.urgencyAnchor,
      urgencyAnchorAt: newUrgency == null ? old.urgencyAnchorAt : now,
      tagIds: List.unmodifiable(tagIds),
    );
    await _appendEvent('edited', next, now);
    return next;
  }

  Future<void> completeTask(TaskRecord old) async {
    if (old.status != TaskStatus.active) return;
    final now = DateTime.now().toUtc();
    await _appendEvent(
      'completed',
      old.copyWith(status: TaskStatus.completed, completedAt: now),
      now,
    );
  }

  Future<void> deleteTask(TaskRecord old) async {
    final now = DateTime.now().toUtc();
    await _appendEvent(
      'deleted',
      old.copyWith(status: TaskStatus.deleted, deletedAt: now),
      now,
    );
  }

  Future<void> _appendEvent(String type, TaskRecord state, DateTime at) async {
    final profile = await activeProfile();
    final profileId = profile['profile_id'] as String;
    await db.transaction((tx) async {
      final previous = await tx.query(
        'task_events',
        where: 'profile_id = ? AND task_id = ?',
        whereArgs: [profileId, state.id],
        orderBy: 'idx DESC',
        limit: 1,
      );
      if (previous.isNotEmpty) {
        final last = TaskEvent.fromJson(
          (jsonDecode(previous.single['event_json'] as String) as Map).cast<String, Object?>(),
        );
        if (at.isBefore(last.occurredAt)) throw StateError('CLOCK_SKEW');
      }

      final count = Sqflite.firstIntValue(await tx.rawQuery(
            'SELECT COUNT(*) FROM task_events WHERE profile_id = ? AND task_id = ?',
            [profileId, state.id],
          )) ??
          0;
      final event = TaskEvent(
        id: const Uuid().v4(),
        taskId: state.id,
        type: type,
        occurredAt: at,
        after: state,
      );
      final taskRows = await tx.query(
        'tasks',
        columns: ['server_revision'],
        where: 'profile_id = ? AND task_id = ?',
        whereArgs: [profileId, state.id],
        limit: 1,
      );
      final baseRevision =
          taskRows.isEmpty ? 0 : (taskRows.single['server_revision'] as num).toInt();

      await tx.insert('task_events', {
        'profile_id': profileId,
        'event_id': event.id,
        'task_id': state.id,
        'idx': count,
        'event_json': jsonEncode(event.toJson()),
        'confirmed': 0,
      });
      await tx.insert(
        'tasks',
        {
          'profile_id': profileId,
          'task_id': state.id,
          'state_json': jsonEncode(state.toJson()),
          'server_revision': baseRevision,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (profile['kind'] == 'account' && profile['sync_enabled'] == 1) {
        final batchId = const Uuid().v4();
        await tx.insert('outbox', {
          'profile_id': profileId,
          'batch_id': batchId,
          'status': 'pending',
          'payload_json': jsonEncode({
            'schema_version': 1,
            'batch_id': batchId,
            'entity_kind': 'task',
            'entity_id': state.id,
            'base_revision': baseRevision,
            'events': [event.toJson()],
          }),
        });
      }
    });
    _changes.add(null);
  }

  Future<WeeklySummary> weeklySummary(BusinessCalendar calendar, DateTime weekStart) async {
    final start = DateTime.utc(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 7));
    final p = await activeProfile();
    final rows = await db.query(
      'task_events',
      where: 'profile_id = ?',
      whereArgs: [p['profile_id']],
      orderBy: 'task_id, idx',
    );

    final grouped = <String, List<TaskEvent>>{};
    for (final row in rows) {
      final event = TaskEvent.fromJson(
        (jsonDecode(row['event_json'] as String) as Map).cast<String, Object?>(),
      );
      grouped.putIfAbsent(event.taskId, () => []).add(event);
    }

    var created = 0;
    var completed = 0;
    var activeAtEnd = 0;
    var taskDays = 0;
    final heatmap = <String, int>{};

    for (final history in grouped.values) {
      created += history.where((e) => e.type == 'created' && !e.occurredAt.isBefore(start) && e.occurredAt.isBefore(end)).length;
      completed += history.where((e) => e.type == 'completed' && !e.occurredAt.isBefore(start) && e.occurredAt.isBefore(end)).length;

      TaskRecord? endState;
      for (final e in history) {
        if (e.occurredAt.isBefore(end)) endState = e.after;
      }
      if (endState != null && endState.status == TaskStatus.active) activeAtEnd++;

      for (var day = start; day.isBefore(end); day = day.add(const Duration(days: 1))) {
        final dayEnd = day.add(const Duration(days: 1));
        TaskRecord? state;
        for (final e in history) {
          if (e.occurredAt.isBefore(dayEnd)) state = e.after;
        }
        if (state == null || state.status != TaskStatus.active) continue;
        final urgency = calendar.urgency(state, dayEnd.subtract(const Duration(microseconds: 1)));
        if (urgency == null) continue;
        taskDays++;
        final key = '$urgency,${state.importance}';
        heatmap[key] = (heatmap[key] ?? 0) + 1;
      }
    }

    return WeeklySummary(
      from: start,
      to: end,
      created: created,
      completed: completed,
      activeAtEnd: activeAtEnd,
      taskDays: taskDays,
      heatmap: heatmap,
    );
  }

  Future<Map<String, Object?>> exportBackup() async {
    final p = await activeProfile();
    final profileId = p['profile_id'];
    final events = await db.query(
      'task_events',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'task_id, idx',
    );
    final tags = await db.query('tags', where: 'profile_id = ?', whereArgs: [profileId]);
    final s = await settings();
    return {
      'schema_version': 1,
      'app_version': '0.8.0',
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'events': events.map((e) => jsonDecode(e['event_json'] as String)).toList(),
      'tags': tags.map((e) => jsonDecode(e['state_json'] as String)).toList(),
      'settings': s.toJson(),
    };
  }

  Future<String> restoreBackup(Map<String, Object?> doc) async {
    if (doc['schema_version'] != 1 || doc['events'] is! List || doc['tags'] is! List) {
      throw const FormatException('非法或不支持的备份');
    }

    final rawEvents = (doc['events'] as List)
        .map((e) => (e as Map).cast<String, Object?>())
        .toList();
    final seen = <String>{};
    for (final e in rawEvents) {
      final parsed = TaskEvent.fromJson(e);
      if (!seen.add(parsed.id)) throw const FormatException('重复 event id');
    }

    final profileId = 'local-${const Uuid().v4()}';
    await db.transaction((tx) async {
      await tx.update('profiles', {'active': 0});
      await tx.insert('profiles', {
        'profile_id': profileId,
        'kind': 'local',
        'active': 1,
        'sync_enabled': 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await tx.insert('sync_state', {'profile_id': profileId, 'cursor': 0, 'status': 'disabled'});
      final settingsJson = (doc['settings'] as Map?)?.cast<String, Object?>() ?? const AppSettings().toJson();
      await tx.insert('settings', {
        'profile_id': profileId,
        'state_json': jsonEncode(settingsJson),
      });

      final grouped = <String, List<TaskEvent>>{};
      for (final e in rawEvents.map(TaskEvent.fromJson)) {
        grouped.putIfAbsent(e.taskId, () => []).add(e);
      }
      for (final entry in grouped.entries) {
        entry.value.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
        for (var i = 0; i < entry.value.length; i++) {
          final event = entry.value[i];
          await tx.insert('task_events', {
            'profile_id': profileId,
            'event_id': event.id,
            'task_id': event.taskId,
            'idx': i,
            'event_json': jsonEncode(event.toJson()),
            'confirmed': 0,
          });
        }
        final last = entry.value.last;
        await tx.insert('tasks', {
          'profile_id': profileId,
          'task_id': entry.key,
          'state_json': jsonEncode(last.after.toJson()),
          'server_revision': 0,
        });
      }

      for (final raw in doc['tags'] as List) {
        final tag = TagRecord.fromJson((raw as Map).cast<String, Object?>());
        await tx.insert('tags', {
          'profile_id': profileId,
          'tag_id': tag.id,
          'state_json': jsonEncode(tag.toJson()),
          'name': tag.name,
          'archived_at': tag.archivedAt?.toIso8601String(),
        });
      }
    });
    _changes.add(null);
    return profileId;
  }

  Future<List<Map<String, Object?>>> pendingOutbox() async {
    final p = await activeProfile();
    return db.query(
      'outbox',
      where: "profile_id = ? AND status IN ('pending','failed')",
      whereArgs: [p['profile_id']],
      orderBy: 'rowid',
    );
  }

  Future<void> markOutboxDone(String batchId) async {
    final p = await activeProfile();
    await db.delete(
      'outbox',
      where: 'profile_id = ? AND batch_id = ?',
      whereArgs: [p['profile_id'], batchId],
    );
  }

  Future<void> markOutboxStatus(String batchId, String status) async {
    final p = await activeProfile();
    await db.update(
      'outbox',
      {'status': status},
      where: 'profile_id = ? AND batch_id = ?',
      whereArgs: [p['profile_id'], batchId],
    );
  }

  Future<int> cursor() async {
    final p = await activeProfile();
    final rows = await db.query('sync_state', where: 'profile_id = ?', whereArgs: [p['profile_id']]);
    return rows.isEmpty ? 0 : (rows.single['cursor'] as num).toInt();
  }

  Future<void> setCursorAndStatus(int cursor, String status) async {
    final p = await activeProfile();
    await db.update(
      'sync_state',
      {'cursor': cursor, 'status': status},
      where: 'profile_id = ?',
      whereArgs: [p['profile_id']],
    );
  }

  Future<void> createAccountProfile(String userId) async {
    final accountId = 'account-$userId';
    final active = await activeProfile();
    final existing = await db.query('profiles', where: 'profile_id = ?', whereArgs: [accountId]);
    final inheritedSettings = (await settings()).toJson();
    final localEvents = active['kind'] == 'local'
        ? await db.query('task_events', where: 'profile_id = ?', whereArgs: [active['profile_id']])
        : <Map<String, Object?>>[];
    final localTasks = active['kind'] == 'local'
        ? await db.query('tasks', where: 'profile_id = ?', whereArgs: [active['profile_id']])
        : <Map<String, Object?>>[];
    final localTags = active['kind'] == 'local'
        ? await db.query('tags', where: 'profile_id = ?', whereArgs: [active['profile_id']])
        : <Map<String, Object?>>[];

    await db.transaction((tx) async {
      if (existing.isEmpty) {
        await tx.insert('profiles', {
          'profile_id': accountId,
          'kind': 'account',
          'user_id': userId,
          'active': 0,
          'sync_enabled': 1,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        await tx.insert('sync_state', {'profile_id': accountId, 'cursor': 0, 'status': 'idle'});
        await tx.insert('settings', {
          'profile_id': accountId,
          'state_json': jsonEncode(inheritedSettings),
        });

        if (active['kind'] == 'local') {
          for (final row in localEvents) {
            await tx.insert('task_events', {
              ...row,
              'profile_id': accountId,
              'confirmed': 0,
            });
          }
          for (final row in localTasks) {
            await tx.insert('tasks', {
              ...row,
              'profile_id': accountId,
              'server_revision': 0,
            });
          }
          for (final row in localTags) {
            await tx.insert('tags', {...row, 'profile_id': accountId});
          }
        }
      }
      await tx.update('profiles', {'active': 0});
      await tx.update(
        'profiles',
        {'active': 1, 'sync_enabled': 1},
        where: 'profile_id = ?',
        whereArgs: [accountId],
      );
    });
    _changes.add(null);
  }

  Future<void> disableSync() async {
    final p = await activeProfile();
    await db.update(
      'profiles',
      {'sync_enabled': 0},
      where: 'profile_id = ?',
      whereArgs: [p['profile_id']],
    );
    await setCursorAndStatus(await cursor(), 'disabled');
    _changes.add(null);
  }

  Future<void> switchToLocalProfile() async {
    final locals = await db.query('profiles', where: "kind = 'local'", orderBy: 'created_at ASC', limit: 1);
    if (locals.isEmpty) {
      await db.update('profiles', {'active': 0});
      await _ensureLocalProfile();
    } else {
      await db.transaction((tx) async {
        await tx.update('profiles', {'active': 0});
        await tx.update(
          'profiles',
          {'active': 1},
          where: 'profile_id = ?',
          whereArgs: [locals.single['profile_id']],
        );
      });
    }
    _changes.add(null);
  }

  Future<void> markBatchApplied({
    required String batchId,
    required String entityId,
    required int revision,
  }) async {
    final p = await activeProfile();
    final profileId = p['profile_id'];
    await db.transaction((tx) async {
      await tx.update(
        'tasks',
        {'server_revision': revision},
        where: 'profile_id = ? AND task_id = ?',
        whereArgs: [profileId, entityId],
      );
      await tx.update(
        'task_events',
        {'confirmed': 1},
        where: 'profile_id = ? AND task_id = ?',
        whereArgs: [profileId, entityId],
      );
      await tx.delete(
        'outbox',
        where: 'profile_id = ? AND batch_id = ?',
        whereArgs: [profileId, batchId],
      );
    });
    _changes.add(null);
  }

  Future<void> applyRemotePage(List<Object?> rawChanges, int nextCursor) async {
    final p = await activeProfile();
    final profileId = p['profile_id'] as String;
    await db.transaction((tx) async {
      for (final raw in rawChanges) {
        if (raw is! Map) continue;
        final change = raw.cast<String, Object?>();
        final kind = change['entity_kind']?.toString();
        final entityId = change['entity_id']?.toString();
        final revision = (change['revision'] as num?)?.toInt() ?? 0;
        final stateRaw = change['state'] ?? change['entity_state'] ?? change['payload'];
        if (entityId == null || stateRaw is! Map) continue;
        final state = stateRaw.cast<String, Object?>();

        if (kind == 'task') {
          final taskJson = state['task'] is Map
              ? (state['task'] as Map).cast<String, Object?>()
              : state;
          final task = TaskRecord.fromJson(taskJson);
          await tx.insert(
            'tasks',
            {
              'profile_id': profileId,
              'task_id': entityId,
              'state_json': jsonEncode(task.toJson()),
              'server_revision': revision,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          final eventsRaw = state['events'];
          if (eventsRaw is List) {
            var idx = Sqflite.firstIntValue(await tx.rawQuery(
                  'SELECT COUNT(*) FROM task_events WHERE profile_id = ? AND task_id = ?',
                  [profileId, entityId],
                )) ??
                0;
            for (final eRaw in eventsRaw) {
              if (eRaw is! Map) continue;
              final event = TaskEvent.fromJson(eRaw.cast<String, Object?>());
              final exists = await tx.query(
                'task_events',
                columns: ['event_id'],
                where: 'profile_id = ? AND event_id = ?',
                whereArgs: [profileId, event.id],
                limit: 1,
              );
              if (exists.isNotEmpty) continue;
              await tx.insert('task_events', {
                'profile_id': profileId,
                'event_id': event.id,
                'task_id': entityId,
                'idx': idx++,
                'event_json': jsonEncode(event.toJson()),
                'confirmed': 1,
              });
            }
          }
        } else if (kind == 'tag') {
          final tag = TagRecord.fromJson(state);
          await tx.insert(
            'tags',
            {
              'profile_id': profileId,
              'tag_id': tag.id,
              'state_json': jsonEncode(tag.toJson()),
              'name': tag.name,
              'archived_at': tag.archivedAt?.toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else if (kind == 'settings') {
          final settings = AppSettings.fromJson(state);
          await tx.insert(
            'settings',
            {'profile_id': profileId, 'state_json': jsonEncode(settings.toJson())},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await tx.update(
        'sync_state',
        {'cursor': nextCursor, 'status': 'idle'},
        where: 'profile_id = ?',
        whereArgs: [profileId],
      );
    });
    _changes.add(null);
  }

  Future<void> addConflict({
    required String entityId,
    required Object? cloud,
    required Object? local,
  }) async {
    final p = await activeProfile();
    await db.insert('conflicts', {
      'profile_id': p['profile_id'],
      'conflict_id': const Uuid().v4(),
      'entity_id': entityId,
      'cloud_json': jsonEncode(cloud),
      'local_json': jsonEncode(local),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    _changes.add(null);
  }

  Future<int> conflictCount() async {
    final p = await activeProfile();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) c FROM conflicts WHERE profile_id = ?',
      [p['profile_id']],
    );
    return (rows.single['c'] as num).toInt();
  }

  Future<void> dispose() async {
    await _changes.close();
    await db.close();
  }
}
