import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/planning/planned_block.dart';
import 'package:quadrant_planner/domain/planning/planner_candidate.dart';
import 'package:quadrant_planner/domain/planning/planner_engine.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/quadrant/quadrant.dart';
import 'package:quadrant_planner/domain/tasks/task.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/tasks/workload.dart';

void main() {
  const engine = PlannerEngine();

  test('standard day splits a long task around the 12 to 14 lunch break', () {
    final result = engine.planDay(
      date: DateTime(2026, 9, 28),
      schedule: WorkSchedule.standard(),
      candidates: [candidate('long', minutes: 240)],
      lockedBlocks: const [],
    );

    expect(result.unscheduled, isEmpty);
    expect(result.blocks, hasLength(2));
    expect(_clock(result.blocks[0].start), '09:00');
    expect(_clock(result.blocks[0].end), '12:00');
    expect(_clock(result.blocks[1].start), '14:00');
    expect(_clock(result.blocks[1].end), '15:00');
    expect(
      result.blocks.any(
        (block) =>
            block.start.hour < 14 &&
            (block.end.hour > 12 ||
                (block.end.hour == 12 && block.end.minute > 0)),
      ),
      isFalse,
    );
  });

  test('weekend has no available blocks by default', () {
    final result = engine.planDay(
      date: DateTime(2026, 10, 3),
      schedule: WorkSchedule.standard(),
      candidates: [candidate('weekend', minutes: 60)],
      lockedBlocks: const [],
    );

    expect(result.blocks, isEmpty);
    expect(result.unscheduled, hasLength(1));
    expect(result.unscheduled.single.reason, UnscheduledReason.noAvailableWindow);
  });

  test('one-date Saturday override opens only the requested window', () {
    final schedule = WorkSchedule.standard().withDateOverride(
      DateTime(2026, 10, 3),
      const [TimeWindow(startMinutes: 10 * 60, endMinutes: 12 * 60)],
    );

    final result = engine.planDay(
      date: DateTime(2026, 10, 3),
      schedule: schedule,
      candidates: [candidate('weekend', minutes: 60)],
      lockedBlocks: const [],
    );

    expect(result.unscheduled, isEmpty);
    expect(result.blocks, hasLength(1));
    expect(_clock(result.blocks.single.start), '10:00');
    expect(_clock(result.blocks.single.end), '11:00');
  });

  test('59 minute task is not split across two short windows', () {
    final schedule = WorkSchedule(
      weekdayWindows: {
        DateTime.monday: const [
          TimeWindow(startMinutes: 9 * 60, endMinutes: 9 * 60 + 30),
          TimeWindow(startMinutes: 10 * 60, endMinutes: 10 * 60 + 30),
        ],
      },
    );

    final result = engine.planDay(
      date: DateTime(2026, 9, 28),
      schedule: schedule,
      candidates: [candidate('short', minutes: 59)],
      lockedBlocks: const [],
    );

    expect(result.blocks, isEmpty);
    expect(result.unscheduled.single.reason, UnscheduledReason.noFittingWindow);
    expect(result.unscheduled.single.remainingMinutes, 59);
  });

  test('60 minute task may split into two 30 minute blocks', () {
    final schedule = WorkSchedule(
      weekdayWindows: {
        DateTime.monday: const [
          TimeWindow(startMinutes: 9 * 60, endMinutes: 9 * 60 + 30),
          TimeWindow(startMinutes: 10 * 60, endMinutes: 10 * 60 + 30),
        ],
      },
    );

    final result = engine.planDay(
      date: DateTime(2026, 9, 28),
      schedule: schedule,
      candidates: [candidate('split', minutes: 60)],
      lockedBlocks: const [],
    );

    expect(result.unscheduled, isEmpty);
    expect(result.blocks, hasLength(2));
    expect(result.blocks.map((block) => block.durationMinutes).toList(), [30, 30]);
  });

  test('replanning preserves locked blocks exactly and packs around them', () {
    final locked = PlannedBlock(
      id: 'locked',
      taskId: 'locked-task',
      start: DateTime(2026, 9, 28, 9),
      end: DateTime(2026, 9, 28, 10),
      isLocked: true,
      source: PlanBlockSource.manual,
    );

    final result = engine.planDay(
      date: DateTime(2026, 9, 28),
      schedule: WorkSchedule.standard(),
      candidates: [candidate('next', minutes: 120)],
      lockedBlocks: [locked],
    );

    expect(result.blocks.first, same(locked));
    final next = result.blocks.singleWhere((block) => block.taskId == 'next');
    expect(_clock(next.start), '10:00');
    expect(_clock(next.end), '12:00');
  });

  test('multiple candidates never create overlapping blocks', () {
    final result = engine.planDay(
      date: DateTime(2026, 9, 28),
      schedule: WorkSchedule.standard(),
      candidates: [
        candidate('first', minutes: 120),
        candidate('second', minutes: 120),
        candidate('third', minutes: 90),
      ],
      lockedBlocks: const [],
    );

    final sorted = [...result.blocks]..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < sorted.length; i += 1) {
      expect(sorted[i].start.isBefore(sorted[i - 1].end), isFalse);
    }
    expect(
      sorted.every((block) => block.durationMinutes > 0),
      isTrue,
    );
  });

  test('missing estimate stays unscheduled instead of inventing a duration', () {
    final result = engine.planDay(
      date: DateTime(2026, 9, 28),
      schedule: WorkSchedule.standard(),
      candidates: [candidate('unknown', minutes: null)],
      lockedBlocks: const [],
    );

    expect(result.blocks, isEmpty);
    expect(result.unscheduled.single.reason, UnscheduledReason.missingEstimate);
  });

  test('split planner avoids a final fragment smaller than 30 minutes', () {
    final schedule = WorkSchedule(
      weekdayWindows: {
        DateTime.monday: const [
          TimeWindow(startMinutes: 9 * 60, endMinutes: 10 * 60),
          TimeWindow(startMinutes: 11 * 60, endMinutes: 11 * 60 + 30),
        ],
      },
    );

    final result = engine.planDay(
      date: DateTime(2026, 9, 28),
      schedule: schedule,
      candidates: [candidate('eighty', minutes: 80)],
      lockedBlocks: const [],
    );

    expect(result.unscheduled, isEmpty);
    expect(result.blocks.map((block) => block.durationMinutes).toList(), [50, 30]);
  });
}

PlannerCandidate candidate(String id, {required int? minutes}) {
  final created = DateTime(2026, 9, 1);
  final task = Task.create(
    id: id,
    title: id,
    description: '',
    status: TaskStatus.planned,
    projectId: null,
    importance: 80,
    baseUrgency: 80,
    baseUrgencyAnchorAt: created,
    deadline: null,
    estimatedMinutes: minutes,
    workload: Workload.medium,
    progress: 0,
    includeInWeeklyReport: true,
    createdAt: created,
    updatedAt: created,
  );
  return PlannerCandidate(
    snapshot: TaskPlanningSnapshot(
      task: task,
      currentUrgency: 80,
      quadrant: Quadrant.doNow,
      dependenciesSatisfied: true,
      milestoneWorkdaysRemaining: null,
      fitsCurrentSlot: true,
    ),
    tier: PlannerPriorityTier.doNow,
    reasons: const [],
    deadlineWorkdaysRemaining: null,
  );
}

String _clock(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
