import 'dart:math' as math;

import '../planning/work_calendar.dart';
import '../tasks/task.dart';
import 'urgency_result.dart';

class UrgencyEngine {
  final WorkCalendar calendar;
  final double growthRatePerWorkday;

  const UrgencyEngine({
    required this.calendar,
    this.growthRatePerWorkday = 1.5,
  });

  UrgencyResult calculate(Task task, DateTime at) {
    final localAt = at.toLocal();
    final localAnchor = task.baseUrgencyAnchorAt.toLocal();

    final ageDays = calendar.workdaysBetween(localAnchor, localAt);
    final ageComponent = _clamp(
      task.baseUrgency + ageDays.count * growthRatePerWorkday,
    );

    var calendarEstimated =
        ageDays.isEstimated || calendar.isWorkday(localAt).isEstimated;
    double? deadlineComponent;

    final deadline = task.deadline;
    if (deadline != null) {
      final localDeadline = deadline.toLocal();
      if (_dateAtOrBefore(localDeadline, localAt)) {
        deadlineComponent = 100;
        calendarEstimated = calendarEstimated ||
            calendar.isWorkday(localDeadline).isEstimated;
      } else {
        final remaining = calendar.workdaysBetween(localAt, localDeadline);
        calendarEstimated = calendarEstimated || remaining.isEstimated;
        deadlineComponent = _clamp(
          100 * math.pow(2, -remaining.count / 3).toDouble(),
        );
      }
    }

    final combined = deadlineComponent == null
        ? ageComponent
        : math.max(ageComponent, deadlineComponent);

    return UrgencyResult(
      value: _clamp(combined).round(),
      ageComponent: ageComponent,
      deadlineComponent: deadlineComponent,
      calendarEstimated: calendarEstimated,
    );
  }

  static bool _dateAtOrBefore(DateTime candidate, DateTime reference) {
    final candidateDate =
        DateTime(candidate.year, candidate.month, candidate.day);
    final referenceDate =
        DateTime(reference.year, reference.month, reference.day);
    return !candidateDate.isAfter(referenceDate);
  }

  static double _clamp(num value) {
    return value.toDouble().clamp(0.0, 100.0);
  }
}
