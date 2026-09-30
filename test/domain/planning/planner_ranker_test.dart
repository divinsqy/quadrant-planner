import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/planning/planner_candidate.dart';
import 'package:quadrant_planner/domain/planning/planner_ranker.dart';
import 'package:quadrant_planner/domain/planning/work_calendar.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/quadrant/quadrant.dart';
import 'package:quadrant_planner/domain/tasks/task.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/tasks/workload.dart';

void main() {
  late PlannerRanker ranker;

  setUp(() {
    ranker = PlannerRanker(
      calendar: WorkCalendar(
        schedule: WorkSchedule.standard(),
        coveredYears: const {2026},
        holidays: const {},
      ),
    );
  });

  test('filters out non executable statuses and dependency-blocked tasks', () {
    final snapshots = [
      snapshot('inbox', status: TaskStatus.inbox),
      snapshot('planned', status: TaskStatus.planned),
      snapshot('running', status: TaskStatus.inProgress),
      snapshot('waiting', status: TaskStatus.waiting),
      snapshot('done', status: TaskStatus.completed),
      snapshot('cancelled', status: TaskStatus.cancelled),
      snapshot(
        'blocked',
        status: TaskStatus.planned,
        dependenciesSatisfied: false,
      ),
    ];

    final ranked = ranker.rank(snapshots, DateTime(2026, 9, 28, 9));

    expect(ranked.map((item) => item.task.id).toList(), [
      'running',
      'planned',
    ]);
  });

  test('critical deadline tasks rank before Q1 then approaching Q2 Q3 and low', () {
    final now = DateTime(2026, 9, 28, 9);
    final ranked = ranker.rank([
      snapshot(
        'low',
        quadrant: Quadrant.lowPriority,
        importance: 20,
        urgency: 20,
      ),
      snapshot(
        'q3',
        quadrant: Quadrant.expedite,
        importance: 20,
        urgency: 80,
      ),
      snapshot(
        'q2-soon',
        quadrant: Quadrant.plan,
        importance: 80,
        urgency: 30,
        deadline: DateTime(2026, 10, 2),
      ),
      snapshot(
        'q1',
        quadrant: Quadrant.doNow,
        importance: 80,
        urgency: 80,
      ),
      snapshot(
        'due-tomorrow',
        quadrant: Quadrant.lowPriority,
        importance: 10,
        urgency: 10,
        deadline: DateTime(2026, 9, 29),
      ),
      snapshot(
        'overdue',
        quadrant: Quadrant.lowPriority,
        importance: 10,
        urgency: 10,
        deadline: DateTime(2026, 9, 25),
      ),
    ], now);

    expect(ranked.map((item) => item.task.id).toList(), [
      'overdue',
      'due-tomorrow',
      'q1',
      'q2-soon',
      'q3',
      'low',
    ]);
    expect(ranked[0].tier, PlannerPriorityTier.criticalDeadline);
    expect(ranked[2].tier, PlannerPriorityTier.doNow);
    expect(ranked[3].tier, PlannerPriorityTier.importantApproaching);
    expect(ranked[4].tier, PlannerPriorityTier.expedite);
  });

  test('same-tier ordering applies deadline then importance then in-progress', () {
    final now = DateTime(2026, 9, 28, 9);
    final ranked = ranker.rank([
      snapshot(
        'later',
        quadrant: Quadrant.doNow,
        importance: 95,
        urgency: 80,
        deadline: DateTime(2026, 10, 5),
      ),
      snapshot(
        'earlier-low-importance',
        quadrant: Quadrant.doNow,
        importance: 70,
        urgency: 80,
        deadline: DateTime(2026, 10, 2),
      ),
      snapshot(
        'earlier-high-importance-planned',
        quadrant: Quadrant.doNow,
        importance: 90,
        urgency: 80,
        deadline: DateTime(2026, 10, 2),
      ),
      snapshot(
        'earlier-high-importance-running',
        status: TaskStatus.inProgress,
        quadrant: Quadrant.doNow,
        importance: 90,
        urgency: 80,
        deadline: DateTime(2026, 10, 2),
      ),
    ], now);

    expect(ranked.map((item) => item.task.id).toList(), [
      'earlier-high-importance-running',
      'earlier-high-importance-planned',
      'earlier-low-importance',
      'later',
    ]);
  });

  test('milestone proximity then current-slot fit break remaining ties', () {
    final ranked = ranker.rank([
      snapshot(
        'milestone-far',
        milestoneWorkdaysRemaining: 5,
        fitsCurrentSlot: true,
      ),
      snapshot(
        'milestone-near-no-fit',
        milestoneWorkdaysRemaining: 2,
        fitsCurrentSlot: false,
      ),
      snapshot(
        'milestone-near-fit',
        milestoneWorkdaysRemaining: 2,
        fitsCurrentSlot: true,
      ),
    ], DateTime(2026, 9, 28, 9));

    expect(ranked.map((item) => item.task.id).toList(), [
      'milestone-near-fit',
      'milestone-near-no-fit',
      'milestone-far',
    ]);
  });

  test('candidate exposes explainable reasons rather than a synthetic score', () {
    final ranked = ranker.rank([
      snapshot(
        'running-q1',
        status: TaskStatus.inProgress,
        quadrant: Quadrant.doNow,
        importance: 88,
        urgency: 82,
      ),
    ], DateTime(2026, 9, 28, 9));

    expect(
      ranked.single.reasons.map((reason) => reason.kind),
      containsAll([
        RecommendationReasonKind.importantUrgent,
        RecommendationReasonKind.inProgress,
      ]),
    );
    expect(ranked.single.reasons.every((reason) => reason.message.isNotEmpty), isTrue);
  });

  test('important planned tasks without approaching deadline remain above low priority', () {
    final ranked = ranker.rank([
      snapshot(
        'low',
        quadrant: Quadrant.lowPriority,
        importance: 20,
        urgency: 20,
      ),
      snapshot(
        'important-later',
        quadrant: Quadrant.plan,
        importance: 85,
        urgency: 20,
        deadline: DateTime(2026, 11, 30),
      ),
    ], DateTime(2026, 9, 28, 9));

    expect(ranked.map((item) => item.task.id).toList(), [
      'important-later',
      'low',
    ]);
    expect(ranked.first.tier, PlannerPriorityTier.importantPlanned);
  });
}

TaskPlanningSnapshot snapshot(
  String id, {
  TaskStatus status = TaskStatus.planned,
  Quadrant quadrant = Quadrant.doNow,
  int importance = 80,
  int urgency = 80,
  DateTime? deadline,
  bool dependenciesSatisfied = true,
  int? milestoneWorkdaysRemaining,
  bool fitsCurrentSlot = true,
}) {
  final created = DateTime(2026, 9, 1);
  final task = Task.create(
    id: id,
    title: id,
    description: '',
    status: status,
    projectId: null,
    importance: importance,
    baseUrgency: urgency,
    baseUrgencyAnchorAt: created,
    deadline: deadline,
    estimatedMinutes: 60,
    workload: Workload.medium,
    progress: 0,
    includeInWeeklyReport: true,
    createdAt: created,
    updatedAt: created,
  );

  return TaskPlanningSnapshot(
    task: task,
    currentUrgency: urgency,
    quadrant: quadrant,
    dependenciesSatisfied: dependenciesSatisfied,
    milestoneWorkdaysRemaining: milestoneWorkdaysRemaining,
    fitsCurrentSlot: fitsCurrentSlot,
  );
}
