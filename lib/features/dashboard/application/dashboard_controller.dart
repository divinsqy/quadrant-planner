import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/planning/planner_candidate.dart';
import '../../../domain/planning/planner_engine.dart';
import '../../../domain/planning/planner_ranker.dart';
import '../../../domain/planning/work_calendar.dart';
import '../../../domain/quadrant/quadrant_engine.dart';
import '../../../domain/settings/app_preferences.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/projects/project.dart';
import '../../projects/data/project_repository.dart';
import '../../tags/data/tag_repository.dart';
import '../../../domain/urgency/urgency_engine.dart';
import '../../settings/data/preferences_repository.dart';
import '../quadrant/quadrant_models.dart';
import '../../tasks/data/task_repository.dart';
import '../../../domain/planning/planned_block.dart';
import '../../planner/data/planner_repository.dart';
import '../../settings/data/work_schedule_repository.dart';

class DashboardState {
  final AppPreferences preferences;
  final List<TaskPlanningSnapshot> snapshots;
  final PlannerCandidate? currentRecommendation;
  final DayPlanSuggestion todayPlan;
  final String? selectedTaskId;
  final String? projectId;
  final bool listExpanded;
  final Map<String, Map<String, String>> taskMetadata;

  const DashboardState({
    required this.preferences,
    required this.snapshots,
    required this.currentRecommendation,
    required this.todayPlan,
    this.selectedTaskId,
    this.projectId,
    this.listExpanded = true,
    this.taskMetadata = const {},
  });

  factory DashboardState.initial() {
    return DashboardState(
      preferences: AppPreferences.defaults(),
      snapshots: const [],
      currentRecommendation: null,
      todayPlan: const DayPlanSuggestion(blocks: [], unscheduled: []),
    );
  }
}

class DashboardController extends ChangeNotifier {
  final TaskRepository tasks;
  final PreferencesRepository preferences;
  WorkCalendar calendar;
  final Stream<WorkCalendar>? calendars;
  final PlannerRepository? planner;
  final ProjectRepository? projects;
  final TagRepository? tags;
  final DateTime Function() _clock;
  final Stream<Set<String>>? blockedTaskIds;

  late UrgencyEngine _urgencyEngine = UrgencyEngine(calendar: calendar);
  final QuadrantEngine _quadrantEngine = const QuadrantEngine();
  late PlannerRanker _ranker = PlannerRanker(calendar: calendar);
  final PlannerEngine _plannerEngine = const PlannerEngine();

  StreamSubscription<List<Task>>? _taskSubscription;
  StreamSubscription<AppPreferences>? _preferencesSubscription;
  StreamSubscription<Set<String>>? _blockedSubscription;
  StreamSubscription<List<Project>>? _projectsSubscription;
  StreamSubscription<Map<String, List<String>>>? _tagsSubscription;
  StreamSubscription<WorkCalendar>? _calendarSubscription;
  StreamSubscription<List<PlannedBlock>>? _planSubscription;
  StreamSubscription<Map<String, String>>? _overrideSubscription;
  String? _watchedPlanDay;
  List<PlannedBlock> _planBlocks = const [];
  Map<String, String> _overrides = const {};
  Map<String, String> _projectNames = const {};
  Map<String, List<String>> _taskTags = const {};
  Set<String> _blocked = const {};
  bool _dependenciesReady;
  String? _selectedTaskId;
  String? _projectId;
  bool _listExpanded = true;
  List<Task> _tasks = const [];
  AppPreferences _preferences = AppPreferences.defaults();
  bool _started = false;

  DashboardState state = DashboardState.initial();

  DashboardController({
    required this.tasks,
    required this.preferences,
    required this.calendar,
    this.projects,
    this.tags,
    this.blockedTaskIds,
    this.calendars,
    this.planner,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _dependenciesReady = blockedTaskIds == null;

  String get greeting {
    final now = _clock();
    final prefix = switch (now.hour) {
      < 12 => '早上好',
      < 18 => '下午好',
      _ => '晚上好',
    };
    final nickname = state.preferences.nickname.trim();
    return nickname.isEmpty ? prefix : '$prefix，$nickname';
  }

  void start() {
    if (_started) {
      return;
    }
    _started = true;

    _calendarSubscription = calendars?.listen((value) {
      calendar = value;
      _urgencyEngine = UrgencyEngine(calendar: value);
      _ranker = PlannerRanker(calendar: value);
      _rebuild();
    });

    _taskSubscription = tasks.watchExecutableTasks().listen((value) {
      _tasks = value;
      _rebuild();
    });
    _preferencesSubscription = preferences.watch().listen((value) {
      _preferences = value;
      _rebuild();
    });
    _blockedSubscription = blockedTaskIds?.listen((value) {
      _blocked = value;
      _dependenciesReady = true;
      _rebuild();
    });
    _projectsSubscription = projects?.watchAll().listen((value) {
      _projectNames = {for (final project in value) project.id: project.name};
      _rebuild();
    });
    _tagsSubscription = tags?.watchTaskTags().listen((value) {
      _taskTags = value;
      _rebuild();
    });
  }

  DateTime get now => _clock();
  void refresh() => _rebuild();

  void selectTask(String? id) {
    _selectedTaskId = id;
    _rebuild();
  }

  void filterProject(String? id) {
    _projectId = id;
    _rebuild();
  }

  void setListExpanded(bool value) {
    _listExpanded = value;
    _rebuild();
  }

  Future<void> updateThresholds(QuadrantThresholds thresholds) async {
    final next = thresholds.clamped();
    await preferences.updateThresholds(
      importance: next.importance,
      urgency: next.urgency,
    );
  }

  void _rebuild() {
    final now = _clock();
    _watchPlanDay(now);
    final minute = now.hour * 60 + now.minute;
    final available = calendar.availableWindows(now);
    final currentSlotMinutes = available.fold<int>(0, (current, window) {
      return minute >= window.startMinutes && minute < window.endMinutes
          ? window.endMinutes - minute
          : current;
    });

    final visibleTasks = _tasks.where(
      (task) => _projectId == null || task.projectId == _projectId,
    );
    final snapshots = visibleTasks
        .map((task) {
          final urgency = _urgencyEngine.calculate(task, now);
          final quadrant = _quadrantEngine.classify(
            importance: task.importance,
            urgency: urgency.value,
            importanceThreshold: _preferences.importanceThreshold,
            urgencyThreshold: _preferences.urgencyThreshold,
          );
          final estimate = task.estimatedMinutes;
          return TaskPlanningSnapshot(
            task: task,
            currentUrgency: urgency.value,
            quadrant: quadrant,
            dependenciesSatisfied:
                _dependenciesReady && !_blocked.contains(task.id),
            milestoneWorkdaysRemaining: null,
            fitsCurrentSlot: estimate != null && estimate <= currentSlotMinutes,
          );
        })
        .toList(growable: false);
    if (!snapshots.any((s) => s.task.id == _selectedTaskId)) {
      _selectedTaskId = null;
    }

    final ranked = _ranker
        .rank(snapshots, now)
        .where((c) => _overrides[c.task.id] != 'skip')
        .toList();
    final order = {
      for (var i = 0; i < ranked.length; i++) ranked[i].task.id: i,
    };
    int priority(PlannerCandidate c) => switch (_overrides[c.task.id]) {
      'pin' => 0,
      'raise' => 1,
      _ => 2,
    };
    final candidates = [...ranked]
      ..sort((a, b) {
        final p = priority(a).compareTo(priority(b));
        return p == 0 ? order[a.task.id]!.compareTo(order[b.task.id]!) : p;
      });
    final todayPlan = planner != null
        ? DayPlanSuggestion(blocks: _planBlocks, unscheduled: const [])
        : _plannerEngine.planDay(
            date: now,
            schedule: calendar.schedule.withDateOverride(now, available),
            candidates: candidates,
            lockedBlocks: const [],
          );

    state = DashboardState(
      preferences: _preferences,
      snapshots: List.unmodifiable(snapshots),
      currentRecommendation: candidates.isEmpty ? null : candidates.first,
      todayPlan: todayPlan,
      selectedTaskId: _selectedTaskId,
      projectId: _projectId,
      listExpanded: _listExpanded,
      taskMetadata: Map.unmodifiable({
        for (final snapshot in snapshots)
          snapshot.task.id: Map<String, String>.unmodifiable({
            '项目': snapshot.task.projectId == null
                ? '无项目'
                : _projectNames[snapshot.task.projectId] ?? '项目',
            '标签': (_taskTags[snapshot.task.id] ?? []).isEmpty
                ? '无标签'
                : _taskTags[snapshot.task.id]!.join('、'),
            if (snapshot.task.deadline != null)
              '剩余工作日': calendar
                  .workdaysBetween(now, snapshot.task.deadline!.toLocal())
                  .count
                  .toString(),
            '依赖': snapshot.dependenciesSatisfied ? '已满足' : '等待前置任务完成',
          }),
      }),
    );
    notifyListeners();
  }

  void _watchPlanDay(DateTime now) {
    if (planner == null || _watchedPlanDay == localDateKey(now)) return;
    _watchedPlanDay = localDateKey(now);
    _planSubscription?.cancel();
    _overrideSubscription?.cancel();
    _planBlocks = const [];
    _overrides = const {};
    _planSubscription = planner!.watchDay(now).listen((value) {
      _planBlocks = value;
      _rebuild();
    });
    _overrideSubscription = planner!.watchOverrides(now).listen((value) {
      _overrides = value;
      _rebuild();
    });
  }

  @override
  void dispose() {
    _taskSubscription?.cancel();
    _preferencesSubscription?.cancel();
    _blockedSubscription?.cancel();
    _projectsSubscription?.cancel();
    _tagsSubscription?.cancel();
    _calendarSubscription?.cancel();
    _planSubscription?.cancel();
    _overrideSubscription?.cancel();
    super.dispose();
  }
}
