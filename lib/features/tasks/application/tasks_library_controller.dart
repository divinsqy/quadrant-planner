import 'package:flutter/foundation.dart';

import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_status.dart';
import '../data/task_repository.dart';

const _unchanged = Object();

class TasksLibraryState {
  final String query;
  final Set<TaskStatus> statuses;
  final String? projectId;
  final String? tagId;
  final String? selectedTaskId;
  final double scrollOffset;

  const TasksLibraryState({
    this.query = '',
    this.statuses = const {},
    this.projectId,
    this.tagId,
    this.selectedTaskId,
    this.scrollOffset = 0,
  });
}

class TasksLibraryController extends ChangeNotifier {
  final TaskRepository tasks;
  TasksLibraryState _state;

  TasksLibraryController({required this.tasks, String? initialTagId})
    : _state = TasksLibraryState(tagId: initialTagId);
  TasksLibraryState get state => _state;

  void setFilters({
    String? query,
    Set<TaskStatus>? statuses,
    Object? projectId = _unchanged,
    Object? tagId = _unchanged,
  }) {
    _state = TasksLibraryState(
      query: query ?? _state.query,
      statuses: Set.unmodifiable(statuses ?? _state.statuses),
      projectId: identical(projectId, _unchanged)
          ? _state.projectId
          : projectId as String?,
      tagId: identical(tagId, _unchanged) ? _state.tagId : tagId as String?,
      selectedTaskId: _state.selectedTaskId,
      scrollOffset: _state.scrollOffset,
    );
    notifyListeners();
  }

  void selectTask(String? id) {
    _state = TasksLibraryState(
      query: _state.query,
      statuses: _state.statuses,
      projectId: _state.projectId,
      tagId: _state.tagId,
      selectedTaskId: id,
      scrollOffset: _state.scrollOffset,
    );
    notifyListeners();
  }

  void updateScrollOffset(double offset) {
    _state = TasksLibraryState(
      query: _state.query,
      statuses: _state.statuses,
      projectId: _state.projectId,
      tagId: _state.tagId,
      selectedTaskId: _state.selectedTaskId,
      scrollOffset: offset,
    );
  }

  Stream<List<Task>> watchTasks() => tasks.watchTasks(
    statuses: _state.statuses,
    projectId: _state.projectId,
    tagId: _state.tagId,
    query: _state.query,
  );
}
