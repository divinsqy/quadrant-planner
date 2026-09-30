import '../quadrant/quadrant.dart';
import '../tasks/task.dart';

enum PlannerPriorityTier {
  criticalDeadline,
  doNow,
  importantApproaching,
  expedite,
  importantPlanned,
  lowPriority,
}

enum RecommendationReasonKind {
  overdue,
  deadlineSoon,
  deadlineApproaching,
  importantUrgent,
  important,
  urgent,
  inProgress,
  milestoneNearby,
  fitsCurrentSlot,
}

class RecommendationReason {
  final RecommendationReasonKind kind;
  final String message;

  const RecommendationReason({
    required this.kind,
    required this.message,
  });
}

class TaskPlanningSnapshot {
  final Task task;
  final int currentUrgency;
  final Quadrant quadrant;
  final bool dependenciesSatisfied;
  final int? milestoneWorkdaysRemaining;
  final bool fitsCurrentSlot;

  const TaskPlanningSnapshot({
    required this.task,
    required this.currentUrgency,
    required this.quadrant,
    required this.dependenciesSatisfied,
    required this.milestoneWorkdaysRemaining,
    required this.fitsCurrentSlot,
  });
}

class PlannerCandidate {
  final TaskPlanningSnapshot snapshot;
  final PlannerPriorityTier tier;
  final List<RecommendationReason> reasons;
  final int? deadlineWorkdaysRemaining;

  const PlannerCandidate({
    required this.snapshot,
    required this.tier,
    required this.reasons,
    required this.deadlineWorkdaysRemaining,
  });

  Task get task => snapshot.task;
  int get currentUrgency => snapshot.currentUrgency;
  Quadrant get quadrant => snapshot.quadrant;
  bool get fitsCurrentSlot => snapshot.fitsCurrentSlot;
  int? get milestoneWorkdaysRemaining =>
      snapshot.milestoneWorkdaysRemaining;
}
