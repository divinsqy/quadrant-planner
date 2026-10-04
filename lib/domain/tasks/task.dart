import 'task_status.dart';
import 'workload.dart';

const Object _unchanged = Object();

class Task {
  final String id;
  final String title;
  final String description;
  final TaskStatus status;
  final String? projectId;
  final String? milestoneId;
  final int importance;
  final int baseUrgency;
  final DateTime baseUrgencyAnchorAt;
  final DateTime? deadline;
  final int? estimatedMinutes;
  final Workload workload;
  final int progress;
  final bool includeInWeeklyReport;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime? deletedAt;

  const Task._({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.projectId,
    required this.milestoneId,
    required this.importance,
    required this.baseUrgency,
    required this.baseUrgencyAnchorAt,
    required this.deadline,
    required this.estimatedMinutes,
    required this.workload,
    required this.progress,
    required this.includeInWeeklyReport,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
    required this.deletedAt,
  });

  factory Task.create({
    required String id,
    required String title,
    required String description,
    required TaskStatus status,
    required String? projectId,
    String? milestoneId,
    required int importance,
    required int baseUrgency,
    required DateTime baseUrgencyAnchorAt,
    required DateTime? deadline,
    required int? estimatedMinutes,
    required Workload workload,
    required int progress,
    required bool includeInWeeklyReport,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? completedAt,
    DateTime? deletedAt,
  }) {
    final cleanedId = id.trim();
    final cleanedTitle = title.trim();
    if (cleanedId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (cleanedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
    _requireScore('importance', importance);
    _requireScore('baseUrgency', baseUrgency);
    _requireScore('progress', progress);
    if (estimatedMinutes != null && estimatedMinutes <= 0) {
      throw ArgumentError.value(
        estimatedMinutes,
        'estimatedMinutes',
        'must be positive when provided',
      );
    }

    return Task._(
      id: cleanedId,
      title: cleanedTitle,
      description: description,
      status: status,
      projectId: projectId,
      milestoneId: milestoneId,
      importance: importance,
      baseUrgency: baseUrgency,
      baseUrgencyAnchorAt: baseUrgencyAnchorAt.toUtc(),
      deadline: deadline?.toUtc(),
      estimatedMinutes: estimatedMinutes,
      workload: workload,
      progress: progress,
      includeInWeeklyReport: includeInWeeklyReport,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      completedAt: completedAt?.toUtc(),
      deletedAt: deletedAt?.toUtc(),
    );
  }

  Task copyWith({
    String? title,
    String? description,
    TaskStatus? status,
    Object? projectId = _unchanged,
    Object? milestoneId = _unchanged,
    int? importance,
    int? baseUrgency,
    DateTime? baseUrgencyAnchorAt,
    Object? deadline = _unchanged,
    Object? estimatedMinutes = _unchanged,
    Workload? workload,
    int? progress,
    bool? includeInWeeklyReport,
    DateTime? updatedAt,
    Object? completedAt = _unchanged,
    Object? deletedAt = _unchanged,
  }) {
    return Task.create(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      projectId: identical(projectId, _unchanged)
          ? this.projectId
          : projectId as String?,
      milestoneId: identical(milestoneId, _unchanged)
          ? this.milestoneId
          : milestoneId as String?,
      importance: importance ?? this.importance,
      baseUrgency: baseUrgency ?? this.baseUrgency,
      baseUrgencyAnchorAt: baseUrgencyAnchorAt ?? this.baseUrgencyAnchorAt,
      deadline: identical(deadline, _unchanged)
          ? this.deadline
          : deadline as DateTime?,
      estimatedMinutes: identical(estimatedMinutes, _unchanged)
          ? this.estimatedMinutes
          : estimatedMinutes as int?,
      workload: workload ?? this.workload,
      progress: progress ?? this.progress,
      includeInWeeklyReport:
          includeInWeeklyReport ?? this.includeInWeeklyReport,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: identical(completedAt, _unchanged)
          ? this.completedAt
          : completedAt as DateTime?,
      deletedAt: identical(deletedAt, _unchanged)
          ? this.deletedAt
          : deletedAt as DateTime?,
    );
  }

  static void _requireScore(String name, int value) {
    if (value < 0 || value > 100) {
      throw ArgumentError.value(value, name, 'must be between 0 and 100');
    }
  }
}
