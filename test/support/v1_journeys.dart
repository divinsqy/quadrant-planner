import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quadrant_planner/app/quadrant_planner_app.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/core/backup/backup_service.dart';
import 'package:quadrant_planner/core/sync/sync_coordinator.dart';
import 'package:quadrant_planner/core/sync/supabase_sync_client.dart';
import 'package:quadrant_planner/core/sync/conflict_repository.dart';
import 'package:quadrant_planner/domain/reports/weekly_report.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_board.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';
import 'package:quadrant_planner/features/tasks/application/task_editor_controller.dart';
import 'package:quadrant_planner/features/tasks/data/task_activity_repository.dart';
import 'package:quadrant_planner/features/planner/application/planner_controller.dart';
import 'package:quadrant_planner/features/planner/data/planner_repository.dart';
import 'package:quadrant_planner/features/settings/data/work_schedule_repository.dart';
import 'package:quadrant_planner/features/settings/data/preferences_repository.dart';
import 'package:quadrant_planner/features/focus/data/focus_repository.dart';
import 'package:quadrant_planner/features/reports/application/weekly_report_builder.dart';
import 'package:quadrant_planner/features/reports/data/report_repository.dart';
import 'package:quadrant_planner/features/reports/export/plain_text_report_renderer.dart';
import 'package:quadrant_planner/migration/legacy_migration_service.dart';
import 'package:quadrant_planner/migration/legacy_models.dart';

import 'legacy_fixture.dart';
import 'sync_fakes.dart';

Future<void> showDashboard(
  WidgetTester tester,
  AppDatabase db,
  String title,
) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  await tester.pumpWidget(QuadrantPlannerApp(database: db));
  await tester.pumpAndSettle();
  expect(find.byType(QuadrantBoard), findsOneWidget);
  expect(
    tester
        .widget<QuadrantBoard>(find.byType(QuadrantBoard))
        .tasks
        .any((t) => t.task.title == title),
    isTrue,
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.binding.setSurfaceSize(null);
}

void taskToReportJourney() {
  testWidgets(
    'journey: create plan focus pause recover complete and factual weekly export',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final at = DateTime(2026, 10, 5, 9);
      final tasks = TaskRepository(db, clock: () => at);
      final task = await tasks.createTask(
        const TaskDraft(
          title: 'RTL UVM AXI dmac_regfile result',
          status: TaskStatus.planned,
          estimatedMinutes: 60,
        ),
      );
      await showDashboard(tester, db, task.title);
      await tester.runAsync(() async {
        final plans = PlannerRepository(
          db,
          schedules: WorkScheduleRepository(db),
        );
        final planner = PlannerController(
          plans: plans,
          tasks: tasks,
          schedules: WorkScheduleRepository(db),
          preferences: PreferencesRepository(db),
          clock: () => at,
        );
        await planner.replan();
        final blocks = await plans.day(at);
        expect(blocks.single.start, DateTime(2026, 10, 5, 9));
        expect(blocks.single.end, DateTime(2026, 10, 5, 10));
        final focus = FocusRepository(db);
        await focus.start(task.id, at, planBlockId: blocks.single.id);
        await focus.pause(at.add(const Duration(minutes: 10)));
        expect(
          (await FocusRepository(db).activeSession())!.state.name,
          'paused',
        );
        await focus.resume(at.add(const Duration(minutes: 20)));
        final done = await focus.complete(at.add(const Duration(minutes: 45)));
        expect(done.elapsed(done.endedAt!), const Duration(minutes: 35));
        final saved = (await tasks.get(task.id))!;
        expect(saved.status, TaskStatus.completed);
        expect(saved.progress, 100);
        expect(saved.estimatedMinutes, 60);
        final reports = ReportRepository(
          db,
          clock: () => at.add(const Duration(days: 4)),
        );
        final report = await WeeklyReportBuilder(
          reports: reports,
          clock: () => at.add(const Duration(days: 4)),
        ).build(DateRange.weekOf(at), await reports.activeStyle());
        expect(report.workItems.single.evidence, isNotEmpty);
        expect(report.workItems.single.progress, 100);
        await reports.save(report);
        expect((await reports.history()).single.id, report.id);
        final text = PlainTextReportRenderer().render(
          report,
          await reports.activeStyle(),
        );
        expect(text, contains('RTL UVM AXI dmac_regfile result [100%]'));
        expect(text, contains('主管反馈:'));
        planner.dispose();
      });
    },
  );
}

void offlineSyncConflictJourney() {
  testWidgets(
    'journey: local offline edit reconnect conflict persists and explicit resolution reaches cloud',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final cloud = FakeCloud();
      final sync = SyncCoordinator(
        db: db,
        sessions: MemorySessions(),
        transport: cloud,
      );
      await tester.runAsync(() async {
        await sync.signIn('fixture@example.com', '123456');
        final tasks = TaskRepository(db);
        final editor = TaskEditorController(
          tasks: tasks,
          activity: TaskActivityRepository(db),
        );
        final task = await tasks.createTask(
          const TaskDraft(title: 'RTL baseline', status: TaskStatus.planned),
        );
        await sync.syncOnce();
        cloud.fail = true;
        await editor.save(task, title: 'UVM offline result');
        await sync.syncOnce();
        expect((await tasks.get(task.id))!.title, 'UVM offline result');
        expect(await sync.outbox.pending(), isNotEmpty);
        final old = cloud.entities['tasks/${task.id}']!;
        final remote = RemoteEntity(
          kind: 'tasks',
          id: task.id,
          revision: old.revision + 1,
          payload: {...old.payload, 'title': 'AXI remote result'},
          sequence: cloud.changes.length + 1,
        );
        cloud.entities['tasks/${task.id}'] = remote;
        cloud.changes.add(remote);
        cloud.fail = false;
        await sync.syncOnce();
        expect(sync.status, SyncStatus.conflict);
        final conflicts = ConflictRepository(db);
        final conflict = (await conflicts.unresolved()).firstWhere(
          (c) => c.field == 'title',
        );
        expect(
          (await ConflictRepository(
            db,
          ).unresolved()).any((c) => c.id == conflict.id),
          isTrue,
        );
        await conflicts.resolve(conflict.id, ConflictChoice.local);
        await sync.syncOnce();
        await sync.syncOnce();
        expect((await tasks.get(task.id))!.title, 'UVM offline result');
        expect(
          cloud.entities['tasks/${task.id}']!.payload['title'],
          'UVM offline result',
        );
        expect(sync.status, SyncStatus.synced);
      });
      await showDashboard(tester, db, 'UVM offline result');
      sync.dispose();
    },
  );
}

void backupRestoreJourney() {
  testWidgets(
    'journey: backup mutate restore snapshot and restored Dashboard',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('v1-restore-journey-'),
      ))!;
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.runAsync(() async {
        final tasks = TaskRepository(db);
        final task = await tasks.createTask(
          const TaskDraft(
            title: 'AXI backup original',
            status: TaskStatus.planned,
          ),
        );
        final backup = BackupService(
          db,
          snapshotDirectory: Directory('${dir.path}/snapshots'),
        );
        final path = '${dir.path}/fixture.qpb';
        await backup.createBackup(path);
        await TaskEditorController(
          tasks: tasks,
          activity: TaskActivityRepository(db),
        ).save(task, title: 'Mutated');
        await backup.restoreBackup(path);
        expect((await tasks.get(task.id))!.title, 'AXI backup original');
        expect(await Directory('${dir.path}/snapshots').list().length, 1);
        expect(
          await db
              .customSelect('PRAGMA user_version')
              .getSingle()
              .then((r) => r.data.values.single),
          5,
        );
      });
      await showDashboard(tester, db, 'AXI backup original');
    },
  );
}

void legacyMigrationJourney() {
  testWidgets(
    'journey: v0 fixture migration leaves source intact and reaches v1 Dashboard',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('v1-migration-journey-'),
      ))!;
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final path = '${dir.path}/quadrant.sqlite';
      await tester.runAsync(() async {
        sqfliteFfiInit();
        await createLegacyFixture(path);
        final before = await File(path).readAsBytes();
        final migration = LegacyMigrationService(
          database: db,
          legacyDatabasePath: path,
          calendarProvider: (_) async =>
              const LegacyCalendar(coveredYears: {2026}, holidays: {}),
        );
        final result = await migration.migrate(
          migrationAt: DateTime.utc(2026, 9, 30, 9),
        );
        expect(result.importedTasks, 3);
        expect(
          (await migration.migrate(migrationAt: DateTime.utc(2026, 9, 30, 10)))
              .alreadyMigrated,
          isTrue,
        );
        expect(await File(path).readAsBytes(), before);
        final task = (await TaskRepository(db).get('t-active'))!;
        expect(task.title, 'DMA');
        expect(task.importance, 50);
        expect(task.baseUrgency, 85);
        expect(
          await db
              .customSelect('PRAGMA user_version')
              .getSingle()
              .then((r) => r.data.values.single),
          5,
        );
      });
      await showDashboard(tester, db, 'DMA');
    },
  );
}
