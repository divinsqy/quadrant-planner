import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/core/sync/outbox_repository.dart';
import 'package:quadrant_planner/features/settings/data/preferences_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late OutboxRepository outbox;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outbox = OutboxRepository(db);
  });
  tearDown(() => db.close());

  test(
    'local-only edits do not enqueue; activating seeds existing data',
    () async {
      await TaskRepository(db).createTask(const TaskDraft(title: 'RTL'));
      expect(await outbox.pending(), isEmpty);
      await outbox.activate('user-a');
      expect(
        (await outbox.pending()).map((o) => o.entityKind),
        containsAll(['tasks', 'activity_events']),
      );
    },
  );

  test(
    'task and operation commit atomically and survive database reopen',
    () async {
      await outbox.activate('user-a');
      await expectLater(
        db.transaction(() async {
          await TaskRepository(db)
              .createTask(const TaskDraft(title: 'rollback'));
          throw StateError('abort');
        }),
        throwsStateError,
      );
      expect(await db.select(db.tasks).get(), isEmpty);
      expect(await outbox.pending(), isEmpty);
      final task = await TaskRepository(db)
          .createTask(const TaskDraft(title: 'dmac_regfile'));
      final ops = (await outbox.pending())
          .where((o) => o.entityKind == 'tasks')
          .toList();
      expect(ops, hasLength(1));
      expect(ops.single.entityId, task.id);
      await outbox.markFailed(ops.single.operationId, 'network');
      expect(
        (await outbox.pending()).first.operationId,
        ops.single.operationId,
      );
      await outbox.markApplied(ops.single.operationId);
      await outbox.markApplied(ops.single.operationId);
      expect(
        (await outbox.pending()).where((o) => o.entityKind == 'tasks'),
        isEmpty,
      );
    },
  );

  test(
    'settings coalesce before attempt, but attempted payload stays immutable',
    () async {
      await outbox.activate('user-a');
      final prefs = PreferencesRepository(db);
      await prefs.updateNickname('姓名');
      await prefs.updateThresholds(importance: 65, urgency: 50);
      var ops = await outbox.pending();
      expect(ops, hasLength(1));
      expect(ops.single.payload['nickname'], '姓名');
      final frozen = await outbox.beginAttempt(ops.single.operationId);
      await prefs.updateThresholds(importance: 65, urgency: 70);
      ops = await outbox.pending();
      expect(ops, hasLength(2));
      expect(ops.first.payload, frozen.payload);
      expect(ops.last.payload['urgency_threshold'], 70);
    },
  );

  test(
    'all user tables enqueue and remote application suppresses echo',
    () async {
      await outbox.activate('user-a');
      final now = DateTime.now();
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'p',
              name: 'AXI',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.reportStyleProfiles)
          .insert(
            ReportStyleProfilesCompanion.insert(
              id: 's',
              name: 'RTL',
              profileJson: '{}',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.workScheduleWindows)
          .insert(
            WorkScheduleWindowsCompanion.insert(
              id: 'w',
              weekday: 1,
              startMinutes: 540,
              endMinutes: 720,
            ),
          );
      await db
          .into(db.weeklyReports)
          .insert(
            WeeklyReportsCompanion.insert(
              id: 'r',
              fromDate: '2026-09-28',
              toDate: '2026-10-02',
              contentJson: '{}',
              createdAt: now,
              updatedAt: now,
            ),
          );
      expect((await outbox.pending()).map((o) => o.entityKind).toSet(), {
        'projects',
        'report_style_profiles',
        'work_schedule_windows',
        'weekly_reports',
      });
      await outbox.withoutCapture(
        () => db.customStatement(
          "UPDATE projects SET name = 'remote' WHERE id = 'p'",
        ),
      );
      expect(
        (await outbox.pending())
            .where((o) => o.entityKind == 'projects')
            .single
            .payload['name'],
        'AXI',
      );
      await expectLater(outbox.activate('user-b'), throwsStateError);
    },
  );
  test(
    'edits made after logout are reconciled on account reactivation',
    () async {
      await outbox.activate('u');
      final task = await TaskRepository(db)
          .createTask(const TaskDraft(title: 'before'));
      for (final op in await outbox.pending()) {
        await outbox.markApplied(op.operationId);
      }
      await outbox.disable();
      await db.customUpdate(
        "UPDATE tasks SET title='after' WHERE id=?",
        variables: [Variable(task.id)],
        updates: {db.tasks},
      );
      await outbox.activate('u');
      expect(
        (await outbox.pending())
            .where((op) => op.entityKind == 'tasks')
            .last
            .payload['title'],
        'after',
      );
    },
  );
}
