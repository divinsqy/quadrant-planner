class TimeWindow {
  final int startMinutes;
  final int endMinutes;

  const TimeWindow({
    required this.startMinutes,
    required this.endMinutes,
  });

  TimeWindow validate() {
    if (startMinutes < 0 ||
        startMinutes >= 24 * 60 ||
        endMinutes <= 0 ||
        endMinutes > 24 * 60 ||
        startMinutes >= endMinutes) {
      throw ArgumentError(
        'time window must satisfy 0 <= start < end <= 1440',
      );
    }
    return this;
  }

  int get durationMinutes => endMinutes - startMinutes;

  @override
  bool operator ==(Object other) {
    return other is TimeWindow &&
        other.startMinutes == startMinutes &&
        other.endMinutes == endMinutes;
  }

  @override
  int get hashCode => Object.hash(startMinutes, endMinutes);
}

class WorkSchedule {
  final Map<int, List<TimeWindow>> weekdayWindows;
  final Map<String, List<TimeWindow>> _dateOverrides;

  WorkSchedule({
    required Map<int, List<TimeWindow>> weekdayWindows,
    Map<String, List<TimeWindow>> dateOverrides = const {},
  })  : weekdayWindows = _validateWeekdayWindows(weekdayWindows),
        _dateOverrides = _validateDateOverrides(dateOverrides);

  factory WorkSchedule.standard() {
    const windows = [
      TimeWindow(startMinutes: 9 * 60, endMinutes: 12 * 60),
      TimeWindow(startMinutes: 14 * 60, endMinutes: 18 * 60),
    ];
    return WorkSchedule(
      weekdayWindows: {
        DateTime.monday: windows,
        DateTime.tuesday: windows,
        DateTime.wednesday: windows,
        DateTime.thursday: windows,
        DateTime.friday: windows,
      },
    );
  }

  WorkSchedule withDateOverride(
    DateTime localDate,
    List<TimeWindow> windows,
  ) {
    final next = Map<String, List<TimeWindow>>.from(_dateOverrides);
    next[_dateKey(localDate)] = List<TimeWindow>.from(windows);
    return WorkSchedule(
      weekdayWindows: weekdayWindows,
      dateOverrides: next,
    );
  }

  bool hasDateOverride(DateTime localDate) {
    return _dateOverrides.containsKey(_dateKey(localDate));
  }

  List<TimeWindow> dateOverride(DateTime localDate) {
    return _dateOverrides[_dateKey(localDate)] ?? const [];
  }

  List<TimeWindow> windowsForWeekday(int weekday) {
    return weekdayWindows[weekday] ?? const [];
  }

  static Map<int, List<TimeWindow>> _validateWeekdayWindows(
    Map<int, List<TimeWindow>> input,
  ) {
    final output = <int, List<TimeWindow>>{};
    for (final entry in input.entries) {
      if (entry.key < DateTime.monday || entry.key > DateTime.sunday) {
        throw ArgumentError.value(entry.key, 'weekday');
      }
      output[entry.key] = _validatedWindows(entry.value);
    }
    return Map.unmodifiable(output);
  }

  static Map<String, List<TimeWindow>> _validateDateOverrides(
    Map<String, List<TimeWindow>> input,
  ) {
    return Map.unmodifiable({
      for (final entry in input.entries)
        entry.key: _validatedWindows(entry.value),
    });
  }

  static List<TimeWindow> _validatedWindows(List<TimeWindow> input) {
    final sorted = input.map((window) => window.validate()).toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    for (var index = 1; index < sorted.length; index += 1) {
      if (sorted[index].startMinutes < sorted[index - 1].endMinutes) {
        throw ArgumentError('time windows must not overlap');
      }
    }
    return List.unmodifiable(sorted);
  }

  static String _dateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
