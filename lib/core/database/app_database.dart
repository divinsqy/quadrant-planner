import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import 'tables.dart';
import 'sync_schema.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Tasks,
    Subtasks,
    Projects,
    Milestones,
    MilestoneHistory,
    Dependencies,
    Tags,
    TaskTags,
    ActivityEvents,
    Preferences,
    WorkScheduleWindows,
    WeekendOverrides,
    FocusSessions,
    DailyPlanBlocks,
    PlannerTaskOverrides,
    WeeklyReports,
    WeeklyNotes,
    ReportStyleProfiles,
    SyncOutbox,
    SyncState,
    SyncConflicts,
    MigrationState,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase.forTesting(super.executor);

  AppDatabase.open(String path)
    : super(NativeDatabase.createInBackground(File(path)));

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _focusIndex();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(tasks, tasks.milestoneId);
      }
      if (from < 3) {
        await migrator.createTable(plannerTaskOverrides);
        await migrator.addColumn(
          preferences,
          preferences.workScheduleConfigured,
        );
        await migrator.addColumn(dailyPlanBlocks, dailyPlanBlocks.completedAt);
        await migrator.addColumn(focusSessions, focusSessions.planBlockId);
        await _focusIndex();
      }
      if (from < 4) {
        await migrator.createTable(milestoneHistory);
        // Older versions kept only the latest row. Preserve that available
        // evidence, and distinguish it from future immutable history entries.
        await customStatement(
          '''INSERT INTO milestone_history
          (milestone_id, project_id, name, deadline, completed_at, created_at, occurred_at, is_legacy_seed)
          SELECT id, project_id, name, deadline, completed_at, created_at,
            COALESCE(completed_at, updated_at), 1 FROM milestones WHERE deleted_at IS NULL''',
        );
      }
      if (from < 5) {
        // Versions <4 create the new history table with this column already.
        if (from >= 4) {
          await migrator.addColumn(milestoneHistory, milestoneHistory.syncId);
        }
        await customStatement(
          'UPDATE milestone_history SET sync_id = lower(hex(randomblob(16))) WHERE sync_id IS NULL',
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await installSyncSchema(this);
    },
  );

  Future<void> _focusIndex() => customStatement(
    "CREATE UNIQUE INDEX IF NOT EXISTS one_active_focus_session ON focus_sessions ((1)) WHERE state IN ('running', 'paused')",
  );
}
