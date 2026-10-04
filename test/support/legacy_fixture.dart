import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> createLegacyFixture(String path) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE profiles(
            profile_id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            user_id TEXT,
            active INTEGER NOT NULL DEFAULT 0,
            sync_enabled INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE tasks(
            profile_id TEXT NOT NULL,
            task_id TEXT NOT NULL,
            state_json TEXT NOT NULL,
            server_revision INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(profile_id, task_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE task_events(
            profile_id TEXT NOT NULL,
            event_id TEXT NOT NULL,
            task_id TEXT NOT NULL,
            idx INTEGER NOT NULL,
            event_json TEXT NOT NULL,
            confirmed INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(profile_id, event_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE tags(
            profile_id TEXT NOT NULL,
            tag_id TEXT NOT NULL,
            state_json TEXT NOT NULL,
            name TEXT NOT NULL,
            archived_at TEXT,
            PRIMARY KEY(profile_id, tag_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE settings(
            profile_id TEXT PRIMARY KEY,
            state_json TEXT NOT NULL
          )
        ''');
      },
    ),
  );

  const profile = 'local-profile';
  await db.insert('profiles', {
    'profile_id': profile,
    'kind': 'local',
    'active': 1,
    'sync_enabled': 0,
    'created_at': '2026-09-01T00:00:00.000Z',
  });
  await db.insert('settings', {
    'profile_id': profile,
    'state_json': jsonEncode({
      'importance_min': -10,
      'importance_max': 10,
      'urgency_min': -15,
      'urgency_max': 5,
      'calendar_version': 'test-calendar',
    }),
  });

  final active = {
    'id': 't-active',
    'title': ' DMA ',
    'note': 'AXI work',
    'importance': 0,
    'urgency_anchor': 0,
    'urgency_anchor_at': '2026-09-28T09:00:00.000Z',
    'created_at': '2026-09-20T09:00:00.000Z',
    'tag_ids': ['tag-dma', 'tag-rtl'],
    'status': 'active',
    'completed_at': null,
    'deleted_at': null,
  };
  final completed = {
    'id': 't-completed',
    'title': 'Finished',
    'note': '',
    'importance': 10,
    'urgency_anchor': -5,
    'urgency_anchor_at': '2026-09-20T09:00:00.000Z',
    'created_at': '2026-09-20T09:00:00.000Z',
    'tag_ids': <String>[],
    'status': 'completed',
    'completed_at': '2026-09-25T10:00:00.000Z',
    'deleted_at': null,
  };
  final deleted = {
    'id': 't-deleted',
    'title': 'Deleted',
    'note': '',
    'importance': -10,
    'urgency_anchor': -15,
    'urgency_anchor_at': '2026-09-20T09:00:00.000Z',
    'created_at': '2026-09-20T09:00:00.000Z',
    'tag_ids': <String>[],
    'status': 'deleted',
    'completed_at': null,
    'deleted_at': '2026-09-26T10:00:00.000Z',
  };

  for (final task in [active, completed, deleted]) {
    await db.insert('tasks', {
      'profile_id': profile,
      'task_id': task['id'],
      'state_json': jsonEncode(task),
      'server_revision': 0,
    });
  }

  await db.insert('tasks', {
    'profile_id': profile,
    'task_id': 'broken',
    'state_json': '{"id":"broken","title":',
    'server_revision': 0,
  });

  for (final tag in [
    {'id': 'tag-dma', 'name': 'DMA', 'archived_at': null},
    {'id': 'tag-rtl', 'name': 'RTL', 'archived_at': null},
  ]) {
    await db.insert('tags', {
      'profile_id': profile,
      'tag_id': tag['id'],
      'state_json': jsonEncode(tag),
      'name': tag['name'],
      'archived_at': null,
    });
  }

  for (final event in [
    {
      'id': 'e1',
      'task_id': 't-active',
      'type': 'created',
      'occurred_at': '2026-09-20T09:00:00.000Z',
      'after': active,
    },
    {
      'id': 'e2',
      'task_id': 't-completed',
      'type': 'completed',
      'occurred_at': '2026-09-25T10:00:00.000Z',
      'after': completed,
    },
  ]) {
    await db.insert('task_events', {
      'profile_id': profile,
      'event_id': event['id'],
      'task_id': event['task_id'],
      'idx': event['id'] == 'e1' ? 0 : 1,
      'event_json': jsonEncode(event),
      'confirmed': 0,
    });
  }

  await db.close();
}
