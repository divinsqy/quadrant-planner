import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/backup/backup_service.dart';
import '../core/sync/sync_coordinator.dart';
import '../core/sync/secure_session_store.dart';
import '../core/sync/supabase_sync_client.dart';
import '../features/tasks/data/trash_repository.dart';
import '../domain/planning/work_calendar.dart';
import '../features/dashboard/application/dashboard_controller.dart';
import '../features/projects/data/project_repository.dart';
import '../features/search/application/global_search_controller.dart';
import '../features/search/data/repository_global_search_source.dart';
import '../features/settings/data/preferences_repository.dart';
import '../features/tags/data/tag_repository.dart';
import '../features/tasks/application/task_editor_controller.dart';
import '../features/tasks/application/tasks_library_controller.dart';
import '../features/tasks/data/task_activity_repository.dart';
import '../features/tasks/data/task_relations_repository.dart';
import '../features/tasks/data/task_repository.dart';
import '../features/settings/data/work_schedule_repository.dart';
import '../features/planner/data/planner_repository.dart';
import '../features/planner/application/planner_controller.dart';
import '../features/focus/data/focus_repository.dart';
import '../features/focus/application/focus_controller.dart';
import '../features/reports/data/report_repository.dart';
import '../features/reports/data/weekly_note_repository.dart';
import '../features/reports/application/reports_controller.dart';
import '../features/reports/ai/report_rewriter.dart';

// The startup gate owns the database lifetime; repositories share this local
// source of truth. Tests override these same boundaries without platform IO.
final workspaceDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError('Workspace database must be provided'),
);
final workspaceCalendarProvider = Provider<WorkCalendar>(
  (ref) => throw StateError('Workspace calendar must be provided'),
);
final taskRepositoryProvider = Provider(
  (ref) => TaskRepository(ref.watch(workspaceDatabaseProvider)),
);
final syncCoordinatorProvider = Provider((ref) {
  final coordinator = SyncCoordinator(
    db: ref.watch(workspaceDatabaseProvider),
    sessions: const OsSecureSessionStore(),
    transport: SupabaseSyncClient(),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
final backupServiceProvider = Provider(
  (ref) => BackupService(ref.watch(workspaceDatabaseProvider)),
);
final trashRepositoryProvider = Provider(
  (ref) => TrashRepository(ref.watch(workspaceDatabaseProvider)),
);
final reportRepositoryProvider = Provider(
  (ref) => ReportRepository(ref.watch(workspaceDatabaseProvider)),
);
final weeklyNoteRepositoryProvider = Provider(
  (ref) => WeeklyNoteRepository(ref.watch(workspaceDatabaseProvider)),
);
// An optional network adapter can be injected; local reports remain complete.
final reportRewriteClientProvider = Provider<ReportRewriteClient?>(
  (ref) => null,
);
final reportsControllerProvider = Provider((ref) {
  final controller = ReportsController(
    reports: ref.watch(reportRepositoryProvider),
    rewriter: ReportRewriter(client: ref.watch(reportRewriteClientProvider)),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
final projectRepositoryProvider = Provider(
  (ref) => ProjectRepository(ref.watch(workspaceDatabaseProvider)),
);
final tagRepositoryProvider = Provider(
  (ref) => TagRepository(ref.watch(workspaceDatabaseProvider)),
);
final preferencesRepositoryProvider = Provider(
  (ref) => PreferencesRepository(ref.watch(workspaceDatabaseProvider)),
);
final workScheduleRepositoryProvider = Provider(
  (ref) => WorkScheduleRepository(
    ref.watch(workspaceDatabaseProvider),
    baseCalendar: ref.watch(workspaceCalendarProvider),
  ),
);
final plannerRepositoryProvider = Provider(
  (ref) => PlannerRepository(
    ref.watch(workspaceDatabaseProvider),
    schedules: ref.watch(workScheduleRepositoryProvider),
  ),
);
final plannerControllerProvider = Provider((ref) {
  final controller = PlannerController(
    plans: ref.watch(plannerRepositoryProvider),
    tasks: ref.watch(taskRepositoryProvider),
    schedules: ref.watch(workScheduleRepositoryProvider),
    preferences: ref.watch(preferencesRepositoryProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
final focusControllerProvider = Provider((ref) {
  final controller = FocusController(
    FocusRepository(ref.watch(workspaceDatabaseProvider)),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
final taskActivityProvider = Provider(
  (ref) => TaskActivityRepository(ref.watch(workspaceDatabaseProvider)),
);
final taskRelationsProvider = Provider(
  (ref) => TaskRelationsRepository(ref.watch(workspaceDatabaseProvider)),
);
final taskEditorProvider = Provider(
  (ref) => TaskEditorController(
    tasks: ref.watch(taskRepositoryProvider),
    activity: ref.watch(taskActivityProvider),
  ),
);
final dashboardControllerProvider = Provider((ref) {
  final controller = DashboardController(
    tasks: ref.watch(taskRepositoryProvider),
    preferences: ref.watch(preferencesRepositoryProvider),
    calendar: ref.watch(workspaceCalendarProvider),
    blockedTaskIds: ref.watch(taskRelationsProvider).watchBlockedTaskIds(),
    projects: ref.watch(projectRepositoryProvider),
    tags: ref.watch(tagRepositoryProvider),
    calendars: ref.watch(workScheduleRepositoryProvider).watchCalendar(),
    planner: ref.watch(plannerRepositoryProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
final tasksLibraryControllerProvider = Provider((ref) {
  final controller = TasksLibraryController(
    tasks: ref.watch(taskRepositoryProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
final globalSearchControllerProvider = Provider((ref) {
  final controller = GlobalSearchController(
    source: RepositoryGlobalSearchSource(
      tasks: ref.watch(taskRepositoryProvider),
      projects: ref.watch(projectRepositoryProvider),
      tags: ref.watch(tagRepositoryProvider),
    ),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
