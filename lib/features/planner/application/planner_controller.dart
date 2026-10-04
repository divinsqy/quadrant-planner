import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/planning/planned_block.dart';
import '../../../domain/planning/planner_candidate.dart';
import '../../../domain/planning/planner_engine.dart';
import '../../../domain/planning/planner_ranker.dart';
import '../../../domain/planning/work_calendar.dart';
import '../../../domain/quadrant/quadrant_engine.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/urgency/urgency_engine.dart';
import '../../settings/data/preferences_repository.dart';
import '../../settings/data/work_schedule_repository.dart';
import '../../tasks/data/task_repository.dart';
import '../data/planner_repository.dart';

class PlannerController extends ChangeNotifier {
  final PlannerRepository plans;
  final TaskRepository tasks;
  final WorkScheduleRepository schedules;
  final PreferencesRepository preferences;
  final DateTime Function() _clock;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  late DateTime date;
  late WorkCalendar calendar;
  List<Task> taskList = const [];
  List<PlannedBlock> blocks = const [];
  List<PlannerCandidate> candidates = const [];
  Map<String, String> overrides = const {};
  DayPlanSuggestion suggestion = const DayPlanSuggestion(
    blocks: [],
    unscheduled: [],
  );
  bool busy = false;
  String? error;
  bool _started = false;
  bool _disposed = false;
  int _generation = 0;
  StreamSubscription<List<PlannedBlock>>? _daySubscription;
  StreamSubscription<Map<String, String>>? _overrideSubscription;

  PlannerController({
    required this.plans,
    required this.tasks,
    required this.schedules,
    required this.preferences,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    date = _day(_clock());
    calendar = schedules.baseCalendar;
  }
  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  Task? task(String id) {
    for (final t in taskList) {
      if (t.id == id) return t;
    }
    return null;
  }

  void start() {
    if (_started) return;
    _started = true;
    _subscriptions.add(tasks.watchTasks().listen((_) => refresh()));
    _subscriptions.add(
      tasks.relations.watchBlockedTaskIds().listen((_) => refresh()),
    );
    _subscriptions.add(preferences.watch().listen((_) => refresh()));
    _subscriptions.add(schedules.watchCalendar().listen((_) => refresh()));
    _subscriptions.add(plans.watchAllocationChanges().listen((_) => refresh()));
    _watchDay();
  }

  void _watchDay() {
    _daySubscription?.cancel();
    _overrideSubscription?.cancel();
    _daySubscription = plans.watchDay(date).listen((_) => refresh());
    _overrideSubscription = plans.watchOverrides(date).listen((_) => refresh());
    refresh();
  }

  void selectDate(DateTime next) {
    date = _day(next.toLocal());
    if (_started) _watchDay();
  }

  Future<void> refresh() async {
    final version = ++_generation;
    final selected = date;
    try {
      final input = await _load(selected);
      if (_disposed || version != _generation) return;
      _apply(input);
      error = null;
      notifyListeners();
    } catch (e) {
      if (_disposed || version != _generation) return;
      error = '$e';
      notifyListeners();
    }
  }

  Future<_PlannerInput> _load(DateTime selected) async {
    final all = await tasks.getTasks();
    final blocked = await tasks.relations.blockedTaskIds();
    final pref = await preferences.get();
    final cal = await schedules.getCalendar();
    final existing = await plans.day(selected);
    final actions = await plans.overridesForDay(selected);
    final completed = await plans.completedTaskIds();
    final active = await plans.activeFocusBlockIds();
    final kept = existing
        .where(
          (b) =>
              b.isLocked ||
              b.source == PlanBlockSource.manual ||
              b.completedAt != null ||
              active.contains(b.id) ||
              completed.contains(b.taskId),
        )
        .toList();
    final allocated = await plans.allocatedOutside(selected);
    for (final b in kept) {
      allocated[b.taskId] = (allocated[b.taskId] ?? 0) + b.durationMinutes;
    }
    final windows = cal.availableWindows(selected);
    final minute = _clock().hour * 60 + _clock().minute;
    final slot = windows.fold<int>(
      0,
      (n, w) => minute >= w.startMinutes && minute < w.endMinutes
          ? w.endMinutes - minute
          : n,
    );
    final urgency = UrgencyEngine(calendar: cal);
    final snapshots = all
        .where((t) => t.deletedAt == null && actions[t.id] != 'skip')
        .map(
          (t) => TaskPlanningSnapshot(
            task: t,
            currentUrgency: urgency.calculate(t, selected).value,
            quadrant: const QuadrantEngine().classify(
              importance: t.importance,
              urgency: urgency.calculate(t, selected).value,
              importanceThreshold: pref.importanceThreshold,
              urgencyThreshold: pref.urgencyThreshold,
            ),
            dependenciesSatisfied: !blocked.contains(t.id),
            milestoneWorkdaysRemaining: null,
            fitsCurrentSlot:
                t.estimatedMinutes != null && t.estimatedMinutes! <= slot,
          ),
        )
        .toList();
    final ranked = PlannerRanker(calendar: cal).rank(snapshots, selected);
    int priority(PlannerCandidate c) => switch (actions[c.task.id]) {
      'pin' => 0,
      'raise' => 1,
      _ => 2,
    };
    final ordered = [...ranked]
      ..sort((a, b) {
        final p = priority(a).compareTo(priority(b));
        return p == 0 ? ranked.indexOf(a).compareTo(ranked.indexOf(b)) : p;
      });
    final generated = const PlannerEngine().planDay(
      date: selected,
      schedule: cal.schedule.withDateOverride(selected, windows),
      candidates: ordered,
      lockedBlocks: kept.map((b) => b.copyWith(isLocked: true)).toList(),
      alreadyAllocatedMinutes: allocated,
    );
    final byId = {for (final b in kept) b.id: b};
    final generatedBlocks = generated.blocks
        .map(
          (b) =>
              byId[b.id] ??
              (actions[b.taskId] == 'pin'
                  ? b.copyWith(isLocked: true, source: PlanBlockSource.manual)
                  : b),
        )
        .toList();
    return _PlannerInput(
      cal,
      all,
      existing,
      actions,
      ordered,
      DayPlanSuggestion(
        blocks: generatedBlocks,
        unscheduled: generated.unscheduled,
      ),
    );
  }

  void _apply(_PlannerInput input) {
    calendar = input.calendar;
    taskList = input.tasks;
    blocks = input.blocks;
    overrides = input.overrides;
    candidates = input.candidates;
    suggestion = input.suggestion;
  }

  Future<void> replan() async {
    if (busy) throw StateError('规划正在保存');
    busy = true;
    if (!_disposed) notifyListeners();
    final selected = date;
    try {
      final input = await _load(selected);
      await plans.replaceUnlockedSuggestions(selected, input.suggestion.blocks);
      await refresh();
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> pin(String taskId) async {
    await plans.pinTask(taskId, date);
    await replan();
  }

  Future<void> skip(String taskId) async {
    await plans.skipTask(taskId, date);
    await replan();
  }

  Future<void> raisePriority(String taskId) async {
    await plans.raisePriority(taskId, date);
    await replan();
  }

  Future<void> defer(String taskId, DateTime until) async {
    await plans.skipTask(taskId, date);
    await plans.pinTask(taskId, until);
    await replan();
  }

  Future<void> move(String id, DateTime start, DateTime end) async {
    await plans.moveBlock(id, start, end);
    await refresh();
  }

  Future<void> reorder(String id, int direction) async {
    await plans.reorderBlock(id, direction);
    await refresh();
  }

  Future<void> lock(String id, bool locked) async {
    await plans.lockBlock(id, locked);
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _daySubscription?.cancel();
    _overrideSubscription?.cancel();
    super.dispose();
  }
}

class _PlannerInput {
  final WorkCalendar calendar;
  final List<Task> tasks;
  final List<PlannedBlock> blocks;
  final Map<String, String> overrides;
  final List<PlannerCandidate> candidates;
  final DayPlanSuggestion suggestion;
  const _PlannerInput(
    this.calendar,
    this.tasks,
    this.blocks,
    this.overrides,
    this.candidates,
    this.suggestion,
  );
}
