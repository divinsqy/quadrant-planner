import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/projects/milestone.dart';
import '../../../domain/projects/project.dart';
import '../../../domain/projects/project_progress.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_status.dart';
import '../../tasks/data/task_repository.dart';
import '../data/project_repository.dart';

class ProjectTimelineEntry {
  final DateTime date;
  final String title;
  final String kind;
  final String? taskId;
  final String? milestoneId;

  const ProjectTimelineEntry({
    required this.date,
    required this.title,
    required this.kind,
    this.taskId,
    this.milestoneId,
  });
}

class ProjectState {
  final Project? project;
  final List<Task> tasks;
  final List<Milestone> milestones;
  final bool isLoading;
  final String? error;
  final bool isSaving;

  const ProjectState({
    this.project,
    this.tasks = const [],
    this.milestones = const [],
    this.isLoading = true,
    this.error,
    this.isSaving = false,
  });

  double get progress => calculateProjectProgress(tasks);

  List<Task> milestoneTasks(String milestoneId) => tasks
      .where((task) => task.milestoneId == milestoneId)
      .toList(growable: false);

  List<ProjectTimelineEntry> get timeline {
    final items = <ProjectTimelineEntry>[];
    final currentProject = project;
    if (currentProject != null) {
      items.add(
        ProjectTimelineEntry(
          date: currentProject.createdAt,
          title: currentProject.name,
          kind: '项目创建',
        ),
      );
      if (currentProject.deadline != null) {
        items.add(
          ProjectTimelineEntry(
            date: currentProject.deadline!,
            title: currentProject.name,
            kind: '项目截止',
          ),
        );
      }
    }
    for (final milestone in milestones) {
      if (milestone.deadline != null) {
        items.add(
          ProjectTimelineEntry(
            date: milestone.deadline!,
            title: milestone.name,
            kind: '里程碑截止',
            milestoneId: milestone.id,
          ),
        );
      }
      if (milestone.completedAt != null) {
        items.add(
          ProjectTimelineEntry(
            date: milestone.completedAt!,
            title: milestone.name,
            kind: '里程碑完成',
            milestoneId: milestone.id,
          ),
        );
      }
    }
    for (final task in tasks) {
      if (task.status == TaskStatus.cancelled) {
        continue;
      }
      items.add(
        ProjectTimelineEntry(
          date: task.createdAt,
          title: task.title,
          kind: '任务创建',
          taskId: task.id,
        ),
      );
      if (task.deadline != null) {
        items.add(
          ProjectTimelineEntry(
            date: task.deadline!,
            title: task.title,
            kind: '任务截止',
            taskId: task.id,
          ),
        );
      }
      if (task.completedAt != null) {
        items.add(
          ProjectTimelineEntry(
            date: task.completedAt!,
            title: task.title,
            kind: '任务完成',
            taskId: task.id,
          ),
        );
      }
    }
    items.sort((a, b) {
      final dateOrder = a.date.compareTo(b.date);
      return dateOrder != 0 ? dateOrder : a.title.compareTo(b.title);
    });
    return List.unmodifiable(items);
  }
}

class ProjectController extends ChangeNotifier {
  final String projectId;
  final ProjectRepository projects;
  final TaskRepository tasks;
  final DateTime Function() _clock;
  StreamSubscription<Project?>? _projectSubscription;
  StreamSubscription<List<Task>>? _tasksSubscription;
  StreamSubscription<List<Milestone>>? _milestonesSubscription;
  Project? _project;
  List<Task> _tasks = const [];
  List<Milestone> _milestones = const [];
  bool _projectLoaded = false;
  bool _tasksLoaded = false;
  bool _milestonesLoaded = false;
  bool _started = false;
  bool _disposed = false;
  bool _saving = false;
  String? _error;
  ProjectState state = const ProjectState();

  ProjectController({
    required this.projectId,
    required this.projects,
    required this.tasks,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _projectSubscription = projects.watchProject(projectId).listen((project) {
      _project = project;
      _projectLoaded = true;
      _publish();
    }, onError: _streamError);
    _tasksSubscription = tasks.watchTasks().listen((items) {
      _tasks = items
          .where((task) => task.projectId == projectId)
          .toList(growable: false);
      _tasksLoaded = true;
      _publish();
    }, onError: _streamError);
    _milestonesSubscription = projects.watchMilestones(projectId).listen((
      items,
    ) {
      _milestones = items;
      _milestonesLoaded = true;
      _publish();
    }, onError: _streamError);
  }

  Future<Project> saveProject({
    required String name,
    required String objective,
    DateTime? deadline,
  }) => _mutate(() async {
    final current = await projects.get(projectId);
    if (current == null) {
      throw StateError('项目不存在');
    }
    final next = Project(
      id: current.id,
      name: name.trim(),
      objective: objective,
      deadline: deadline,
      createdAt: current.createdAt,
      updatedAt: _clock().toUtc(),
      deletedAt: current.deletedAt,
    );
    await projects.save(next);
    return next;
  });

  Future<Milestone> createMilestone({
    required String name,
    DateTime? deadline,
  }) => _mutate(
    () => projects.createMilestone(
      projectId: projectId,
      name: name,
      deadline: deadline,
    ),
  );

  Future<Milestone> saveMilestone(
    Milestone milestone, {
    required String name,
    DateTime? deadline,
  }) => _mutate(() async {
    final current = await _currentMilestone(milestone.id);
    final next = Milestone(
      id: current.id,
      projectId: current.projectId,
      name: name.trim(),
      deadline: deadline,
      completedAt: current.completedAt,
      createdAt: current.createdAt,
      updatedAt: _clock().toUtc(),
    );
    await projects.saveMilestone(next);
    return next;
  });

  Future<void> setMilestoneCompleted(Milestone milestone, bool completed) =>
      _mutate(() async {
        final current = await _currentMilestone(milestone.id);
        final now = _clock().toUtc();
        await projects.saveMilestone(
          Milestone(
            id: current.id,
            projectId: current.projectId,
            name: current.name,
            deadline: current.deadline,
            completedAt: completed ? (current.completedAt ?? now) : null,
            createdAt: current.createdAt,
            updatedAt: now,
          ),
        );
      });

  Future<Milestone> _currentMilestone(String id) async {
    final milestone = await projects.getMilestone(id);
    if (milestone == null || milestone.projectId != projectId) {
      throw StateError('里程碑不存在');
    }
    return milestone;
  }

  Future<T> _mutate<T>(Future<T> Function() action) async {
    _saving = true;
    _error = null;
    _publish();
    try {
      return await action();
    } catch (error) {
      _error = '保存失败：$error';
      rethrow;
    } finally {
      _saving = false;
      _publish();
    }
  }

  void _streamError(Object error) {
    _error = '加载失败：$error';
    _publish();
  }

  void _publish() {
    if (_disposed) {
      return;
    }
    state = ProjectState(
      project: _project,
      tasks: List.unmodifiable(_tasks),
      milestones: List.unmodifiable(_milestones),
      isLoading: !_projectLoaded || !_tasksLoaded || !_milestonesLoaded,
      error: _error,
      isSaving: _saving,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_projectSubscription?.cancel());
    unawaited(_tasksSubscription?.cancel());
    unawaited(_milestonesSubscription?.cancel());
    super.dispose();
  }
}
