import 'dart:ui';

import '../../../domain/planning/planner_candidate.dart';
import '../../../domain/tasks/task_status.dart';
import '../../../domain/tasks/workload.dart';

enum QuadrantPointWorkload {
  small,
  medium,
  large,
}

class QuadrantThresholds {
  final int urgency;
  final int importance;

  const QuadrantThresholds({
    required this.urgency,
    required this.importance,
  });

  QuadrantThresholds clamped() {
    return QuadrantThresholds(
      urgency: urgency.clamp(0, 100).toInt(),
      importance: importance.clamp(0, 100).toInt(),
    );
  }

  QuadrantThresholds copyWith({
    int? urgency,
    int? importance,
  }) {
    return QuadrantThresholds(
      urgency: urgency ?? this.urgency,
      importance: importance ?? this.importance,
    ).clamped();
  }

  @override
  bool operator ==(Object other) {
    return other is QuadrantThresholds &&
        other.urgency == urgency &&
        other.importance == importance;
  }

  @override
  int get hashCode => Object.hash(urgency, importance);
}

class QuadrantTaskPoint {
  final String id;
  final String title;
  final String description;
  final String? projectId;
  final int urgency;
  final int importance;
  final QuadrantPointWorkload workload;
  final String statusLabel;
  final Map<String, String> metadata;

  const QuadrantTaskPoint({
    required this.id,
    required this.title,
    this.description = '',
    required this.projectId,
    required this.urgency,
    required this.importance,
    required this.workload,
    required this.statusLabel,
    required this.metadata,
  });

  factory QuadrantTaskPoint.fromSnapshot(TaskPlanningSnapshot snapshot) {
    final task = snapshot.task;
    return QuadrantTaskPoint(
      id: task.id,
      title: task.title,
      description: task.description,
      projectId: task.projectId,
      urgency: snapshot.currentUrgency,
      importance: task.importance,
      workload: switch (task.workload) {
        Workload.small => QuadrantPointWorkload.small,
        Workload.medium => QuadrantPointWorkload.medium,
        Workload.large => QuadrantPointWorkload.large,
      },
      statusLabel: _statusLabel(task.status),
      metadata: {
        if (task.deadline != null) '截止': _dateLabel(task.deadline!.toLocal()),
        if (task.estimatedMinutes != null)
          '预计': '${task.estimatedMinutes} min',
        '状态': _statusLabel(task.status),
      },
    );
  }

  static String _statusLabel(TaskStatus status) {
    return switch (status) {
      TaskStatus.inbox => '收集箱',
      TaskStatus.planned => '已规划',
      TaskStatus.inProgress => '进行中',
      TaskStatus.waiting => '等待中',
      TaskStatus.completed => '已完成',
      TaskStatus.cancelled => '已取消',
    };
  }

  static String _dateLabel(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class QuadrantCluster {
  final List<QuadrantTaskPoint> members;
  final Offset screenCenter;

  const QuadrantCluster({
    required this.members,
    required this.screenCenter,
  });

  bool get isCluster => members.length > 1;
}
