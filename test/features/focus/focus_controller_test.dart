import 'dart:io';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/focus/focus_session.dart';
import 'package:quadrant_planner/domain/planning/planned_block.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/focus/application/focus_controller.dart';
import 'package:quadrant_planner/features/focus/data/focus_repository.dart';
import 'package:quadrant_planner/features/planner/data/planner_repository.dart';
import 'package:quadrant_planner/features/settings/data/work_schedule_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_activity_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late FocusRepository repo;
  late FocusController controller;
  late TaskRepository tasks;
  late DateTime now;
  late String taskId;
  setUp(() async {
    now = DateTime.utc(2026, 10, 5, 9);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
    taskId = (await tasks.createTask(
      const TaskDraft(
        title: 'Focus task',
        status: TaskStatus.planned,
        estimatedMinutes: 60,
      ),
    )).id;
    repo = FocusRepository(db);
    controller = FocusController(repo, clock: () => now);
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });
  test('pause interval excluded and completion records exact actual time without changing estimate', () async {
    await controller.start(taskId);
    now = now.add(const Duration(minutes: 10));
    await controller.pause();
    now = now.add(const Duration(minutes: 30));
    expect(controller.elapsed.inSeconds, 600);
    await controller.resume();
    now = now.add(const Duration(minutes: 5, seconds: 30));
    await controller.complete();
    expect(controller.session!.state, FocusSessionState.completed);
    expect(controller.elapsed.inSeconds, 930);
    final task = await tasks.get(taskId);
    expect(task!.estimatedMinutes, 60);
    expect(task.status, TaskStatus.completed);
    final events = await TaskActivityRepository(db).fetchPage(taskId);
    final actual = events.singleWhere((e) => e.type == 'focus_completed');
    expect(actual.payload['actualSeconds'], 930);
    expect(actual.payload['actualMinutes'], 15.5);
    expect(events.any((e) => e.type == 'completed'), isTrue);
  });
  test(
    'delayed watch result cannot restore running state after completion',
    () async {
      final delayed = _DelayedPriorReadRepository(db);
      final current = FocusController(delayed, clock: () => now);
      addTearDown(current.dispose);
      await current.start(taskId);
      current.watch();
      await delayed.readStarted.future;
      now = now.add(const Duration(minutes: 1));
      await current.complete();
      delayed.release.complete();
      await Future<void>.delayed(Duration.zero);
      expect(current.session!.state, FocusSessionState.completed);
    },
  );
  test(
    'simultaneous starts cannot create two running or resumable sessions',
    () async {
      final second = await tasks.createTask(
        const TaskDraft(title: 'Second', status: TaskStatus.planned),
      );
      final results = await Future.wait([
        repo.start(taskId, now).then((_) => true).catchError((_) => false),
        repo.start(second.id, now).then((_) => true).catchError((_) => false),
      ]);
      expect(results.where((v) => v), hasLength(1));
      await repo.pause(now.add(const Duration(minutes: 1)));
      await expectLater(
        repo.start(second.id, now.add(const Duration(minutes: 2))),
        throwsStateError,
      );
    },
  );
  test(
    'blocked is terminal, records duration and updates task to waiting',
    () async {
      await controller.start(taskId);
      now = now.add(const Duration(minutes: 2));
      await controller.markBlocked();
      expect(controller.session!.state, FocusSessionState.blocked);
      expect((await tasks.get(taskId))!.status, TaskStatus.waiting);
      expect(controller.elapsed.inSeconds, 120);
      await expectLater(controller.resume(), throwsStateError);
      expect(await repo.activeSession(), isNull);
    },
  );
  test(
    'terminal completion cannot be repeated and regressed timestamps rejected',
    () async {
      await controller.start(taskId);
      await expectLater(
        repo.pause(now.subtract(const Duration(seconds: 1))),
        throwsArgumentError,
      );
      now = now.add(const Duration(minutes: 1));
      await controller.complete();
      await expectLater(controller.complete(), throwsStateError);
      expect(
        (await TaskActivityRepository(db).fetchPage(taskId))
            .where((e) => e.type == 'focus_completed'),
        hasLength(1),
      );
    },
  );
  test(
    'blocked prerequisite prevents starting Focus without task mutation',
    () async {
      final prerequisite = await tasks.createTask(
        const TaskDraft(title: 'Waiting', status: TaskStatus.waiting),
      );
      await tasks.relations.addDependency(taskId, prerequisite.id);
      await expectLater(controller.start(taskId), throwsArgumentError);
      expect(await repo.activeSession(), isNull);
      expect((await tasks.get(taskId))!.status, TaskStatus.planned);
    },
  );
  test('future split blocks remain until explicit confirmation, other tasks untouched', () async {
    final plans = PlannerRepository(db, schedules: WorkScheduleRepository(db));
    final today = DateTime(2026, 10, 5);
    final next = DateTime(2026, 10, 6);
    final other = await tasks.createTask(
      const TaskDraft(title: 'Other', status: TaskStatus.planned),
    );
    await plans.replaceUnlockedSuggestions(next, [
      PlannedBlock(
        id: 'future',
        taskId: taskId,
        start: DateTime(2026, 10, 6, 9),
        end: DateTime(2026, 10, 6, 10),
        isLocked: false,
        source: PlanBlockSource.suggested,
      ),
      PlannedBlock(
        id: 'other',
        taskId: other.id,
        start: DateTime(2026, 10, 6, 10),
        end: DateTime(2026, 10, 6, 11),
        isLocked: true,
        source: PlanBlockSource.manual,
      ),
    ]);
    await controller.start(taskId);
    now = now.add(const Duration(minutes: 1));
    await controller.complete();
    await plans.replaceUnlockedSuggestions(next, []);
    expect((await plans.day(next)).map((b) => b.id), ['future', 'other']);
    await repo.removeFutureBlocks(taskId, now);
    expect((await plans.day(next)).single.id, 'other');
    expect(await plans.day(today), isEmpty);
  });
  test('disk restart recovers running and paused timestamps', () async {
    final folder = await Directory.systemTemp.createTemp('quadrant-focus-');
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}/focus.sqlite';
    await db.close();
    var persisted = AppDatabase.open(path);
    final t = await TaskRepository(
      persisted,
    ).createTask(const TaskDraft(title: 'Recover', status: TaskStatus.planned));
    await FocusRepository(persisted).start(t.id, now);
    await persisted.close();
    persisted = AppDatabase.open(path);
    final recovered = FocusController(
      FocusRepository(persisted),
      clock: () => now.add(const Duration(minutes: 17)),
    );
    await recovered.recover();
    expect(recovered.elapsed.inSeconds, 1020);
    await recovered.pause();
    recovered.dispose();
    await persisted.close();
    persisted = AppDatabase.open(path);
    final paused = FocusController(
      FocusRepository(persisted),
      clock: () => now.add(const Duration(hours: 2)),
    );
    await paused.recover();
    expect(paused.session!.state, FocusSessionState.paused);
    expect(paused.elapsed.inSeconds, 1020);
    paused.dispose();
    await persisted.close();
  });
}

class _DelayedPriorReadRepository extends FocusRepository {
  final readStarted = Completer<void>();
  final release = Completer<void>();
  int reads = 0;
  _DelayedPriorReadRepository(super.db);
  @override
  Future<Duration> priorDuration(String taskId, String currentId) async {
    final result = await super.priorDuration(taskId, currentId);
    if (++reads == 2) {
      readStarted.complete();
      await release.future;
    }
    return result;
  }
}
