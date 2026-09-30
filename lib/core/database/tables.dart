import 'package:drift/drift.dart';

@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get status => text()();
  TextColumn get projectId =>
      text().nullable().references(Projects, #id, onDelete: KeyAction.setNull)();
  IntColumn get importance => integer()();
  IntColumn get baseUrgency => integer()();
  DateTimeColumn get baseUrgencyAnchorAt => dateTime()();
  DateTimeColumn get deadline => dateTime().nullable()();
  IntColumn get estimatedMinutes => integer().nullable()();
  TextColumn get workload => text()();
  IntColumn get progress => integer().withDefault(const Constant(0))();
  BoolColumn get includeInWeeklyReport =>
      boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get serverRevision => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SubtaskRow')
class Subtasks extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ProjectRow')
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get objective => text().withDefault(const Constant(''))();
  DateTimeColumn get deadline => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MilestoneRow')
class Milestones extends Table {
  TextColumn get id => text()();
  TextColumn get projectId =>
      text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  DateTimeColumn get deadline => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('DependencyRow')
class Dependencies extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get dependsOnTaskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {taskId, dependsOnTaskId},
      ];
}

@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TaskTagRow')
class TaskTags extends Table {
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {taskId, tagId};
}

@DataClassName('ActivityEventRow')
class ActivityEvents extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AppPreferencesRow')
class Preferences extends Table {
  TextColumn get id => text()();
  TextColumn get nickname => text().withDefault(const Constant(''))();
  IntColumn get importanceThreshold =>
      integer().withDefault(const Constant(50))();
  IntColumn get urgencyThreshold => integer().withDefault(const Constant(50))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WorkScheduleWindowRow')
class WorkScheduleWindows extends Table {
  TextColumn get id => text()();
  IntColumn get weekday => integer()();
  IntColumn get startMinutes => integer()();
  IntColumn get endMinutes => integer()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WeekendOverrideRow')
class WeekendOverrides extends Table {
  TextColumn get id => text()();
  TextColumn get localDate => text()();
  IntColumn get startMinutes => integer()();
  IntColumn get endMinutes => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FocusSessionRow')
class FocusSessions extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get state => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get intervalsJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('DailyPlanBlockRow')
class DailyPlanBlocks extends Table {
  TextColumn get id => text()();
  TextColumn get localDate => text()();
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  IntColumn get startMinutes => integer()();
  IntColumn get endMinutes => integer()();
  BoolColumn get isLocked => boolean().withDefault(const Constant(false))();
  TextColumn get source => text().withDefault(const Constant('suggested'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WeeklyReportRow')
class WeeklyReports extends Table {
  TextColumn get id => text()();
  TextColumn get fromDate => text()();
  TextColumn get toDate => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get contentJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WeeklyNoteRow')
class WeeklyNotes extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().nullable().references(Tasks, #id, onDelete: KeyAction.setNull)();
  TextColumn get weekStart => text()();
  TextColumn get problem => text().nullable()();
  TextColumn get cause => text().nullable()();
  TextColumn get solution => text().nullable()();
  TextColumn get learning => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ReportStyleProfileRow')
class ReportStyleProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get profileJson => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SyncOutboxRow')
class SyncOutbox extends Table {
  TextColumn get operationId => text()();
  TextColumn get entityKind => text()();
  TextColumn get entityId => text()();
  IntColumn get baseRevision => integer().withDefault(const Constant(0))();
  TextColumn get changedFieldsJson => text()();
  TextColumn get payloadJson => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get error => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

@DataClassName('SyncStateRow')
class SyncState extends Table {
  TextColumn get id => text()();
  IntColumn get cursor => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('disabled'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SyncConflictRow')
class SyncConflicts extends Table {
  TextColumn get id => text()();
  TextColumn get entityKind => text()();
  TextColumn get entityId => text()();
  TextColumn get field => text()();
  TextColumn get baseJson => text().nullable()();
  TextColumn get localJson => text()();
  TextColumn get remoteJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MigrationStateRow')
class MigrationState extends Table {
  TextColumn get id => text()();
  TextColumn get sourcePath => text()();
  TextColumn get sourceHash => text()();
  DateTimeColumn get migratedAt => dateTime()();
  TextColumn get importedCountsJson => text()();
  TextColumn get skippedJson => text()();
  BoolColumn get success => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
