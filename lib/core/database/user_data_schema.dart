import 'dart:convert';

import 'package:drift/drift.dart';

import 'app_database.dart';
import '../sync/credential_boundary.dart';

/// Parent-first order, shared by sync and portable backup. Authentication and
/// transport bookkeeping are deliberately outside this allowlist.
const userTableNames = [
  'projects',
  'milestones',
  'tasks',
  'tags',
  'subtasks',
  'dependencies',
  'task_tags',
  'activity_events',
  'preferences',
  'work_schedule_windows',
  'weekend_overrides',
  'daily_plan_blocks',
  'planner_task_overrides',
  'focus_sessions',
  'weekly_reports',
  'weekly_notes',
  'report_style_profiles',
  'milestone_history',
];

class DataInvariantFailure implements Exception {
  const DataInvariantFailure();
}

class UserTable {
  final String name;
  final List<String> columns;
  final List<String> keys;
  final Set<String> requiredColumns;
  final Map<String, String> types;
  const UserTable(
    this.name,
    this.columns,
    this.keys,
    this.requiredColumns,
    this.types,
  );
  String idOf(Map<String, Object?> row) => keys.length == 1
      ? row[keys.single].toString()
      : _arrayId(keys.map((key) => row[key]).toList());
  String sqlId(String alias) => keys.length == 1
      ? '$alias.${keys.single}'
      : 'json_array(${keys.map((key) => '$alias.$key').join(',')})';
  String sqlPayload(String alias) =>
      'json_object(${columns.expand((column) => ["'$column'", '$alias.$column']).join(',')})';
  String get whereKey => keys.map((key) => '$key = ?').join(' AND ');
  List<Object?> keyValues(String id) => keys.length == 1 ? [id] : _parseId(id);
}

// JSON encoding keeps composite keys unambiguous even if a component contains
// delimiters. Implementations are below to keep identifier construction private.
String _arrayId(List<Object?> values) => jsonEncode(values);
List<Object?> _parseId(String id) => (jsonDecode(id) as List).cast<Object?>();

class UserDataSchema {
  final AppDatabase db;
  final List<UserTable> tables;
  UserDataSchema._(this.db, this.tables);
  static Future<UserDataSchema> load(AppDatabase db) async {
    final tables = <UserTable>[];
    for (final name in userTableNames) {
      final info = await db.customSelect('PRAGMA table_info($name)').get();
      if (info.isEmpty) continue;
      final columns = info
          .map((row) => row.read<String>('name'))
          .where(
            (name) =>
                name != 'server_revision' &&
                !(name == 'id' &&
                    info.any((row) => row.read<String>('name') == 'sync_id')),
          )
          .toList();
      final keys = name == 'milestone_history'
          ? ['sync_id']
          : info
                .where((row) => row.read<int>('pk') > 0)
                .map((row) => row.read<String>('name'))
                .toList();
      final required = info
          .where((row) => row.read<int>('notnull') == 1)
          .map((row) => row.read<String>('name'))
          .where(columns.contains)
          .toSet();
      tables.add(
        UserTable(name, columns, keys, required, {
          for (final row in info)
            row.read<String>('name'): row.read<String>('type'),
        }),
      );
    }
    return UserDataSchema._(db, tables);
  }

  UserTable table(String name) => tables.firstWhere(
    (table) => table.name == name,
    orElse: () => throw const FormatException('Unknown entity'),
  );
  Set<TableInfo> get readsFrom => db.allTables
      .where((table) => userTableNames.contains(table.actualTableName))
      .toSet();
  Future<Map<String, Object?>?> read(String kind, String id) async {
    final spec = table(kind);
    final rows = await db
        .customSelect(
          'SELECT ${spec.columns.join(',')} FROM $kind WHERE ${spec.whereKey}',
          variables: spec
              .keyValues(id)
              .map((value) => Variable(value))
              .toList(),
        )
        .get();
    return rows.isEmpty ? null : rows.single.data;
  }

  void validate(String kind, Map<String, Object?> payload) {
    final spec = table(kind);
    rejectCredentialFields(payload);
    if (payload.keys.any(
      (key) => !spec.columns.contains(key) && key != '_deleted',
    )) {
      throw const FormatException('Unknown field');
    }
    if (spec.columns.any((key) => !payload.containsKey(key))) {
      throw const FormatException('Incomplete entity');
    }
    if (spec.requiredColumns.any((key) => payload[key] == null)) {
      throw const FormatException('Missing field');
    }
    if (spec.keys.any(
      (key) => payload[key] == null || payload[key].toString().isEmpty,
    )) {
      throw const FormatException('Missing key');
    }
    for (final key in spec.columns) {
      final value = payload[key];
      if (value == null) continue;
      if (spec.types[key] == 'INTEGER' && value is! int && value is! bool ||
          spec.types[key] == 'TEXT' && value is! String) {
        throw const FormatException('Invalid field type');
      }
    }
    for (final key in [
      'importance',
      'base_urgency',
      'progress',
      'importance_threshold',
      'urgency_threshold',
    ]) {
      if (payload.containsKey(key) &&
          (payload[key] is! int ||
              (payload[key] as int) < 0 ||
              (payload[key] as int) > 100)) {
        throw const FormatException('Invalid score');
      }
    }
    if (kind == 'tasks') {
      if (![
            'inbox',
            'planned',
            'inProgress',
            'waiting',
            'completed',
            'cancelled',
          ].contains(payload['status']) ||
          !['small', 'medium', 'large'].contains(payload['workload'])) {
        throw const FormatException('Invalid task enum');
      }
      final estimate = payload['estimated_minutes'];
      if (estimate != null && (estimate is! int || estimate <= 0)) {
        throw const FormatException('Invalid estimate');
      }
    }
    if ([
      'work_schedule_windows',
      'weekend_overrides',
      'daily_plan_blocks',
    ].contains(kind)) {
      final start = payload['start_minutes'] as int,
          end = payload['end_minutes'] as int;
      if (start < 0 || end > 1440 || end <= start || start < 840 && end > 720) {
        throw const FormatException('Invalid work window');
      }
      if (kind == 'work_schedule_windows' &&
          !(payload['weekday'] as int >= 1 && payload['weekday'] as int <= 5)) {
        throw const FormatException('Invalid recurring day');
      }
    }
    if (kind == 'focus_sessions' &&
        ![
          'running',
          'paused',
          'completed',
          'blocked',
        ].contains(payload['state'])) {
      throw const FormatException('Invalid focus state');
    }
    for (final key in spec.columns.where((key) => key.endsWith('_json'))) {
      if (payload[key] != null) jsonDecode(payload[key] as String);
    }
  }

  Future<void> write(String kind, Map<String, Object?> payload) async {
    validate(kind, payload);
    final spec = table(kind);
    final id = spec.idOf(payload);
    if (payload['_deleted'] == true || payload['_deleted'] == 1) {
      if (!spec.columns.contains('deleted_at')) {
        await db.customUpdate(
          'DELETE FROM $kind WHERE ${spec.whereKey}',
          variables: spec.keyValues(id).map((v) => Variable(v)).toList(),
          updates: readsFrom,
        );
        return;
      }
      if (payload['deleted_at'] == null) {
        payload = {
          ...payload,
          'deleted_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        };
      }
    }
    if ([
          'work_schedule_windows',
          'weekend_overrides',
          'daily_plan_blocks',
        ].contains(kind) &&
        (payload['enabled'] ?? 1) != 0 &&
        payload['enabled'] != false) {
      final grouping = kind == 'work_schedule_windows'
          ? 'weekday'
          : 'local_date';
      final overlap = await db
          .customSelect(
            'SELECT 1 AS overlap FROM $kind WHERE $grouping=? AND ${kind == 'work_schedule_windows' ? 'enabled=1 AND ' : ''}start_minutes<? AND end_minutes>? AND NOT (${spec.whereKey}) LIMIT 1',
            variables: [
              Variable(payload[grouping]),
              Variable(payload['end_minutes']),
              Variable(payload['start_minutes']),
              ...spec.keyValues(id).map((v) => Variable(v)),
            ],
          )
          .getSingleOrNull();
      if (overlap != null) throw const DataInvariantFailure();
    }
    final columns = spec.columns.where(payload.containsKey).toList();
    final updates = columns
        .where((key) => !spec.keys.contains(key))
        .map((key) => '$key = excluded.$key')
        .join(',');
    await db.customInsert(
      'INSERT INTO $kind (${columns.join(',')}) VALUES (${columns.map((_) => '?').join(',')}) ON CONFLICT (${spec.keys.join(',')}) DO ${updates.isEmpty ? 'NOTHING' : 'UPDATE SET $updates'}',
      variables: columns.map((key) => Variable(payload[key])).toList(),
      updates: readsFrom,
    );
  }
}
