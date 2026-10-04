import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';

void main() {
  test('v2 upgrade retains preferences, locked plans and Focus interval history', () async {
    final folder = await Directory.systemTemp.createTemp(
      'quadrant-v2-upgrade-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}/workspace.sqlite');
    final seed = AppDatabase.forTesting(NativeDatabase(file));
    await seed
        .into(seed.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'old',
            title: 'Existing task',
            status: 'planned',
            importance: 80,
            baseUrgency: 70,
            baseUrgencyAnchorAt: DateTime.utc(2026),
            workload: 'medium',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            estimatedMinutes: const Value(60),
          ),
        );
    await seed
        .into(seed.preferences)
        .insert(
          PreferencesCompanion.insert(
            id: 'default',
            nickname: const Value('Local user'),
            importanceThreshold: const Value(65),
          ),
        );
    await seed
        .into(seed.dailyPlanBlocks)
        .insert(
          DailyPlanBlocksCompanion.insert(
            id: 'locked',
            localDate: '2026-10-05',
            taskId: 'old',
            startMinutes: 540,
            endMinutes: 600,
            isLocked: const Value(true),
            source: const Value('manual'),
          ),
        );
    const intervals =
        '[{"start":"2026-10-05T01:00:00.000Z","end":"2026-10-05T01:15:00.000Z"}]';
    await seed
        .into(seed.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: 'history',
            taskId: 'old',
            state: 'completed',
            startedAt: DateTime.utc(2026, 10, 5, 1),
            endedAt: Value(DateTime.utc(2026, 10, 5, 1, 15)),
            intervalsJson: const Value(intervals),
          ),
        );
    await seed.close();
    final upgraded = AppDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (db) {
          // Reproduce the immediately preceding schema without hand-copying all tables.
          for (final row in db.select("SELECT name FROM sqlite_master WHERE type='trigger'")) {
            db.execute('DROP TRIGGER "${row['name']}"');
          }
          db.execute('DROP INDEX one_active_focus_session');
          db.execute('DROP TABLE planner_task_overrides');
          db.execute('DROP TABLE milestone_history');
          db.execute(
            'ALTER TABLE preferences DROP COLUMN work_schedule_configured',
          );
          db.execute('ALTER TABLE daily_plan_blocks DROP COLUMN completed_at');
          db.execute('ALTER TABLE focus_sessions DROP COLUMN plan_block_id');
          db.execute('PRAGMA user_version = 2');
        },
      ),
    );
    addTearDown(upgraded.close);
    final preferences = await upgraded.select(upgraded.preferences).getSingle();
    expect(preferences.nickname, 'Local user');
    expect(preferences.importanceThreshold, 65);
    expect(preferences.workScheduleConfigured, isFalse);
    final block = await upgraded.select(upgraded.dailyPlanBlocks).getSingle();
    expect(block.isLocked, isTrue);
    expect(block.startMinutes, 540);
    expect(block.endMinutes, 600);
    expect(block.completedAt, isNull);
    final focus = await upgraded.select(upgraded.focusSessions).getSingle();
    expect(focus.state, 'completed');
    expect(focus.intervalsJson, intervals);
    expect(focus.planBlockId, isNull);
    expect(
      (await upgraded.select(upgraded.tasks).getSingle()).estimatedMinutes,
      60,
    );
  });
  test(
    'workspace upgrade preserves existing v1 tasks and adds milestone link',
    () async {
      final database = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (db) {
            db.execute('''CREATE TABLE tasks (
        id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', status TEXT NOT NULL,
        project_id TEXT, importance INTEGER NOT NULL, base_urgency INTEGER NOT NULL, base_urgency_anchor_at INTEGER NOT NULL,
        deadline INTEGER, estimated_minutes INTEGER, workload TEXT NOT NULL, progress INTEGER NOT NULL DEFAULT 0,
        include_in_weekly_report INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
        completed_at INTEGER, deleted_at INTEGER, server_revision INTEGER NOT NULL DEFAULT 0
      )''');
            db.execute(
              "INSERT INTO tasks (id,title,status,importance,base_urgency,base_urgency_anchor_at,workload,created_at,updated_at) VALUES ('old','Preserve task','planned',50,50,1,'medium',1,1)",
            );
            db.execute('PRAGMA user_version = 1');
            db.execute(
              'CREATE TABLE projects (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL)',
            );
            db.execute(
              'CREATE TABLE milestones (id TEXT NOT NULL PRIMARY KEY, project_id TEXT NOT NULL, name TEXT NOT NULL, deadline INTEGER, completed_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER)',
            );
            db.execute(
              "CREATE TABLE preferences (id TEXT NOT NULL PRIMARY KEY, nickname TEXT NOT NULL DEFAULT '', importance_threshold INTEGER NOT NULL DEFAULT 50, urgency_threshold INTEGER NOT NULL DEFAULT 50)",
            );
            db.execute(
              "CREATE TABLE daily_plan_blocks (id TEXT NOT NULL PRIMARY KEY, local_date TEXT NOT NULL, task_id TEXT NOT NULL, start_minutes INTEGER NOT NULL, end_minutes INTEGER NOT NULL, is_locked INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL DEFAULT 'suggested')",
            );
            db.execute(
              "CREATE TABLE focus_sessions (id TEXT NOT NULL PRIMARY KEY, task_id TEXT NOT NULL, state TEXT NOT NULL, started_at INTEGER NOT NULL, ended_at INTEGER, intervals_json TEXT NOT NULL DEFAULT '[]')",
            );
          },
        ),
      );
      addTearDown(database.close);
      expect(database.schemaVersion, 5);
      final row = await database.select(database.tasks).getSingle();
      expect(row.title, 'Preserve task');
      expect(row.milestoneId, isNull);
    },
  );
}
