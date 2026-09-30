enum PlanBlockSource {
  suggested,
  manual,
}

class PlannedBlock {
  final String id;
  final String taskId;
  final DateTime start;
  final DateTime end;
  final bool isLocked;
  final PlanBlockSource source;

  const PlannedBlock({
    required this.id,
    required this.taskId,
    required this.start,
    required this.end,
    required this.isLocked,
    required this.source,
  });

  int get durationMinutes => end.difference(start).inMinutes;
}
