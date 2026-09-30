import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'legacy_models.dart';

class LegacyReader {
  final String databasePath;

  const LegacyReader(this.databasePath);

  Future<LegacySnapshot> read() async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(readOnly: true),
    );

    try {
      final profiles = await database.query(
        'profiles',
        where: 'active = 1',
        limit: 1,
      );
      if (profiles.isEmpty) {
        throw StateError('LEGACY_ACTIVE_PROFILE_NOT_FOUND');
      }
      final profileId = profiles.single['profile_id']?.toString();
      if (profileId == null || profileId.isEmpty) {
        throw StateError('LEGACY_PROFILE_ID_INVALID');
      }

      final skipped = <LegacySkippedEntity>[];
      final settings = await _readSettings(database, profileId);
      final tags = await _readTags(database, profileId, skipped);
      final tasks = await _readTasks(database, profileId, skipped);
      final events = await _readEvents(database, profileId, skipped);

      return LegacySnapshot(
        profileId: profileId,
        settings: settings,
        tasks: tasks,
        tags: tags,
        events: events,
        skipped: skipped,
      );
    } finally {
      await database.close();
    }
  }

  Future<LegacySettings> _readSettings(
    Database database,
    String profileId,
  ) async {
    final rows = await database.query(
      'settings',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const LegacySettings();
    }
    final state = rows.single['state_json']?.toString();
    if (state == null || state.isEmpty) {
      return const LegacySettings();
    }
    final json = (jsonDecode(state) as Map).cast<String, Object?>();
    return LegacySettings.fromJson(json);
  }

  Future<List<LegacyTask>> _readTasks(
    Database database,
    String profileId,
    List<LegacySkippedEntity> skipped,
  ) async {
    final rows = await database.query(
      'tasks',
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );
    final tasks = <LegacyTask>[];
    for (final row in rows) {
      final entityId = row['task_id']?.toString() ?? 'unknown';
      try {
        final state = row['state_json']?.toString() ?? '';
        final json = (jsonDecode(state) as Map).cast<String, Object?>();
        tasks.add(LegacyTask.fromJson(json));
      } catch (error) {
        skipped.add(
          LegacySkippedEntity(
            entityKind: 'task',
            entityId: entityId,
            reason: error.toString(),
          ),
        );
      }
    }
    return tasks;
  }

  Future<List<LegacyTag>> _readTags(
    Database database,
    String profileId,
    List<LegacySkippedEntity> skipped,
  ) async {
    final rows = await database.query(
      'tags',
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );
    final tags = <LegacyTag>[];
    for (final row in rows) {
      final entityId = row['tag_id']?.toString() ?? 'unknown';
      try {
        final state = row['state_json']?.toString() ?? '';
        final json = (jsonDecode(state) as Map).cast<String, Object?>();
        tags.add(LegacyTag.fromJson(json));
      } catch (error) {
        skipped.add(
          LegacySkippedEntity(
            entityKind: 'tag',
            entityId: entityId,
            reason: error.toString(),
          ),
        );
      }
    }
    return tags;
  }

  Future<List<LegacyEvent>> _readEvents(
    Database database,
    String profileId,
    List<LegacySkippedEntity> skipped,
  ) async {
    final rows = await database.query(
      'task_events',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'idx ASC',
    );
    final events = <LegacyEvent>[];
    for (final row in rows) {
      final entityId = row['event_id']?.toString() ?? 'unknown';
      try {
        final state = row['event_json']?.toString() ?? '';
        final json = (jsonDecode(state) as Map).cast<String, Object?>();
        events.add(LegacyEvent.fromJson(json));
      } catch (error) {
        skipped.add(
          LegacySkippedEntity(
            entityKind: 'event',
            entityId: entityId,
            reason: error.toString(),
          ),
        );
      }
    }
    return events;
  }
}
