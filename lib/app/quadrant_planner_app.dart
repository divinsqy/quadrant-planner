import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/app_theme.dart';
import 'desktop_workspace.dart';
import 'workspace_providers.dart';
import '../core/calendar/holiday_calendar_loader.dart';
import '../domain/planning/work_calendar.dart';
import '../domain/planning/work_schedule.dart';

import '../core/database/app_database.dart';
import '../core/database/database_paths.dart';
import '../migration/legacy_migration_service.dart';
import '../migration/migration_controller.dart';
import '../migration/migration_screen.dart';

class QuadrantPlannerApp extends StatelessWidget {
  final AppDatabase? database;
  final WorkCalendar? calendar;
  final MigrationController? migrationController;
  const QuadrantPlannerApp({
    super.key,
    this.database,
    this.calendar,
    this.migrationController,
  });

  @override
  Widget build(BuildContext context) {
    if (database != null) {
      if (migrationController != null) {
        return _MigrationGate(
          runtime: _StartupRuntime(
            database: database!,
            migrationController: migrationController!,
            calendar:
                calendar ??
                WorkCalendar(
                  schedule: WorkSchedule.standard(),
                  coveredYears: const {},
                  holidays: const {},
                ),
          ),
        );
      }
      return _workspace(
        database!,
        calendar ??
            WorkCalendar(
              schedule: WorkSchedule.standard(),
              coveredYears: const {},
              holidays: const {},
            ),
      );
    }
    return const _StartupGate();
  }
}

class _StartupRuntime {
  final AppDatabase database;
  final MigrationController migrationController;
  final WorkCalendar calendar;

  const _StartupRuntime({
    required this.database,
    required this.migrationController,
    required this.calendar,
  });
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late final Future<_StartupRuntime> _runtime = _openRuntime();
  AppDatabase? _database;
  MigrationController? _migration;

  Future<_StartupRuntime> _openRuntime() async {
    final paths = await DatabasePaths.current();
    final database = AppDatabase.open(paths.v1DatabasePath);
    _database = database;

    final service = LegacyMigrationService(
      database: database,
      legacyDatabasePath: paths.legacyDatabasePath,
    );
    final controller = MigrationController(
      gateway: LegacyMigrationGateway(
        database: database,
        legacyDatabasePath: paths.legacyDatabasePath,
        service: service,
      ),
    );
    _migration = controller;
    final holidays = await const HolidayCalendarLoader().load(
      'cn-release-2026-v1',
    );
    return _StartupRuntime(
      database: database,
      migrationController: controller,
      calendar: WorkCalendar(
        schedule: WorkSchedule.standard(),
        coveredYears: holidays.coveredYears,
        holidays: holidays.holidays,
      ),
    );
  }

  @override
  void dispose() {
    _database?.close();
    _migration?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StartupRuntime>(
      future: _runtime,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StartupFrame(
            child: Center(child: SelectableText('启动失败：${snapshot.error}')),
          );
        }
        final runtime = snapshot.data;
        if (runtime == null) {
          return const _StartupFrame(
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return _MigrationGate(runtime: runtime);
      },
    );
  }
}

Widget _workspace(AppDatabase database, WorkCalendar calendar) => ProviderScope(
  overrides: [
    workspaceDatabaseProvider.overrideWithValue(database),
    workspaceCalendarProvider.overrideWithValue(calendar),
  ],
  child: const DesktopWorkspace(),
);

class _StartupFrame extends StatelessWidget {
  final Widget child;
  const _StartupFrame({required this.child});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Quadrant Planner',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: Scaffold(body: child),
  );
}

class _MigrationGate extends StatefulWidget {
  final _StartupRuntime runtime;
  const _MigrationGate({required this.runtime});
  @override
  State<_MigrationGate> createState() => _MigrationGateState();
}

class _MigrationGateState extends State<_MigrationGate> {
  @override
  void initState() {
    super.initState();
    widget.runtime.migrationController.addListener(_changed);
    // Start before the migration screen mounts so its synchronous checking
    // notification cannot mark this ancestor dirty during a child build.
    widget.runtime.migrationController.initialize();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.runtime.migrationController.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    if (runtime.migrationController.stage == MigrationStage.ready) {
      return _workspace(runtime.database, runtime.calendar);
    }
    return _StartupFrame(
      child: MigrationScreen(
        controller: runtime.migrationController,
        readyBuilder: (_) => const SizedBox.shrink(),
      ),
    );
  }
}
