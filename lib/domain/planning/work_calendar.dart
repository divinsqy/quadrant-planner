import 'work_schedule.dart';

class WorkdayDecision {
  final bool isWorkday;
  final bool isEstimated;

  const WorkdayDecision({
    required this.isWorkday,
    required this.isEstimated,
  });
}

class WorkdayCount {
  final int count;
  final bool isEstimated;

  const WorkdayCount({
    required this.count,
    required this.isEstimated,
  });
}

class WorkCalendar {
  final WorkSchedule schedule;
  final Set<int> coveredYears;
  final Set<String> holidays;

  const WorkCalendar({
    required this.schedule,
    required this.coveredYears,
    required this.holidays,
  });

  WorkdayDecision isWorkday(DateTime localDate) {
    final date = DateTime(localDate.year, localDate.month, localDate.day);

    if (schedule.hasDateOverride(date)) {
      return WorkdayDecision(
        isWorkday: schedule.dateOverride(date).isNotEmpty,
        isEstimated: false,
      );
    }

    final covered = coveredYears.contains(date.year);
    final isWeekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    if (isWeekend) {
      return WorkdayDecision(
        isWorkday: false,
        isEstimated: !covered,
      );
    }

    if (covered && holidays.contains(_dateKey(date))) {
      return const WorkdayDecision(
        isWorkday: false,
        isEstimated: false,
      );
    }

    final hasWorkingWindow =
        schedule.windowsForWeekday(date.weekday).isNotEmpty;
    return WorkdayDecision(
      isWorkday: hasWorkingWindow,
      isEstimated: !covered,
    );
  }

  List<TimeWindow> availableWindows(DateTime localDate) {
    final date = DateTime(localDate.year, localDate.month, localDate.day);
    if (schedule.hasDateOverride(date)) {
      return schedule.dateOverride(date);
    }
    if (!isWorkday(date).isWorkday) {
      return const [];
    }
    return schedule.windowsForWeekday(date.weekday);
  }

  WorkdayCount workdaysBetween(DateTime from, DateTime to) {
    var cursor = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(cursor)) {
      return const WorkdayCount(count: 0, isEstimated: false);
    }

    var count = 0;
    var estimated = false;
    while (cursor.isBefore(end)) {
      cursor = cursor.add(const Duration(days: 1));
      final decision = isWorkday(cursor);
      estimated = estimated || decision.isEstimated;
      if (decision.isWorkday) {
        count += 1;
      }
    }

    return WorkdayCount(count: count, isEstimated: estimated);
  }

  static String _dateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
