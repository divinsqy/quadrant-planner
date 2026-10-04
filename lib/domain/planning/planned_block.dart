enum PlanBlockSource { suggested, manual }

class PlannedBlock {
  final String id;
  final String taskId;
  final DateTime start;
  final DateTime end;
  final bool isLocked;
  final PlanBlockSource source;
  final DateTime? completedAt;

  const PlannedBlock({
    required this.id,
    required this.taskId,
    required this.start,
    required this.end,
    required this.isLocked,
    required this.source,
    this.completedAt,
  });

  int get durationMinutes => end.difference(start).inMinutes;

  PlannedBlock copyWith({
    DateTime? start,
    DateTime? end,
    bool? isLocked,
    PlanBlockSource? source,
  }) => PlannedBlock(
    id: id,
    taskId: taskId,
    start: start ?? this.start,
    end: end ?? this.end,
    isLocked: isLocked ?? this.isLocked,
    source: source ?? this.source,
    completedAt: completedAt,
  );
}
