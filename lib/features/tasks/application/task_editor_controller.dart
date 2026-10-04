import 'dart:convert';

import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_status.dart';
import '../../../domain/tasks/workload.dart';
import '../data/task_activity_repository.dart';
import '../data/task_repository.dart';

const Object unchangedTaskField = Object();
const Object _unchanged = unchangedTaskField;

class TaskEditorController {
  final TaskRepository tasks;
  final TaskActivityRepository activity;
  final DateTime Function() _clock;

  TaskEditorController({
    required this.tasks,
    required this.activity,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  Future<Task> save(
    Task task, {
    String? title,
    String? description,
    TaskStatus? status,
    Object? projectId = _unchanged,
    Object? milestoneId = _unchanged,
    int? importance,
    int? baseUrgency,
    Object? deadline = _unchanged,
    Object? estimatedMinutes = _unchanged,
    Workload? workload,
    int? progress,
    bool? includeInWeeklyReport,
  }) {
    return _save(
      task,
      title: title,
      description: description,
      status: status,
      projectId: projectId,
      milestoneId: milestoneId,
      importance: importance,
      baseUrgency: baseUrgency,
      deadline: deadline,
      estimatedMinutes: estimatedMinutes,
      workload: workload,
      progress: progress,
      includeInWeeklyReport: includeInWeeklyReport,
      eventType: 'task_updated',
    );
  }

  Future<Task> complete(Task task) {
    return _save(
      task,
      status: TaskStatus.completed,
      progress: 100,
      eventType: 'completed',
    );
  }

  Future<Task> _save(
    Task task, {
    String? title,
    String? description,
    TaskStatus? status,
    Object? projectId = _unchanged,
    Object? milestoneId = _unchanged,
    int? importance,
    int? baseUrgency,
    Object? deadline = _unchanged,
    Object? estimatedMinutes = _unchanged,
    Workload? workload,
    int? progress,
    bool? includeInWeeklyReport,
    required String eventType,
  }) => tasks.transaction(() async {
    final current = await tasks.get(task.id) ?? task;
    final now = _clock().toUtc();
    final nextStatus = status ?? current.status;
    final nextBaseUrgency = baseUrgency ?? current.baseUrgency;
    final baseUrgencyChanged = nextBaseUrgency != current.baseUrgency;

    final nextDeadline = identical(deadline, _unchanged)
        ? current.deadline
        : deadline as DateTime?;
    final nextEstimate = identical(estimatedMinutes, _unchanged)
        ? current.estimatedMinutes
        : estimatedMinutes as int?;

    final completedAt = nextStatus == TaskStatus.completed
        ? (current.completedAt ?? now)
        : null;
    final nextProjectId = identical(projectId, _unchanged)
        ? current.projectId
        : projectId as String?;
    final nextMilestoneId = identical(milestoneId, _unchanged)
        ? (nextProjectId == current.projectId ? current.milestoneId : null)
        : milestoneId as String?;

    final next = current.copyWith(
      title: title,
      description: description,
      status: nextStatus,
      projectId: nextProjectId,
      milestoneId: nextMilestoneId,
      importance: importance,
      baseUrgency: nextBaseUrgency,
      baseUrgencyAnchorAt: baseUrgencyChanged
          ? now
          : current.baseUrgencyAnchorAt,
      deadline: nextDeadline,
      estimatedMinutes: nextEstimate,
      workload: workload,
      progress: nextStatus == TaskStatus.completed ? 100 : progress,
      includeInWeeklyReport: includeInWeeklyReport,
      updatedAt: now,
      completedAt: completedAt,
    );

    final changes = _changes(current, next);
    if (changes.isEmpty) {
      return current;
    }

    await tasks.save(next);
    await activity.add(
      taskId: next.id,
      type: eventType,
      occurredAt: now,
      payload: {'changes': changes},
    );
    return next;
  });

  Map<String, dynamic> _changes(Task before, Task after) {
    final changes = <String, dynamic>{};

    void add(String key, Object? oldValue, Object? newValue) {
      final oldEncoded = _encode(oldValue);
      final newEncoded = _encode(newValue);
      if (jsonEncode(oldEncoded) == jsonEncode(newEncoded)) {
        return;
      }
      changes[key] = {'before': oldEncoded, 'after': newEncoded};
    }

    add('title', before.title, after.title);
    add('description', before.description, after.description);
    add('status', before.status, after.status);
    add('projectId', before.projectId, after.projectId);
    add('milestoneId', before.milestoneId, after.milestoneId);
    add('importance', before.importance, after.importance);
    add('baseUrgency', before.baseUrgency, after.baseUrgency);
    add(
      'baseUrgencyAnchorAt',
      before.baseUrgencyAnchorAt,
      after.baseUrgencyAnchorAt,
    );
    add('deadline', before.deadline, after.deadline);
    add('estimatedMinutes', before.estimatedMinutes, after.estimatedMinutes);
    add('workload', before.workload, after.workload);
    add('progress', before.progress, after.progress);
    add(
      'includeInWeeklyReport',
      before.includeInWeeklyReport,
      after.includeInWeeklyReport,
    );
    add('completedAt', before.completedAt, after.completedAt);
    return changes;
  }

  Object? _encode(Object? value) {
    return switch (value) {
      DateTime date => date.toUtc().toIso8601String(),
      TaskStatus status => status.name,
      Workload workload => workload.name,
      _ => value,
    };
  }
}
