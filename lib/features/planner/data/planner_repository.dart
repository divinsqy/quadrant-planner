import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/planning/planned_block.dart';
import '../../../domain/tasks/task_status.dart';
import '../../settings/data/work_schedule_repository.dart';

class PlannerRepository {
  final AppDatabase _db;
  final WorkScheduleRepository schedules;
  PlannerRepository(this._db, {required this.schedules});

  Stream<List<PlannedBlock>> watchDay(DateTime date) =>
      (_db.select(_db.dailyPlanBlocks)
            ..where((b) => b.localDate.equals(localDateKey(date)))
            ..orderBy([
              (b) => OrderingTerm.asc(b.startMinutes),
              (b) => OrderingTerm.asc(b.id),
            ]))
          .watch()
          .map((rows) => rows.map(_block).toList(growable: false));
  Future<List<PlannedBlock>> day(DateTime date) async {
    final rows =
        await (_db.select(_db.dailyPlanBlocks)
              ..where((b) => b.localDate.equals(localDateKey(date)))
              ..orderBy([
                (b) => OrderingTerm.asc(b.startMinutes),
                (b) => OrderingTerm.asc(b.id),
              ]))
            .get();
    return rows.map(_block).toList(growable: false);
  }

  Stream<Map<String, String>> watchOverrides(DateTime date) =>
      (_db.select(_db.plannerTaskOverrides)
            ..where((r) => r.localDate.equals(localDateKey(date))))
          .watch()
          .map((rows) => {for (final row in rows) row.taskId: row.action});
  Future<Map<String, String>> overridesForDay(DateTime date) async {
    final rows = await (_db.select(
      _db.plannerTaskOverrides,
    )..where((r) => r.localDate.equals(localDateKey(date)))).get();
    return {for (final row in rows) row.taskId: row.action};
  }

  Future<Set<String>> completedTaskIds() async =>
      (await (_db.select(
            _db.tasks,
          )..where((t) => t.status.equals(TaskStatus.completed.name))).get())
          .map((t) => t.id)
          .toSet();
  Stream<void> watchAllocationChanges() => _db
      .customSelect(
        'SELECT id FROM daily_plan_blocks UNION ALL SELECT id FROM focus_sessions',
        readsFrom: {_db.dailyPlanBlocks, _db.focusSessions},
      )
      .watch()
      .map((_) {});

  Future<Set<String>> activeFocusBlockIds() async =>
      (await (_db.select(_db.focusSessions)..where(
                (s) =>
                    s.state.isIn(['running', 'paused']) &
                    s.planBlockId.isNotNull(),
              ))
              .get())
          .map((s) => s.planBlockId!)
          .toSet();

  Future<Map<String, int>> allocatedOutside(DateTime date) async {
    final rows = await (_db.select(
      _db.dailyPlanBlocks,
    )..where((b) => b.localDate.equals(localDateKey(date)).not())).get();
    final minutes = <String, int>{};
    for (final b in rows) {
      minutes[b.taskId] =
          (minutes[b.taskId] ?? 0) + b.endMinutes - b.startMinutes;
    }
    return minutes;
  }

  Future<void> replaceUnlockedSuggestions(
    DateTime date,
    List<PlannedBlock> blocks,
  ) => _db.transaction(() async {
    final old = await day(date);
    final completed = await completedTaskIds();
    final active = await activeFocusBlockIds();
    final kept = old
        .where(
          (b) =>
              b.isLocked ||
              b.source == PlanBlockSource.manual ||
              b.completedAt != null ||
              active.contains(b.id) ||
              completed.contains(b.taskId),
        )
        .toList();
    final keptIds = kept.map((b) => b.id).toSet();
    final skipped = await overridesForDay(date);
    final next = blocks
        .where((b) => !keptIds.contains(b.id) && skipped[b.taskId] != 'skip')
        .toList();
    await _validate(date, next, kept);
    for (final b in old.where((b) => !keptIds.contains(b.id))) {
      await (_db.delete(
        _db.dailyPlanBlocks,
      )..where((r) => r.id.equals(b.id))).go();
    }
    for (final b in next) {
      await _insert(b);
    }
  });

  Future<void> _validate(
    DateTime date,
    List<PlannedBlock> next,
    List<PlannedBlock> kept,
  ) async {
    final windows = (await schedules.getCalendar()).availableWindows(
      date.toLocal(),
    );
    for (final b in next) {
      final start = b.start.toLocal();
      final end = b.end.toLocal();
      final s = start.hour * 60 + start.minute;
      final e = _endMinute(b);
      final endsAtMidnight =
          end.hour == 0 &&
          end.minute == 0 &&
          localDateKey(end) ==
              localDateKey(DateTime(start.year, start.month, start.day + 1));
      if (localDateKey(start) != localDateKey(date) ||
          (localDateKey(end) != localDateKey(date) && !endsAtMidnight) ||
          !end.isAfter(start) ||
          start.second != 0 ||
          end.second != 0 ||
          start.millisecond != 0 ||
          end.millisecond != 0 ||
          start.microsecond != 0 ||
          end.microsecond != 0 ||
          (s < 840 && e > 720) ||
          !windows.any((w) => s >= w.startMinutes && e <= w.endMinutes)) {
        throw ArgumentError('计划块必须位于当天工作时段内，不能跨午休或不可用日期');
      }
      final task =
          await (_db.select(_db.tasks)
                ..where((t) => t.id.equals(b.taskId) & t.deletedAt.isNull()))
              .getSingleOrNull();
      if (task == null ||
          (task.status != 'planned' && task.status != 'inProgress')) {
        throw ArgumentError('任务不可执行');
      }
      if (b.source == PlanBlockSource.suggested &&
          (task.estimatedMinutes ?? 0) >= 60 &&
          b.durationMinutes < 30) {
        throw ArgumentError('自动拆分的每个时间块至少30分钟');
      }
      final prerequisite = _db.alias(_db.tasks, 'prerequisite');
      final blocked =
          await (_db.select(_db.dependencies).join([
                innerJoin(
                  prerequisite,
                  prerequisite.id.equalsExp(_db.dependencies.dependsOnTaskId),
                ),
              ])..where(
                _db.dependencies.taskId.equals(b.taskId) &
                    prerequisite.status.equals('completed').not(),
              ))
              .get();
      if (blocked.isNotEmpty) throw ArgumentError('任务的前置依赖尚未完成');
    }
    final sorted = [...kept, ...next]
      ..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].start.isBefore(sorted[i - 1].end)) {
        throw ArgumentError('计划块不能重叠');
      }
    }
    if (sorted.map((b) => b.id).toSet().length != sorted.length) {
      throw ArgumentError('计划块 ID 重复');
    }
  }

  Future<void> lockBlock(String id, bool locked) => _db.transaction(() async {
    await _require(id);
    await (_db.update(_db.dailyPlanBlocks)..where((b) => b.id.equals(id)))
        .write(DailyPlanBlocksCompanion(isLocked: Value(locked)));
  });
  Future<void> moveBlock(String id, DateTime start, DateTime end) =>
      _db.transaction(() async {
        final b = _block(await _require(id));
        if (b.isLocked || b.completedAt != null) {
          throw ArgumentError('请先解锁；已完成时间块不能移动');
        }
        final moved = b.copyWith(
          start: start,
          end: end,
          source: PlanBlockSource.manual,
        );
        await _validate(b.start, [
          moved,
        ], (await day(b.start)).where((other) => other.id != id).toList());
        await _writeMoved(moved);
      });

  Future<void> reorderBlock(String id, int direction) => _db.transaction(
    () async {
      if (direction != -1 && direction != 1) throw ArgumentError('请选择向前或向后移动');
      final b = _block(await _require(id));
      final rows = await day(b.start);
      final i = rows.indexWhere((r) => r.id == id);
      final j = i + direction;
      if (j < 0 || j >= rows.length) return;
      final other = rows[j];
      if (b.isLocked ||
          other.isLocked ||
          b.completedAt != null ||
          other.completedAt != null) {
        throw ArgumentError('锁定或完成的时间块不能重排');
      }
      final earlier = direction < 0 ? other : b;
      final later = direction < 0 ? b : other;
      if (earlier.end != later.start) throw ArgumentError('非相邻连续时段请使用修改时间');
      final first = later.copyWith(
        start: earlier.start,
        end: earlier.start.add(Duration(minutes: later.durationMinutes)),
        source: PlanBlockSource.manual,
      );
      final second = earlier.copyWith(
        start: first.end,
        end: first.end.add(Duration(minutes: earlier.durationMinutes)),
        source: PlanBlockSource.manual,
      );
      await _validate(b.start, [
        first,
        second,
      ], rows.where((r) => r.id != b.id && r.id != other.id).toList());
      await _writeMoved(first);
      await _writeMoved(second);
    },
  );

  Future<void> pinTask(String id, DateTime date) => _override(id, date, 'pin');
  Future<void> skipTask(String id, DateTime date) =>
      _override(id, date, 'skip');
  Future<void> raisePriority(String id, DateTime date) =>
      _override(id, date, 'raise');
  Future<void> deferTask(String id, DateTime date) async {
    await skipTask(id, date);
  }

  Future<void> clearOverride(String id, DateTime date) =>
      (_db.delete(_db.plannerTaskOverrides)..where(
            (r) => r.localDate.equals(localDateKey(date)) & r.taskId.equals(id),
          ))
          .go();
  Future<void> _override(String id, DateTime date, String action) =>
      _db.transaction(() async {
        final key = localDateKey(date);
        if (action == 'skip') {
          final active = await activeFocusBlockIds();
          if ((await day(date))
              .any((b) => b.taskId == id && active.contains(b.id))) {
            throw StateError('请先完成或标记阻塞当前专注，再跳过该计划');
          }
        }
        await _db
            .into(_db.plannerTaskOverrides)
            .insertOnConflictUpdate(
              PlannerTaskOverridesCompanion.insert(
                localDate: key,
                taskId: id,
                action: action,
              ),
            );
        if (action == 'skip') {
          await (_db.delete(_db.dailyPlanBlocks)..where(
                (b) =>
                    b.taskId.equals(id) &
                    b.localDate.equals(key) &
                    b.completedAt.isNull(),
              ))
              .go();
        } else if (action == 'pin') {
          await (_db.update(
            _db.dailyPlanBlocks,
          )..where((b) => b.taskId.equals(id) & b.localDate.equals(key))).write(
            const DailyPlanBlocksCompanion(
              isLocked: Value(true),
              source: Value('manual'),
            ),
          );
        }
      });
  Future<DailyPlanBlockRow> _require(String id) async {
    final row = await (_db.select(
      _db.dailyPlanBlocks,
    )..where((b) => b.id.equals(id))).getSingleOrNull();
    if (row == null) throw ArgumentError('计划块不存在');
    return row;
  }

  Future<void> _writeMoved(PlannedBlock b) =>
      (_db.update(_db.dailyPlanBlocks)..where((r) => r.id.equals(b.id))).write(
        DailyPlanBlocksCompanion(
          startMinutes: Value(_startMinute(b)),
          endMinutes: Value(_endMinute(b)),
          source: Value(b.source.name),
        ),
      );
  Future<void> _insert(PlannedBlock b) => _db
      .into(_db.dailyPlanBlocks)
      .insert(
        DailyPlanBlocksCompanion.insert(
          id: b.id,
          localDate: localDateKey(b.start),
          taskId: b.taskId,
          startMinutes: _startMinute(b),
          endMinutes: _endMinute(b),
          isLocked: Value(b.isLocked),
          source: Value(b.source.name),
          completedAt: Value(b.completedAt),
        ),
      );
  PlannedBlock _block(DailyPlanBlockRow row) {
    final date = DateTime.parse(row.localDate);
    return PlannedBlock(
      id: row.id,
      taskId: row.taskId,
      start: date.add(Duration(minutes: row.startMinutes)),
      end: date.add(Duration(minutes: row.endMinutes)),
      isLocked: row.isLocked,
      source: PlanBlockSource.values.byName(row.source),
      completedAt: row.completedAt?.toUtc(),
    );
  }

  int _startMinute(PlannedBlock b) =>
      b.start.toLocal().hour * 60 + b.start.toLocal().minute;
  int _endMinute(PlannedBlock b) => localDateKey(b.start) != localDateKey(b.end)
      ? 1440
      : b.end.toLocal().hour * 60 + b.end.toLocal().minute;
}
