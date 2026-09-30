import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Tasks,
    Subtasks,
    Projects,
    Milestones,
    Dependencies,
    Tags,
    TaskTags,
    ActivityEvents,
    Preferences,
    WorkScheduleWindows,
    WeekendOverrides,
    FocusSessions,
    DailyPlanBlocks,
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

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) => migrator.createAll(),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
