import 'planned_block.dart';
import 'planner_candidate.dart';
import 'work_schedule.dart';

enum UnscheduledReason {
  noAvailableWindow,
  noFittingWindow,
  missingEstimate,
}

class UnscheduledCandidate {
  final PlannerCandidate candidate;
  final UnscheduledReason reason;
  final int? remainingMinutes;

  const UnscheduledCandidate({
    required this.candidate,
    required this.reason,
    required this.remainingMinutes,
  });
}

class DayPlanSuggestion {
  final List<PlannedBlock> blocks;
  final List<UnscheduledCandidate> unscheduled;

  const DayPlanSuggestion({
    required this.blocks,
    required this.unscheduled,
  });
}

class PlannerEngine {
  const PlannerEngine();

  DayPlanSuggestion planDay({
    required DateTime date,
    required WorkSchedule schedule,
    required List<PlannerCandidate> candidates,
    required List<PlannedBlock> lockedBlocks,
  }) {
    final day = DateTime(date.year, date.month, date.day);
    final windows = _windowsForDate(schedule, day);
    final blocks = <PlannedBlock>[...lockedBlocks];
    final unscheduled = <UnscheduledCandidate>[];

    if (windows.isEmpty) {
      for (final candidate in candidates) {
        unscheduled.add(
          UnscheduledCandidate(
            candidate: candidate,
            reason: candidate.task.estimatedMinutes == null
                ? UnscheduledReason.missingEstimate
                : UnscheduledReason.noAvailableWindow,
            remainingMinutes: candidate.task.estimatedMinutes,
          ),
        );
      }
      return DayPlanSuggestion(
        blocks: List.unmodifiable(_sorted(blocks)),
        unscheduled: List.unmodifiable(unscheduled),
      );
    }

    var free = _subtractLocked(day, windows, lockedBlocks);

    for (final candidate in candidates) {
      final estimate = candidate.task.estimatedMinutes;
      if (estimate == null) {
        unscheduled.add(
          UnscheduledCandidate(
            candidate: candidate,
            reason: UnscheduledReason.missingEstimate,
            remainingMinutes: null,
          ),
        );
        continue;
      }

      if (estimate < 60) {
        final index = free.indexWhere(
          (slot) => slot.durationMinutes >= estimate,
        );
        if (index < 0) {
          unscheduled.add(
            UnscheduledCandidate(
              candidate: candidate,
              reason: UnscheduledReason.noFittingWindow,
              remainingMinutes: estimate,
            ),
          );
          continue;
        }

        final slot = free[index];
        blocks.add(_suggestedBlock(candidate.task.id, slot.start, estimate));
        free = _consumeSlot(free, index, estimate);
        continue;
      }

      if (!free.any((slot) => slot.durationMinutes >= 30)) {
        unscheduled.add(
          UnscheduledCandidate(
            candidate: candidate,
            reason: UnscheduledReason.noFittingWindow,
            remainingMinutes: estimate,
          ),
        );
        continue;
      }

      var remaining = estimate;
      while (remaining > 0) {
        final index = free.indexWhere(
          (slot) => slot.durationMinutes >= 30,
        );
        if (index < 0) {
          break;
        }

        final slot = free[index];
        final length = _nextChunkLength(
          remaining: remaining,
          slotLength: slot.durationMinutes,
        );
        if (length < 30) {
          break;
        }

        blocks.add(
          _suggestedBlock(candidate.task.id, slot.start, length),
        );
        free = _consumeSlot(free, index, length);
        remaining -= length;
      }

      if (remaining > 0) {
        unscheduled.add(
          UnscheduledCandidate(
            candidate: candidate,
            reason: UnscheduledReason.noFittingWindow,
            remainingMinutes: remaining,
          ),
        );
      }
    }

    return DayPlanSuggestion(
      blocks: List.unmodifiable(_sorted(blocks)),
      unscheduled: List.unmodifiable(unscheduled),
    );
  }

  List<_FreeSlot> _windowsForDate(
    WorkSchedule schedule,
    DateTime day,
  ) {
    final windows = schedule.hasDateOverride(day)
        ? schedule.dateOverride(day)
        : schedule.windowsForWeekday(day.weekday);

    return windows
        .map(
          (window) => _FreeSlot(
            start: day.add(Duration(minutes: window.startMinutes)),
            end: day.add(Duration(minutes: window.endMinutes)),
          ),
        )
        .toList(growable: false);
  }

  List<_FreeSlot> _subtractLocked(
    DateTime day,
    List<_FreeSlot> windows,
    List<PlannedBlock> lockedBlocks,
  ) {
    var free = <_FreeSlot>[...windows];

    final lockedForDay = lockedBlocks
        .where(
          (block) =>
              block.isLocked &&
              _sameLocalDate(block.start, day) &&
              block.end.isAfter(block.start),
        )
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    for (final block in lockedForDay) {
      final next = <_FreeSlot>[];
      for (final slot in free) {
        if (!block.end.isAfter(slot.start) ||
            !block.start.isBefore(slot.end)) {
          next.add(slot);
          continue;
        }

        if (block.start.isAfter(slot.start)) {
          next.add(
            _FreeSlot(
              start: slot.start,
              end: block.start.isBefore(slot.end) ? block.start : slot.end,
            ),
          );
        }
        if (block.end.isBefore(slot.end)) {
          next.add(
            _FreeSlot(
              start: block.end.isAfter(slot.start) ? block.end : slot.start,
              end: slot.end,
            ),
          );
        }
      }
      free = next.where((slot) => slot.durationMinutes > 0).toList();
    }

    free.sort((a, b) => a.start.compareTo(b.start));
    return free;
  }

  int _nextChunkLength({
    required int remaining,
    required int slotLength,
  }) {
    if (remaining <= slotLength) {
      return remaining;
    }

    final leaveAtLeastThirty = remaining - 30;
    return slotLength < leaveAtLeastThirty
        ? slotLength
        : leaveAtLeastThirty;
  }

  PlannedBlock _suggestedBlock(
    String taskId,
    DateTime start,
    int minutes,
  ) {
    final end = start.add(Duration(minutes: minutes));
    return PlannedBlock(
      id: 'suggested-' + taskId + '-' + start.millisecondsSinceEpoch.toString(),
      taskId: taskId,
      start: start,
      end: end,
      isLocked: false,
      source: PlanBlockSource.suggested,
    );
  }

  List<_FreeSlot> _consumeSlot(
    List<_FreeSlot> slots,
    int index,
    int minutes,
  ) {
    final next = <_FreeSlot>[...slots];
    final slot = next[index];
    final newStart = slot.start.add(Duration(minutes: minutes));

    if (!newStart.isBefore(slot.end)) {
      next.removeAt(index);
    } else {
      next[index] = _FreeSlot(start: newStart, end: slot.end);
    }
    return next;
  }

  List<PlannedBlock> _sorted(List<PlannedBlock> blocks) {
    final sorted = <PlannedBlock>[...blocks]
      ..sort((a, b) => a.start.compareTo(b.start));
    return sorted;
  }

  bool _sameLocalDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _FreeSlot {
  final DateTime start;
  final DateTime end;

  const _FreeSlot({
    required this.start,
    required this.end,
  });

  int get durationMinutes => end.difference(start).inMinutes;
}
