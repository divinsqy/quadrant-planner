import '../quadrant/quadrant.dart';
import '../tasks/task_status.dart';
import 'planner_candidate.dart';
import 'work_calendar.dart';

class PlannerRanker {
  final WorkCalendar calendar;
  final int approachingDeadlineWorkdays;

  const PlannerRanker({
    required this.calendar,
    this.approachingDeadlineWorkdays = 5,
  });

  List<PlannerCandidate> rank(
    List<TaskPlanningSnapshot> tasks,
    DateTime now,
  ) {
    final candidates = <PlannerCandidate>[];

    for (final snapshot in tasks) {
      if (!_isExecutable(snapshot)) {
        continue;
      }
      candidates.add(_toCandidate(snapshot, now));
    }

    candidates.sort(_compare);
    return List.unmodifiable(candidates);
  }

  bool _isExecutable(TaskPlanningSnapshot snapshot) {
    if (!snapshot.dependenciesSatisfied) {
      return false;
    }
    return snapshot.task.status == TaskStatus.planned ||
        snapshot.task.status == TaskStatus.inProgress;
  }

  PlannerCandidate _toCandidate(
    TaskPlanningSnapshot snapshot,
    DateTime now,
  ) {
    final deadlineInfo = _deadlineInfo(snapshot, now);
    final tier = _tierFor(snapshot, deadlineInfo);
    final reasons = _reasonsFor(snapshot, tier, deadlineInfo);

    return PlannerCandidate(
      snapshot: snapshot,
      tier: tier,
      reasons: List.unmodifiable(reasons),
      deadlineWorkdaysRemaining: deadlineInfo?.workdaysRemaining,
    );
  }

  _DeadlineInfo? _deadlineInfo(
    TaskPlanningSnapshot snapshot,
    DateTime now,
  ) {
    final deadline = snapshot.task.deadline;
    if (deadline == null) {
      return null;
    }

    final localNow = now.toLocal();
    final localDeadline = deadline.toLocal();
    final nowDate = DateTime(localNow.year, localNow.month, localNow.day);
    final deadlineDate = DateTime(
      localDeadline.year,
      localDeadline.month,
      localDeadline.day,
    );

    final overdue = deadlineDate.isBefore(nowDate);
    if (overdue || deadlineDate == nowDate) {
      return _DeadlineInfo(
        workdaysRemaining: 0,
        overdue: overdue,
      );
    }

    final count = calendar.workdaysBetween(localNow, localDeadline);
    return _DeadlineInfo(
      workdaysRemaining: count.count,
      overdue: false,
    );
  }

  PlannerPriorityTier _tierFor(
    TaskPlanningSnapshot snapshot,
    _DeadlineInfo? deadline,
  ) {
    if (deadline != null && deadline.workdaysRemaining <= 1) {
      return PlannerPriorityTier.criticalDeadline;
    }

    switch (snapshot.quadrant) {
      case Quadrant.doNow:
        return PlannerPriorityTier.doNow;
      case Quadrant.plan:
        if (deadline != null &&
            deadline.workdaysRemaining <= approachingDeadlineWorkdays) {
          return PlannerPriorityTier.importantApproaching;
        }
        return PlannerPriorityTier.importantPlanned;
      case Quadrant.expedite:
        return PlannerPriorityTier.expedite;
      case Quadrant.lowPriority:
        return PlannerPriorityTier.lowPriority;
    }
  }

  List<RecommendationReason> _reasonsFor(
    TaskPlanningSnapshot snapshot,
    PlannerPriorityTier tier,
    _DeadlineInfo? deadline,
  ) {
    final reasons = <RecommendationReason>[];

    if (deadline != null) {
      if (deadline.overdue) {
        reasons.add(
          const RecommendationReason(
            kind: RecommendationReasonKind.overdue,
            message: '任务已逾期',
          ),
        );
      } else if (deadline.workdaysRemaining <= 1) {
        reasons.add(
          RecommendationReason(
            kind: RecommendationReasonKind.deadlineSoon,
            message: '截止仅剩 ${deadline.workdaysRemaining} 个工作日',
          ),
        );
      } else if (deadline.workdaysRemaining <= approachingDeadlineWorkdays) {
        reasons.add(
          RecommendationReason(
            kind: RecommendationReasonKind.deadlineApproaching,
            message: '截止剩余 ${deadline.workdaysRemaining} 个工作日',
          ),
        );
      }
    }

    switch (tier) {
      case PlannerPriorityTier.doNow:
        reasons.add(
          const RecommendationReason(
            kind: RecommendationReasonKind.importantUrgent,
            message: '当前位于重要且紧急象限',
          ),
        );
      case PlannerPriorityTier.importantApproaching:
      case PlannerPriorityTier.importantPlanned:
        reasons.add(
          const RecommendationReason(
            kind: RecommendationReasonKind.important,
            message: '任务重要性较高',
          ),
        );
      case PlannerPriorityTier.expedite:
        reasons.add(
          const RecommendationReason(
            kind: RecommendationReasonKind.urgent,
            message: '任务当前较紧急',
          ),
        );
      case PlannerPriorityTier.criticalDeadline:
      case PlannerPriorityTier.lowPriority:
        break;
    }

    if (snapshot.task.status == TaskStatus.inProgress) {
      reasons.add(
        const RecommendationReason(
          kind: RecommendationReasonKind.inProgress,
          message: '任务已经开始进行',
        ),
      );
    }

    final milestone = snapshot.milestoneWorkdaysRemaining;
    if (milestone != null && milestone <= approachingDeadlineWorkdays) {
      reasons.add(
        RecommendationReason(
          kind: RecommendationReasonKind.milestoneNearby,
          message: '关联里程碑剩余 $milestone 个工作日',
        ),
      );
    }

    if (snapshot.fitsCurrentSlot) {
      reasons.add(
        const RecommendationReason(
          kind: RecommendationReasonKind.fitsCurrentSlot,
          message: '预计时长适合当前可用时间',
        ),
      );
    }

    return reasons;
  }

  int _compare(PlannerCandidate a, PlannerCandidate b) {
    var result = a.tier.index.compareTo(b.tier.index);
    if (result != 0) {
      return result;
    }

    result = _compareDeadline(a.task.deadline, b.task.deadline);
    if (result != 0) {
      return result;
    }

    result = b.task.importance.compareTo(a.task.importance);
    if (result != 0) {
      return result;
    }

    result = _statusRank(a.task.status).compareTo(_statusRank(b.task.status));
    if (result != 0) {
      return result;
    }

    result = _nullableAscending(
      a.milestoneWorkdaysRemaining,
      b.milestoneWorkdaysRemaining,
    );
    if (result != 0) {
      return result;
    }

    result = _fitRank(a.fitsCurrentSlot).compareTo(_fitRank(b.fitsCurrentSlot));
    if (result != 0) {
      return result;
    }

    return a.task.id.compareTo(b.task.id);
  }

  static int _compareDeadline(DateTime? a, DateTime? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return a.compareTo(b);
  }

  static int _statusRank(TaskStatus status) {
    return status == TaskStatus.inProgress ? 0 : 1;
  }

  static int _fitRank(bool fits) => fits ? 0 : 1;

  static int _nullableAscending(int? a, int? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return a.compareTo(b);
  }
}

class _DeadlineInfo {
  final int workdaysRemaining;
  final bool overdue;

  const _DeadlineInfo({
    required this.workdaysRemaining,
    required this.overdue,
  });
}
