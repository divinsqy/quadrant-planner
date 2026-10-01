import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/planning/planner_candidate.dart';
import '../../../domain/planning/planner_engine.dart';
import '../../../domain/planning/planner_ranker.dart';
import '../../../domain/planning/work_calendar.dart';
import '../../../domain/quadrant/quadrant_engine.dart';
import '../../../domain/settings/app_preferences.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/urgency/urgency_engine.dart';
import '../../settings/data/preferences_repository.dart';
import '../quadrant/quadrant_models.dart';
import '../../tasks/data/task_repository.dart';

class DashboardState {
  final AppPreferences preferences;
  final List<TaskPlanningSnapshot> snapshots;
  final PlannerCandidate? currentRecommendation;
  final DayPlanSuggestion todayPlan;

  const DashboardState({
    required this.preferences,
    required this.snapshots,
    required this.currentRecommendation,
    required this.todayPlan,
  });

  factory DashboardState.initial() {
    return DashboardState(
      preferences: AppPreferences.defaults(),
      snapshots: const [],
      currentRecommendation: null,
      todayPlan: const DayPlanSuggestion(
        blocks: [],
        unscheduled: [],
      ),
    );
  }
}

class DashboardController extends ChangeNotifier {
  final TaskRepository tasks;
  final PreferencesRepository preferences;
  final WorkCalendar calendar;
  final DateTime Function() _clock;

  late final UrgencyEngine _urgencyEngine = UrgencyEngine(calendar: calendar);
  final QuadrantEngine _quadrantEngine = const QuadrantEngine();
  late final PlannerRanker _ranker = PlannerRanker(calendar: calendar);
  final PlannerEngine _plannerEngine = const PlannerEngine();

  StreamSubscription<List<Task>>? _taskSubscription;
  StreamSubscription<AppPreferences>? _preferencesSubscription;
  List<Task> _tasks = const [];
  AppPreferences _preferences = AppPreferences.defaults();
  bool _started = false;

  DashboardState state = DashboardState.initial();

  DashboardController({
    required this.tasks,
    required this.preferences,
    required this.calendar,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

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

    _taskSubscription = tasks.watchExecutableTasks().listen((value) {
      _tasks = value;
      _rebuild();
    });
    _preferencesSubscription = preferences.watch().listen((value) {
      _preferences = value;
      _rebuild();
    });
  }

  Future<void> updateThresholds(QuadrantThresholds thresholds) async {
    final next = thresholds.clamped();
    await preferences.save(
      AppPreferences(
        nickname: _preferences.nickname,
        importanceThreshold: next.importance,
        urgencyThreshold: next.urgency,
      ),
    );
  }

  void _rebuild() {
    final now = _clock();
    final available = calendar.availableWindows(now);
    final largestWindow = available.fold<int>(
      0,
      (current, window) =>
          window.durationMinutes > current ? window.durationMinutes : current,
    );

    final snapshots = _tasks.map((task) {
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
        dependenciesSatisfied: true,
        milestoneWorkdaysRemaining: null,
        fitsCurrentSlot: estimate != null && estimate <= largestWindow,
      );
    }).toList(growable: false);

    final candidates = _ranker.rank(snapshots, now);
    final todayPlan = _plannerEngine.planDay(
      date: now,
      schedule: calendar.schedule,
      candidates: candidates,
      lockedBlocks: const [],
    );

    state = DashboardState(
      preferences: _preferences,
      snapshots: List.unmodifiable(snapshots),
      currentRecommendation: candidates.isEmpty ? null : candidates.first,
      todayPlan: todayPlan,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _taskSubscription?.cancel();
    _preferencesSubscription?.cancel();
    super.dispose();
  }
}
