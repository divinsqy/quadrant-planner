import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/focus/focus_session.dart';
import '../../../domain/tasks/task_status.dart';
import '../../settings/data/work_schedule_repository.dart';
import '../../tasks/application/task_editor_controller.dart';
import '../../tasks/data/task_activity_repository.dart';
import '../../tasks/data/task_repository.dart';

class FocusRepository {
  final AppDatabase _db;
  final String Function() _idFactory;
  FocusRepository(this._db, {String Function()? idFactory})
    : _idFactory = idFactory ?? (() => const Uuid().v4());

  Future<FocusSession?> activeSession() async {
    final row = await (_db.select(
      _db.focusSessions,
    )..where((s) => s.state.isIn(['running', 'paused']))).getSingleOrNull();
    return row == null ? null : _session(row);
  }

  Stream<FocusSession?> watchActive() =>
      (_db.select(_db.focusSessions)
            ..where((s) => s.state.isIn(['running', 'paused'])))
          .watchSingleOrNull()
          .map((row) => row == null ? null : _session(row));
  Future<Duration> priorDuration(String taskId, String currentId) async {
    final rows =
        await (_db.select(_db.focusSessions)..where(
              (s) =>
                  s.taskId.equals(taskId) &
                  s.id.equals(currentId).not() &
                  s.endedAt.isNotNull(),
            ))
            .get();
    return rows.fold<Duration>(
      Duration.zero,
      (sum, row) => sum + _session(row).elapsed(row.endedAt!),
    );
  }

  Future<FocusSession> start(
    String taskId,
    DateTime at, {
    String? planBlockId,
  }) => _db.transaction(() async {
    if (await activeSession() != null) throw StateError('已有可恢复的专注会话，请先完成或标记阻塞');
    final tasks = TaskRepository(_db);
    final task = await tasks.get(taskId);
    if (task == null ||
        task.deletedAt != null ||
        (task.status != TaskStatus.planned &&
            task.status != TaskStatus.inProgress)) {
      throw ArgumentError('任务不可执行');
    }
    if ((await tasks.relations.blockedTaskIds()).contains(taskId)) {
      throw ArgumentError('前置任务尚未完成，无法开始专注');
    }
    if (planBlockId != null) {
      final block =
          await (_db.select(_db.dailyPlanBlocks)..where(
                (b) =>
                    b.id.equals(planBlockId) &
                    b.taskId.equals(taskId) &
                    b.completedAt.isNull(),
              ))
              .getSingleOrNull();
      if (block == null) throw ArgumentError('计划块不存在或已完成');
    }
    final utc = at.toUtc();
    final session = FocusSession(
      id: _idFactory(),
      taskId: taskId,
      planBlockId: planBlockId,
      state: FocusSessionState.running,
      startedAt: utc,
      intervals: [FocusInterval(start: utc)],
    );
    await _db
        .into(_db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: session.id,
            taskId: taskId,
            state: session.state.name,
            startedAt: utc,
            planBlockId: Value(planBlockId),
            intervalsJson: Value(_encode(session.intervals)),
          ),
        );
    await TaskEditorController(
      tasks: tasks,
      activity: TaskActivityRepository(_db),
      clock: () => utc,
    ).save(task, status: TaskStatus.inProgress);
    await _event(session, utc, 'focus_started');
    return session;
  });

  Future<FocusSession> pause(DateTime at) =>
      _transition(at, FocusSessionState.paused);
  Future<FocusSession> resume(DateTime at) =>
      _transition(at, FocusSessionState.running);
  Future<FocusSession> complete(
    DateTime at, {
    bool completeTask = true,
    bool removeFutureBlocks = false,
  }) => _transition(
    at,
    FocusSessionState.completed,
    completeTask: completeTask,
    removeFuture: removeFutureBlocks,
  );
  Future<FocusSession> markBlocked(DateTime at) =>
      _transition(at, FocusSessionState.blocked);

  Future<FocusSession> _transition(
    DateTime at,
    FocusSessionState next, {
    bool completeTask = false,
    bool removeFuture = false,
  }) => _db.transaction(() async {
    final current = await activeSession();
    if (current == null) throw StateError('没有可恢复的专注会话');
    if (next == FocusSessionState.paused &&
        current.state != FocusSessionState.running) {
      throw StateError('当前会话已暂停');
    }
    if (next == FocusSessionState.running &&
        current.state != FocusSessionState.paused) {
      throw StateError('当前会话未暂停');
    }
    final utc = at.toUtc();
    final previous = current.intervals.last;
    if (utc.isBefore(previous.end ?? previous.start)) {
      throw ArgumentError('操作时间不能早于上次会话时间');
    }
    if (removeFuture && !completeTask) throw ArgumentError('仅完成任务时才能清理后续计划');
    final intervals = [...current.intervals];
    if (current.state == FocusSessionState.running) {
      intervals[intervals.length - 1] = FocusInterval(
        start: previous.start,
        end: utc,
      );
    }
    if (next == FocusSessionState.running) {
      intervals.add(FocusInterval(start: utc));
    }
    final terminal =
        next == FocusSessionState.completed ||
        next == FocusSessionState.blocked;
    final session = FocusSession(
      id: current.id,
      taskId: current.taskId,
      planBlockId: current.planBlockId,
      state: next,
      startedAt: current.startedAt,
      endedAt: terminal ? utc : null,
      intervals: intervals,
    );
    await (_db.update(
      _db.focusSessions,
    )..where((s) => s.id.equals(session.id))).write(
      FocusSessionsCompanion(
        state: Value(next.name),
        endedAt: Value(session.endedAt),
        intervalsJson: Value(_encode(intervals)),
      ),
    );
    if (terminal) {
      final tasks = TaskRepository(_db);
      final task = await tasks.get(session.taskId);
      if (task == null) throw ArgumentError('任务不存在');
      final editor = TaskEditorController(
        tasks: tasks,
        activity: TaskActivityRepository(_db),
        clock: () => utc,
      );
      if (completeTask) await editor.complete(task);
      if (next == FocusSessionState.blocked) {
        await editor.save(task, status: TaskStatus.waiting);
      }
      if (next == FocusSessionState.completed && session.planBlockId != null) {
        await (_db.update(_db.dailyPlanBlocks)
              ..where((b) => b.id.equals(session.planBlockId!)))
            .write(DailyPlanBlocksCompanion(completedAt: Value(utc)));
      }
      if (removeFuture) await removeFutureBlocks(session.taskId, utc);
    }
    await _event(session, utc, switch (next) {
      FocusSessionState.running => 'focus_resumed',
      FocusSessionState.paused => 'focus_paused',
      FocusSessionState.completed => 'focus_completed',
      FocusSessionState.blocked => 'focus_blocked',
    });
    return session;
  });

  Future<int> futureBlockCount(String taskId, DateTime at) async =>
      (await _futureQuery(taskId, at).get()).length;
  SimpleSelectStatement<$DailyPlanBlocksTable, DailyPlanBlockRow> _futureQuery(
    String taskId,
    DateTime at,
  ) {
    final date = localDateKey(at);
    final local = at.toLocal();
    final minute = local.hour * 60 + local.minute;
    return _db.select(_db.dailyPlanBlocks)..where(
      (b) =>
          b.taskId.equals(taskId) &
          b.completedAt.isNull() &
          (b.localDate.isBiggerThanValue(date) |
              (b.localDate.equals(date) &
                  b.startMinutes.isBiggerOrEqualValue(minute))),
    );
  }

  Future<void> removeFutureBlocks(String taskId, DateTime at) =>
      _db.transaction(() async {
        final task = await TaskRepository(_db).get(taskId);
        if (task?.status != TaskStatus.completed) {
          throw ArgumentError('请先明确完成任务');
        }
        final rows = await _futureQuery(taskId, at).get();
        for (final row in rows) {
          await (_db.delete(
            _db.dailyPlanBlocks,
          )..where((b) => b.id.equals(row.id))).go();
        }
      });

  Future<void> _event(FocusSession session, DateTime at, String type) async {
    final seconds = session.elapsed(at).inSeconds;
    await TaskActivityRepository(_db).add(
      taskId: session.taskId,
      type: type,
      occurredAt: at,
      payload: {
        'sessionId': session.id,
        'planBlockId': session.planBlockId,
        'state': session.state.name,
        'startedAt': session.startedAt.toIso8601String(),
        'endedAt': session.endedAt?.toIso8601String(),
        'actualSeconds': seconds,
        'actualMinutes': seconds / 60,
        'intervals': jsonDecode(_encode(session.intervals)),
      },
    );
  }

  String _encode(List<FocusInterval> intervals) => jsonEncode(
    intervals
        .map(
          (i) => {
            'start': i.start.toUtc().toIso8601String(),
            'end': i.end?.toUtc().toIso8601String(),
          },
        )
        .toList(),
  );
  FocusSession _session(FocusSessionRow row) => FocusSession(
    id: row.id,
    taskId: row.taskId,
    planBlockId: row.planBlockId,
    state: FocusSessionState.values.byName(row.state),
    startedAt: row.startedAt.toUtc(),
    endedAt: row.endedAt?.toUtc(),
    intervals: (jsonDecode(row.intervalsJson) as List)
        .map(
          (i) => FocusInterval(
            start: DateTime.parse(i['start'] as String).toUtc(),
            end: i['end'] == null
                ? null
                : DateTime.parse(i['end'] as String).toUtc(),
          ),
        )
        .toList(),
  );
}
