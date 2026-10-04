import 'package:quadrant_planner/domain/tasks/task.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/tasks/workload.dart';
import 'package:quadrant_planner/domain/planning/planner_candidate.dart';
import 'package:quadrant_planner/domain/quadrant/quadrant.dart';

TaskPlanningSnapshot fixtureSnapshot(int index) {
  final task = Task.create(
    id: 't-$index',
    title: 'RTL AXI $index',
    description: 'UVM coverage',
    status: TaskStatus.planned,
    projectId: null,
    importance: (index * 37) % 101,
    baseUrgency: index % 101,
    baseUrgencyAnchorAt: DateTime(2026, 10, 5),
    deadline: null,
    estimatedMinutes: 60,
    workload: Workload.medium,
    progress: 0,
    includeInWeeklyReport: true,
    createdAt: DateTime(2026, 10, 5),
    updatedAt: DateTime(2026, 10, 5),
  );
  return TaskPlanningSnapshot(
    task: task,
    currentUrgency: index % 101,
    quadrant: Quadrant.doNow,
    dependenciesSatisfied: true,
    milestoneWorkdaysRemaining: null,
    fitsCurrentSlot: true,
  );
}
